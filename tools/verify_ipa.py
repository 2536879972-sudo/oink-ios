#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_ipa.py - 校验改包结果：结构 / 注入命令 / 签名残留 / 执行位

用法:
    python verify_ipa.py out.ipa
    python verify_ipa.py out.ipa --expect-dylib hook.dylib
"""
import argparse
import plistlib
import struct
import sys
import zipfile

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from macho_inject import (FAT_MAGIC, FAT_MAGIC_64, LC_LOAD_DYLIB,  # noqa: E402
                          MH_MAGIC, MH_MAGIC_64)


def read_cmds(data, base=0):
    """返回 (magic_desc, [(cmd, cmdsize, payload_str)], is64)"""
    magic = struct.unpack_from("<I", data, base)[0]
    if magic == MH_MAGIC_64:
        hdr, is64 = 32, True
    elif magic == MH_MAGIC:
        hdr, is64 = 28, False
    else:
        return None, [], False
    ncmds = struct.unpack_from("<I", data, base + 16)[0]
    out = []
    off = base + hdr
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        payload = b""
        if cmd == LC_LOAD_DYLIB:
            name_off = struct.unpack_from("<I", data, off + 8)[0]
            start = off + name_off
            end = data.find(b"\x00", start)
            payload = data[start:end if end > 0 else start + 256]
        out.append((cmd, cmdsize, payload))
        off += cmdsize
    return magic, out, is64


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ipa")
    ap.add_argument("--expect-dylib", action="append", default=[])
    a = ap.parse_args()

    ok = True
    with zipfile.ZipFile(a.ipa) as z:
        names = z.namelist()
        print("[*] 条目数: %d" % len(names))
        if not any(n.startswith("Payload/") for n in names):
            print("[-] 缺少 Payload/ 根目录 —— 全能签会拒签")
            ok = False
        apps = {n.split("/")[1] for n in names if n.startswith("Payload/") and "/" in n[8:]}
        print("[*] App: %s" % apps)
        if len(apps) != 1:
            print("[-] Payload 下 .app 数量异常")
            ok = False

        app_dir = "Payload/%s" % list(apps)[0]
        info_raw = z.read(app_dir + "/Info.plist")
        info = plistlib.loads(info_raw)
        exe = info["CFBundleExecutable"]
        print("[*] BundleID: %s" % info.get("CFBundleIdentifier"))
        print("[*] 显示名 : %s" % info.get("CFBundleDisplayName"))
        print("[*] 主二进制: %s" % exe)

        # 签名残留
        leftovers = [n for n in names if "_CodeSignature" in n or n.endswith("embedded.mobileprovision")]
        if leftovers:
            print("[!] 仍有签名残留 %d 项（全能签通常会覆盖，但建议清干净）" % len(leftovers))
        else:
            print("[+] 无签名残留")

        # 主二进制检查
        exe_path = "%s/%s" % (app_dir, exe)
        if exe_path not in names:
            print("[-] 主二进制不在 IPA 里: %s" % exe_path)
            return 1
        data = z.read(exe_path)
        zi = z.getinfo(exe_path)
        mode = (zi.external_attr >> 16) & 0o777
        print("[*] 主二进制权限: 0o%o %s" % (mode, "OK" if mode & 0o100 else "<-- 无执行位，装完会闪退"))

        magic0 = struct.unpack_from(">I", data, 0)[0]
        slices = []
        if magic0 in (FAT_MAGIC, FAT_MAGIC_64):
            nfat = struct.unpack_from(">I", data, 4)[0]
            ent = 20 if magic0 == FAT_MAGIC else 32
            for i in range(nfat):
                b = 8 + i * ent
                if magic0 == FAT_MAGIC:
                    _, _, off, size, _ = struct.unpack_from(">IIIII", data, b)
                else:
                    _, _, off, size, _, _ = struct.unpack_from(">IIQQII", data, b)
                slices.append((off, size))
            print("[*] FAT 二进制，%d 个 slice" % nfat)
        else:
            slices.append((0, len(data)))

        found = []
        for off, size in slices:
            m, cmds, is64 = read_cmds(data, off)
            if m is None:
                print("[-] slice@%d 不是 Mach-O" % off)
                ok = False
                continue
            dylibs = [p.decode("utf-8", "ignore") for c, s, p in cmds if c == LC_LOAD_DYLIB]
            found.extend(dylibs)
            has_sig = any(c == 0x1D for c, s, p in cmds)
            print("    slice@%-8d %s  LC_CODE_SIGNATURE=%s  dylibs=%s"
                  % (off, "arm64/64" if is64 else "32", "有" if has_sig else "已剥离", dylibs))

        for want in a.expect_dylib:
            hit = [d for d in found if want in d]
            if hit:
                print("[+] 注入确认: %s" % hit[0])
            else:
                print("[-] 未找到注入: %s" % want)
                ok = False

    print("\n[%s]" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
