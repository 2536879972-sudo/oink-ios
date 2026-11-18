#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
macho_inject.py - 纯 Python Mach-O dylib 注入器（零依赖，Windows 可直接跑）

支持:
  * 64 位 / 32 位 Mach-O
  * FAT(通用)二进制，逐 slice 注入
  * 自动剥离 LC_CODE_SIGNATURE（注入后原签名必然失效，必须去掉）

能力等价于 macOS 的 insert_dylib，但不需要 Mac、不需要 optool。

用法:
    python macho_inject.py <macho文件> "@executable_path/hook.dylib"
    python macho_inject.py App -o App.patched "@executable_path/hook.dylib"
    python macho_inject.py App --keep-codesig "@executable_path/hook.dylib"

原理:
    Mach-O 的 load commands 紧跟在 header 之后，而 __TEXT 段第一个 section
    的数据通常从 0x4000 开始，中间有一大块 header pad。注入器把原有
    load commands 重建（去掉签名命令、追加 LC_LOAD_DYLIB），写回 header pad，
    同时更新 ncmds / sizeofcmds。文件总大小不变，所有 section offset 不变。
"""
import argparse
import os
import struct
import sys

MH_MAGIC = 0xFEEDFACE
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_SEGMENT = 0x01
LC_LOAD_DYLIB = 0x0C
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D


def _align(v, a=8):
    return (v + a - 1) // a * a


def _dylib_cmd(path):
    """构造一条 LC_LOAD_DYLIB 命令。dylib_command 固定 24 字节。"""
    raw = path.encode("utf-8") + b"\x00"
    total = _align(24 + len(raw))
    buf = bytearray(total)
    # cmd, cmdsize, name.offset, timestamp, current_version, compatibility_version
    struct.pack_into("<IIIIII", buf, 0, LC_LOAD_DYLIB, total, 24, 2, 0x10000, 0x10000)
    buf[24:24 + len(raw)] = raw
    return bytes(buf)


def _headerpad(data, is64):
    """计算 header pad 上界：__TEXT 段内第一个 section 的 file offset。"""
    ncmds, _ = struct.unpack_from("<II", data, 16)
    hdr = 32 if is64 else 28
    off = hdr
    pads = []

    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize < 8 or off + cmdsize > len(data):
            break

        if cmd == LC_SEGMENT_64:
            segname = data[off + 8:off + 24].rstrip(b"\x00").decode("ascii", "ignore")
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            if segname == "__TEXT":
                for i in range(nsects):
                    s = off + 72 + i * 80          # section_64 = 80 字节, offset 在 +48
                    if s + 52 > len(data):
                        break
                    sec_off = struct.unpack_from("<I", data, s + 48)[0]
                    if sec_off:
                        pads.append(sec_off)
        elif cmd == LC_SEGMENT:
            segname = data[off + 8:off + 24].rstrip(b"\x00").decode("ascii", "ignore")
            nsects = struct.unpack_from("<I", data, off + 48)[0]
            if segname == "__TEXT":
                for i in range(nsects):
                    s = off + 56 + i * 68          # section = 68 字节, offset 在 +40
                    if s + 44 > len(data):
                        break
                    sec_off = struct.unpack_from("<I", data, s + 40)[0]
                    if sec_off:
                        pads.append(sec_off)
        off += cmdsize

    if pads:
        return min(pads)

    # 兜底：所有段里最小的非零 fileoff
    off = hdr
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize < 8:
            break
        if cmd == LC_SEGMENT_64:
            foff = struct.unpack_from("<Q", data, off + 40)[0]
            if foff:
                pads.append(foff)
        elif cmd == LC_SEGMENT:
            foff = struct.unpack_from("<I", data, off + 32)[0]
            if foff:
                pads.append(foff)
        off += cmdsize
    return min(pads) if pads else 0x4000


def patch_thin(data, dylib_path, strip_codesig=True):
    """对单个（非 FAT）Mach-O 注入 LC_LOAD_DYLIB，返回新 bytes。"""
    if len(data) < 32:
        raise ValueError("文件太小，不是 Mach-O")
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic == MH_MAGIC_64:
        is64 = True
    elif magic == MH_MAGIC:
        is64 = False
    else:
        raise ValueError("不是 thin Mach-O (magic=0x%08x)" % magic)

    hdr = 32 if is64 else 28
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    pad = _headerpad(data, is64)

    cmds = []
    off = hdr
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize < 8 or off + cmdsize > len(data):
            raise ValueError("load commands 解析失败 @0x%x" % off)
        cmds.append((cmd, data[off:off + cmdsize]))
        off += cmdsize

    kept = []
    for cmd, blob in cmds:
        if strip_codesig and cmd == LC_CODE_SIGNATURE:
            continue
        kept.append(blob)
    kept.append(_dylib_cmd(dylib_path))

    new_size = sum(len(b) for b in kept)
    need = hdr + new_size
    if need > pad:
        raise ValueError(
            "header pad 不足：需要 %d 字节，可用 %d 字节。"
            "该二进制编译时没留 headerpad，请用 "
            "-Wl,-headerpad_max_install_names 重新编译，或改用 fat 注入方式。"
            % (need, pad)
        )

    out = bytearray(data)
    blob = b"".join(kept)
    out[hdr:hdr + len(blob)] = blob
    if pad > need:
        out[need:pad] = b"\x00" * (pad - need)
    struct.pack_into("<II", out, 16, len(kept), new_size)
    return bytes(out)


def patch_fat(data, dylib_path, strip_codesig=True):
    """对 FAT（通用）二进制逐 slice 注入。所有 slice 共用同一个加载路径。"""
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        raise ValueError("不是 FAT Mach-O")
    nfat = struct.unpack_from(">I", data, 4)[0]
    out = bytearray(data)
    entsize = 20 if magic == FAT_MAGIC else 32
    done = []
    for i in range(nfat):
        base = 8 + i * entsize
        if magic == FAT_MAGIC:
            cputype, cpusub, offset, size, _ = struct.unpack_from(">IIIII", data, base)
        else:
            cputype, cpusub, offset, size, _, _ = struct.unpack_from(">IIQQII", data, base)
        sl = bytes(data[offset:offset + size])
        new = patch_thin(sl, dylib_path, strip_codesig)
        if len(new) != size:
            raise ValueError("slice 尺寸变化，拒绝写入（cputype=%d）" % cputype)
        out[offset:offset + size] = new
        done.append(cputype)
    return bytes(out), done


def is_fat(data):
    return len(data) >= 4 and struct.unpack_from(">I", data, 0)[0] in (FAT_MAGIC, FAT_MAGIC_64)


def inject_file(path, dylib_path, out_path=None, strip_codesig=True):
    data = open(path, "rb").read()
    if is_fat(data):
        new, cpus = patch_fat(data, dylib_path, strip_codesig)
        kind = "fat cputypes=%s" % cpus
    else:
        new = patch_thin(data, dylib_path, strip_codesig)
        kind = "thin"
    outp = out_path or path
    with open(outp, "wb") as f:
        f.write(new)
    return kind, len(data), len(new)


def main():
    ap = argparse.ArgumentParser(description="纯 Python Mach-O dylib 注入器")
    ap.add_argument("macho", help="目标 Mach-O（App 主二进制或任一 dylib/framework）")
    ap.add_argument("dylib", help="加载路径，例如 @executable_path/hook.dylib")
    ap.add_argument("-o", "--output", help="输出文件，默认原地改写")
    ap.add_argument("--keep-codesig", action="store_true",
                    help="保留 LC_CODE_SIGNATURE（一般不要，会导致签名失败）")
    a = ap.parse_args()

    try:
        kind, before, after = inject_file(a.macho, a.dylib, a.output, not a.keep_codesig)
    except Exception as e:
        print("[-] 注入失败: %s" % e, file=sys.stderr)
        return 1
    print("[+] OK  %s" % a.macho)
    print("    加载命令: %s" % a.dylib)
    print("    类型: %s   大小: %d -> %d" % (kind, before, after))
    return 0


if __name__ == "__main__":
    sys.exit(main())
