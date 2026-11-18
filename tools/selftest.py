#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Self-test: build a minimal arm64 Mach-O in memory, validate injector logic.

No real iOS binary required. Output is ASCII to survive GBK consoles.
"""
import os
import plistlib
import struct
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho_inject import LC_LOAD_DYLIB, is_fat, patch_fat, patch_thin  # noqa


def build_min_macho(headerpad=0x4000, with_codesig=True, extra_cmds=b""):
    segname = b"__TEXT".ljust(16, b"\x00")
    sectname = b"__text".ljust(16, b"\x00")
    nsects = 1
    cmds = extra_cmds
    ncmds = 0

    seg_size = 72 + 80 * nsects
    seg = bytearray(seg_size)
    struct.pack_into("<II", seg, 0, 0x19, seg_size)
    seg[8:24] = segname
    struct.pack_into("<QQQQ", seg, 24, 0x100000000, headerpad, 0, headerpad)
    struct.pack_into("<II", seg, 56, 7, 5)
    struct.pack_into("<I", seg, 64, nsects)
    struct.pack_into("<I", seg, 68, 0)
    s = 72
    seg[s:s + 16] = sectname
    seg[s + 16:s + 32] = segname
    struct.pack_into("<QQ", seg, s + 32, 0x100000000, 0x10)
    struct.pack_into("<I", seg, s + 48, headerpad)
    struct.pack_into("<I", seg, s + 52, 4)
    cmds += bytes(seg)
    ncmds += 1

    if with_codesig:
        cmds += struct.pack("<IIII", 0x1D, 16, headerpad + 0x10, 0x8)
        ncmds += 1

    sizeofcmds = len(cmds)
    hdr = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2,
                      ncmds, sizeofcmds, 0x200085, 0)
    body = hdr + cmds
    body += b"\x00" * (headerpad - len(body))
    body += b"\xde\xad\xbe\xef" * 4
    return body


def read_cmds(data):
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    out = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        out.append((cmd, cmdsize))
        off += cmdsize
    return out


def main():
    fails = []

    # 1. thin inject
    orig = build_min_macho()
    n_before = len(read_cmds(orig))
    injected = patch_thin(orig, "@executable_path/HookKit.dylib", True)
    cmds = read_cmds(injected)
    print("[1] thin: ncmds %d -> %d cmds=%s" % (n_before, len(cmds), cmds))
    if not any(c == LC_LOAD_DYLIB for c, _ in cmds):
        fails.append("thin: LC_LOAD_DYLIB not written")
    if any(c == 0x1D for c, _ in cmds):
        fails.append("thin: LC_CODE_SIGNATURE not stripped")
    if b"@executable_path/HookKit.dylib" not in injected:
        fails.append("thin: load path string missing")
    if len(injected) != len(orig):
        fails.append("thin: file size changed")
    if injected[0x4000:0x4000 + 16] != orig[0x4000:0x4000 + 16]:
        fails.append("thin: section data corrupted")

    # 2. inject twice
    twice = patch_thin(injected, "@executable_path/Second.dylib", True)
    n_dylib = sum(1 for c, _ in read_cmds(twice) if c == LC_LOAD_DYLIB)
    print("[2] double inject: LC_LOAD_DYLIB count = %d" % n_dylib)
    if n_dylib != 2:
        fails.append("double inject failed")

    # 3. insufficient headerpad must raise
    small = build_min_macho(headerpad=0x60)
    try:
        patch_thin(small, "@executable_path/HookKit.dylib", True)
        fails.append("no error on insufficient headerpad")
    except ValueError as e:
        print("[3] headerpad guard OK: %s" % str(e)[:48])

    # 4. FAT inject
    arm = build_min_macho()
    x86 = build_min_macho()
    fa = bytearray()
    fa += struct.pack(">II", 0xCAFEBABE, 2)
    off1 = 0x1000
    off2 = off1 + len(arm)
    fa += struct.pack(">IIIII", 0x0100000C, 0, off1, len(arm), 12)
    fa += struct.pack(">IIIII", 0x01000007, 3, off2, len(x86), 12)
    fa += b"\x00" * (off1 - len(fa))
    fa += arm + x86
    fa = bytes(fa)
    assert is_fat(fa)
    fat_out, cpus = patch_fat(fa, "@executable_path/HookKit.dylib", True)
    print("[4] fat: cputypes=%s size %d -> %d" % (cpus, len(fa), len(fat_out)))
    if len(fat_out) != len(fa):
        fails.append("fat: size changed")
    for off, name in ((off1, "arm64"), (off2, "x86_64")):
        sl = fat_out[off:off + len(arm)]
        if not any(c == LC_LOAD_DYLIB for c, _ in read_cmds(sl)):
            fails.append("fat: %s slice not injected" % name)

    # 5. end-to-end sample IPA for patch_ipa.py
    tmp = tempfile.mkdtemp(prefix="selftest_")
    app = os.path.join(tmp, "Payload", "Demo.app")
    os.makedirs(app)
    with open(os.path.join(app, "Demo"), "wb") as f:
        f.write(orig)
    info = {"CFBundleExecutable": "Demo", "CFBundleIdentifier": "com.demo.app",
            "CFBundleDisplayName": "Demo", "CFBundleName": "Demo"}
    with open(os.path.join(app, "Info.plist"), "wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
    ipa = os.path.join(tmp, "demo.ipa")
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(tmp):
            for fn in files:
                p = os.path.join(root, fn)
                if p == ipa:
                    continue
                z.write(p, os.path.relpath(p, tmp).replace("\\", "/"))
    print("[5] sample IPA: %s (%d bytes)" % (ipa, os.path.getsize(ipa)))

    print()
    if fails:
        print("FAIL: " + "; ".join(fails))
        return 1
    print("PASS: all injector cases ok")
    print("SAMPLE_IPA=%s" % ipa)
    return 0


if __name__ == "__main__":
    sys.exit(main())
