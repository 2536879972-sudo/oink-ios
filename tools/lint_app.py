#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""静态检查：YAML 合法性 + Swift 结构配对 + 符号交叉引用（没有 macOS 也能跑）"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

bad = 0

print("--- YAML ---")
try:
    import yaml
    for f in sorted(glob.glob("**/*.yml", recursive=True)):
        with open(f, encoding="utf-8") as fh:
            yaml.safe_load(fh)
        print("  OK   %s" % f)
except ImportError:
    print("  SKIP pyyaml 未安装")

print("\n--- Swift 结构 ---")
swift_files = sorted(glob.glob("app/Sources/*.swift"))
for f in swift_files:
    src = open(f, encoding="utf-8").read()
    s = re.sub(r'"""[\s\S]*?"""', '""', src)
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*[\s\S]*?\*/', '', s)

    st = {"(": 0, "[": 0, "{": 0}
    pairs = {")": "(", "]": "[", "}": "{"}
    early = False
    for ch in s:
        if ch in st:
            st[ch] += 1
        elif ch in pairs:
            st[pairs[ch]] -= 1
            if st[pairs[ch]] < 0:
                early = True
                break
    if early:
        print("  FAIL %-26s 括号提前闭合" % os.path.basename(f))
        bad += 1
    elif any(v != 0 for v in st.values()):
        print("  FAIL %-26s 不平衡 %s" % (os.path.basename(f), st))
        bad += 1
    else:
        print("  OK   %-26s" % os.path.basename(f))

print("\n--- 必需文件 ---")
for need in ["app/project.yml", "app/Sources/OinkApp.swift",
             ".github/workflows/build-oink.yml"]:
    if os.path.isfile(need):
        print("  OK   %s" % need)
    else:
        print("  FAIL %s 缺失" % need)
        bad += 1

print("\n--- 符号 ---")
all_src = "".join(open(f, encoding="utf-8").read() for f in swift_files)
syms = ["ChatStore", "ChatMessage", "APIClient", "SecureStore", "Keychain",
        "ChatView", "SettingsView", "MessageBubble", "EmptyStateView", "OinkApp",
        "APIError", "WireRequest", "StreamChunk"]
for sym in syms:
    hit = any(("%s %s" % (kw, sym)) in all_src for kw in ("struct", "class", "enum"))
    print(("  OK   %s" % sym) if hit else ("  FAIL %s 未定义" % sym))
    if not hit:
        bad += 1

print("\n--- @main 入口 ---")
app_src = open("app/Sources/OinkApp.swift", encoding="utf-8").read()
if "@main" in app_src and "struct OinkApp: App" in app_src:
    print("  OK   @main struct OinkApp: App")
else:
    print("  FAIL 入口缺失")
    bad += 1

print("\n--- project.yml 关键项 ---")
pj = open("app/project.yml", encoding="utf-8").read()
for key in ["CODE_SIGNING_ALLOWED: NO", "CODE_SIGNING_REQUIRED: NO",
            "UILaunchScreen", "PRODUCT_BUNDLE_IDENTIFIER", "deploymentTarget"]:
    print(("  OK   %s" % key) if key in pj else ("  FAIL 缺 %s" % key))
    if key not in pj:
        bad += 1

print("\nRESULT:", "PASS" if bad == 0 else "FAIL(%d)" % bad)
sys.exit(0 if bad == 0 else 1)
