# ios-kit —— iOS 自签工具链（全能签配套）

Windows 上也能跑的一套完整流程：写 App / 注入 dylib / 重打包 IPA / 自签安装。
不需要 Mac，不需要 insert_dylib，不需要越狱。

## 目录

```
ios-kit/
├─ tools/
│  ├─ macho_inject.py   纯 Python Mach-O 注入器（等价 insert_dylib）
│  ├─ patch_ipa.py      一键：解包→注入→改BundleID→清签名→重打包
│  ├─ verify_ipa.py     校验产物结构 / 注入 / 权限 / 签名残留
│  └─ selftest.py       合成 Mach-O 自测，验证注入器逻辑
├─ hook/
│  ├─ Makefile          Theos 根 Makefile（越狱 deb 方案）
│  ├─ Makefile.dylib    dylib 方案（注入未签名 IPA，非越狱可用）
│  ├─ control           deb 控制文件
│  └─ Tweak.x           零依赖 hook 实现（Objective-C runtime，不链 substrate）
├─ .github/workflows/build.yml   云 Mac 编译 App + dylib
└─ examples/ContentView.swift    可用 SwiftUI 起点
```

## 快速验证（不需要任何 iOS 设备）

```bash
cd ios-kit
python tools/selftest.py
```

期望输出 `PASS: all injector cases ok`。自测会构造最小 arm64 Mach-O、FAT 二进制、
bad headerpad 拒绝、双次注入、以及一个可直接喂给 `patch_ipa.py` 的样例 IPA。

## 完整流程 A：改别人的 IPA 加钩子（最常用）

```bash
# 1. 准备一个脱壳后的 IPA（未加密），从 App Store 下的必须先用 frida-ios-dump 砸壳
#    真机路径: /var/containers/Bundle/Application/<UUID>/App.app

# 2. 编译 hook dylib
#    macOS:
cd hook && make -f Makefile.dylib FINALPACKAGE=1 && cd ..
#    产物: hook/.theos/obj/HookKit.dylib
#    Windows: 用 .github/workflows/build.yml 让 GitHub Actions 编

# 3. 注入 + 改包名 + 重打包
python tools/patch_ipa.py target.ipa -o out.ipa \
    --dylib hook/.theos/obj/HookKit.dylib \
    --bundle-id com.yourco.tool \
    --name "工具"

# 4. 校验
python tools/verify_ipa.py out.ipa --expect-dylib HookKit.dylib

# 5. 全能签: 导入 out.ipa -> 选证书 -> 签名 -> 安装
```

## 完整流程 B：从零做自己的 App

```bash
# 有 Mac
xcodebuild -project MyApp.xcodeproj -scheme MyApp -sdk iphoneos \
  -configuration Release -archivePath build/app.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" PROVISIONING_PROFILE_SPECIFIER=""
cd build && mkdir Payload && cp -R app.xcarchive/Products/Applications/MyApp.app Payload/ \
  && zip -qry unsigned.ipa Payload

# 无 Mac
# 把工程推到 GitHub，手动触发 build-ios-artifacts workflow
# 下载 artifact: unsigned-ipa
```

拿到 `unsigned.ipa` 后走全能签签名。

## 证书选择

| 证书 | 有效期 | 需绑 UDID | 掉签 | 适用 |
|---|---|---|---|---|
| 个人开发者 | 7 天 | 是 | 到期必掉，重签即可 | 自己用，配 SideStore 自动续 |
| 付费 ad-hoc | 1 年 | 是 | 基本不掉 | 长期自用 / 小范围分发 |
| 企业证书 | 1 年 | 否 | **随时被吊销** | 应急，别依赖 |

取 UDID：Safari 打开 `https://foulab.org.cn/udid/` 装描述文件，或 Finder 里点序列号切换。

永久安装（免续签）的路线：iOS 14.0–16.6.1 / 17.0 用 TrollStore；
越狱机用 palera1n / Dopamine，直接 `dpkg -i`。

## 注入器原理（为什么不需要 insert_dylib）

Mach-O 的 header 之后紧跟 load commands，而 `__TEXT` 段第一个 section 的
file offset 通常是 `0x4000`。中间这块 header pad 是空的。

`macho_inject.py` 做的事：

1. 读 header 拿 `ncmds` / `sizeofcmds`
2. 逐条解析 load command
3. 剔除 `LC_CODE_SIGNATURE`（注入后必然失效）
4. 追加一条 `LC_LOAD_DYLIB`，路径写 `@executable_path/xxx.dylib`
5. 拼回 header pad，更新 `ncmds` / `sizeofcmds`
6. FAT 二进制则逐 slice 递归，slice 内偏移不变、文件总大小不变

因为只在空白区重写、不移动任何 section 数据，所以**文件大小恒定、所有
offset 不变**，不需要重算链接信息。

## 常见故障对照

| 现象 | 原因 | 处理 |
|---|---|---|
| `header pad 不足` | 目标二进制没留 headerpad | 用 `-Wl,-headerpad_max_install_names` 重编，或注入到 framework 而非主二进制 |
| 装完闪退 | entitlements 不匹配 / 权限非 755 | `verify_ipa.py` 看权限；用 `ldid -e` 导出原 entitlements 给全能签 |
| dylib 没加载 | 路径写错 / 架构不符 | 必须是 `@executable_path/xxx.dylib`；`lipo -info` 对齐 arm64/arm64e |
| 越狱检测仍在 | 只 hook 了 OC 层 | Tweak.x 里补 C 层 hook（`access`/`stat`/`fopen`，用 fishhook） |
| 签不上 | 残留 `_CodeSignature` | `patch_ipa.py` 默认已清；加 `--no-clean` 会跳过 |
| 与已装版本冲突 | Bundle ID 相同 | 必须 `--bundle-id` 改成新的 |

## 免责

本目录所有脚本只在操作者自有设备与自有 IPA 上使用。
