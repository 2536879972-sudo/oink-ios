#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_ipa.py - 一键 IPA 重打包：解包 -> 拷入 dylib -> 注入 Mach-O ->
               改 Bundle ID / 显示名 -> 清签名残留 -> 重打包

输出直接丢给全能签签名安装。

用法:
  # 只注入
  python patch_ipa.py target.ipa -o out.ipa --dylib hook.dylib

  # 注入 + 改包名（重签必须改，否则和已装版本冲突）
  python patch_ipa.py target.ipa -o out.ipa --dylib hook.dylib ^
         --bundle-id com.yourco.tool --name "我的工具"

  # 保留原签名（一般不用，签名后必然失效）
  python patch_ipa.py target.ipa -o out.ipa --keep-codesig
"""
import argparse
import os
import plistlib
import shutil
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho_inject import FAT_MAGIC, FAT_MAGIC_64, is_fat, patch_fat, patch_thin  # noqa: E402


def unzip_all(ipa, dst):
    with zipfile.ZipFile(ipa) as z:
        bad = z.testzip()
        if bad:
            raise SystemExit("IPA 损坏，首个坏文件: %s" % bad)
        z.extractall(dst)


def collect_exec(project_root, app, info):
    """收集需要 0o755 权限的文件（Windows 上解压会丢执行位，必须显式打回 zip）。"""
    ex = set()
    exe = info["CFBundleExecutable"]
    ex.add((app / exe).relative_to(project_root).as_posix())
    for pat in (
        "Frameworks/*.framework/*",
        "Frameworks/*.dylib",
        "Frameworks/*.framework/Frameworks/*",
        "PlugIns/*.appex/*",
        "Extensions/*.appex/*",
        "Watch/*.app/*",
        "*.dylib",
    ):
        for p in app.glob(pat):
            if p.is_file():
                ex.add(p.relative_to(project_root).as_posix())
    return ex


def zip_dir(src_root, out_ipa, exec_rel):
    src_root = Path(src_root)
    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(src_root.rglob("*")):
            if p.is_dir():
                continue
            rel = p.relative_to(src_root).as_posix()
            zi = zipfile.ZipInfo(rel)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if rel in exec_rel else 0o644) << 16
            zi.create_system = 3          # unix
            with open(p, "rb") as f:
                z.writestr(zi, f.read())


def clean_signature(app):
    removed = []
    targets = [app / "_CodeSignature", app / "embedded.mobileprovision",
               app / "SC_Info", app / "CodeResources"]
    for t in targets:
        if t.is_dir():
            shutil.rmtree(t)
            removed.append(str(t.name))
        elif t.exists():
            t.unlink()
            removed.append(str(t.name))
    for p in list(app.rglob("_CodeSignature")):
        if p.is_dir():
            shutil.rmtree(p)
            removed.append(p.relative_to(app).as_posix())
    return removed


def main():
    ap = argparse.ArgumentParser(description="IPA 一键注入 + 重打包")
    ap.add_argument("ipa")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--dylib", action="append", default=[], help="可重复，注入多个 dylib")
    ap.add_argument("--bundle-id", help="新 Bundle ID")
    ap.add_argument("--name", help="新显示名称（桌面图标下文字）")
    ap.add_argument("--keep-codesig", action="store_true")
    ap.add_argument("--no-clean", action="store_true", help="不清理 _CodeSignature")
    ap.add_argument("--keep-workdir", action="store_true")
    a = ap.parse_args()

    for d in a.dylib:
        if not os.path.isfile(d):
            raise SystemExit("dylib 不存在: %s" % d)

    work = tempfile.mkdtemp(prefix="ipapatch_")
    print("[*] 解包 -> %s" % work)
    unzip_all(a.ipa, work)

    payload = Path(work) / "Payload"
    apps = list(payload.glob("*.app"))
    if len(apps) != 1:
        raise SystemExit("Payload 下应恰好一个 .app，实际: %s" % apps)
    app = apps[0]

    info_path = app / "Info.plist"
    with open(info_path, "rb") as f:
        info = plistlib.load(f)
    exe_name = info["CFBundleExecutable"]
    exe_path = app / exe_name
    if not exe_path.is_file():
        raise SystemExit("找不到主二进制: %s" % exe_path)

    # ---- 1. 拷 dylib ----
    loads = []
    for d in a.dylib:
        base = os.path.basename(d)
        shutil.copy2(d, app / base)
        loads.append("@executable_path/" + base)
        print("[+] dylib -> Payload/%s/%s" % (app.name, base))

    # ---- 2. 注入 ----
    data = exe_path.read_bytes()
    for load in loads:
        if is_fat(data):
            data, cpus = patch_fat(data, load, not a.keep_codesig)
            print("[+] 注入 %s (fat cputypes=%s)" % (load, cpus))
        else:
            data = patch_thin(data, load, not a.keep_codesig)
            print("[+] 注入 %s (thin)" % load)
    exe_path.write_bytes(data)

    # ---- 3. 改 Info.plist ----
    if a.bundle_id:
        old = info.get("CFBundleIdentifier")
        info["CFBundleIdentifier"] = a.bundle_id
        # 扩展/插件里的 ID 一般要跟着变，否则重签冲突
        for ext in app.glob("**/*.appex/Info.plist"):
            try:
                with open(ext, "rb") as f:
                    ei = plistlib.load(f)
                if ei.get("CFBundleIdentifier", "").startswith(old or ""):
                    ei["CFBundleIdentifier"] = ei["CFBundleIdentifier"].replace(old, a.bundle_id, 1)
                    with open(ext, "wb") as f:
                        plistlib.dump(ei, f, fmt=plistlib.FMT_BINARY)
            except Exception:
                pass
        print("[+] Bundle ID: %s -> %s" % (old, a.bundle_id))
    if a.name:
        info["CFBundleDisplayName"] = a.name
        info["CFBundleName"] = a.name
        print("[+] 显示名: %s" % a.name)

    with open(info_path, "wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)

    # ---- 4. 清签名残留 ----
    if not a.no_clean:
        removed = clean_signature(app)
        print("[+] 已清理: %s" % (", ".join(removed) if removed else "无残留"))

    # ---- 5. 重打包 ----
    exec_rel = collect_exec(work, app, info)
    zip_dir(work, a.output, exec_rel)
    size_mb = os.path.getsize(a.output) / 1048576.0
    print("[+] 输出: %s  (%.2f MB)" % (a.output, size_mb))
    print("[*] 下一步: 全能签导入该 IPA -> 选证书 -> 签名 -> 安装")

    if a.keep_workdir:
        print("[*] 工作目录保留: %s" % work)
    else:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
