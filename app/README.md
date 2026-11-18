# 把「小码酱」装进手机 —— 自签流程

三条路，按省事程度排：

| 路线 | 耗时 | 需要什么 | 掉签 |
|---|---|---|---|
| **A. PWA**（最省事） | 5 分钟 | 一个能放网页的地方 | 不掉 |
| **B. 本目录原生 App** | 30 分钟 | GitHub 账号 + 全能签 | 7 天（个人证书） |
| **C. 现成开源客户端自签** | 15 分钟 | 全能签 + 一个 IPA | 同上 |

---

## A. PWA —— 完全不签名，5 分钟

适合“我就想随时问两句”。

1. 打开任意支持 PWA 的聊天前端（NextChat / LobeChat / 自建），或自己丢一个
   `index.html` 到 Vercel / Netlify / Cloudflare Pages。
2. iPhone Safari 打开，点底部「分享」→「添加到主屏幕」。
3. 桌面出现图标，点开是全屏的，没有地址栏。

缺点：iOS 的 PWA 后台会被杀，长回复切后台会断；不能读相册/文件深路径。

---

## B. 本目录原生 App —— 能编译、能自签、能长期用

### B1. 出未签名 IPA（不需要 Mac）

1. 把整个 `ios-kit` 目录推到一个 GitHub 仓库（public 或 private 都行）。
2. 仓库 → Actions → 左侧 `build-oink` → `Run workflow`。
3. 等 5~8 分钟，下载 artifact `oink-unsigned-ipa`，里面是 `Oink.ipa`。

workflow 会自动装 XcodeGen、生成 `Oink.xcodeproj`、关掉签名编译、打成
`Payload/Oink.app` 结构的 IPA。

### B2. 有 Mac 的话（更快，能真机调试）

```bash
cd ios-kit/app
brew install xcodegen
xcodegen generate

# 真机调试：Xcode 打开 Oink.xcodeproj，选你的设备，改 Signing Team
open Oink.xcodeproj

# 只要未签名 IPA：
xcodebuild -project Oink.xcodeproj -scheme Oink -sdk iphoneos \
  -configuration Release -archivePath build/Oink.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" PROVISIONING_PROFILE_SPECIFIER=""

cd build && mkdir -p Payload \
  && cp -R Oink.xcarchive/Products/Applications/Oink.app Payload/ \
  && zip -qry Oink.ipa Payload
```

### B3. 全能签签名安装

1. 全能签 → 证书管理 → 导入 `p12` + `mobileprovision`。
   - 个人证书：必须先把这台 iPhone 的 UDID 加进 developer.apple.com 的 Devices，
     再重新生成描述文件。取 UDID：Safari 开 `https://foulab.org.cn/udid/`。
   - 企业证书：不绑 UDID，但随时可能被吊销。
2. 全能签 → 导入 `Oink.ipa` → 选证书 → 签名。
3. 安装。首次打开会提示「未受信任的开发者」，去
   设置 → 通用 → VPN与设备管理 → 信任对应证书。

**如果签名时提示 Bundle ID 冲突**：`project.yml` 里把
`PRODUCT_BUNDLE_IDENTIFIER` 改成你自己的（比如 `com.你的名字.oink`），
重新跑 workflow。

### B4. 首次打开要做的两件事

1. 右上角齿轮 → 填 **Base URL** + **模型** + **API Key**。
   - DeepSeek：`https://api.deepseek.com/v1` / `deepseek-chat`
   - OpenAI：`https://api.openai.com/v1` / `gpt-4o-mini`
   - 自建 / 中转：填到 `/v1` 为止，App 自动补 `/chat/completions`
2. 「人格」那一栏可以写系统提示词，默认是
   `你是小码酱，技术问题直接给可运行的结果。` —— 改成你想要的。

设置页底部会实时显示「实际请求地址」，填错了能立刻看出来。

### B5. 不想每周重签

- **SideStore / AltStore**：电脑装 AltServer，手机同 WiFi 自动后台续签，
  个人证书 7 天自动刷新，免费。
- **TrollStore**：iOS 14.0–16.6.1 / 17.0 有 CoreTrust 漏洞，装完永久签名，
  IPA 拖进去就行，不过期。这是终局方案。

---

## C. 现成开源客户端自签

不想自己编的话，下这些的 IPA 直接全能签：

- **ChatBox**（开源，Mac/iOS）
- **LobeChat**（Web，走 PWA 最省事）
- **NextChat**（Web/PWA）
- **OpenCat**（付费，App Store 有）

自签装完同样在设置里填 Base URL + Key。

---

## 代码结构

```
app/
├─ project.yml            XcodeGen 描述，bundle id / 显示名都在这改
└─ Sources/
   ├─ OinkApp.swift       入口
   ├─ ChatView.swift      聊天界面、气泡、输入栏
   ├─ ChatStore.swift     会话状态、上下文裁剪、流式追加
   ├─ APIClient.swift     OpenAI 兼容 SSE 流式调用
   ├─ Keychain.swift      Key 存储（Keychain 失败自动降级 UserDefaults）
   └─ SettingsView.swift  接口 / Key / 人格 设置
```

### 自签环境下的两个必要处理

1. **Keychain 降级**：自签 App 常常拿不到 `keychain-access-groups` entitlement，
   `SecItemAdd` 会返回 `errSecMissingEntitlement`。`Keychain.swift` 写完立刻回读，
   读不到就落 UserDefaults，保证 Key 一定存得住。

2. **`UILaunchScreen` 必须存在**：`project.yml` 里给了空字典。缺了它在新系统上
   会黑屏或窗口尺寸错乱 —— 这是手搓 iOS App 最常见的踩坑点。

### 流式是怎么做的

`URLSession.shared.bytes(for:)` 拿到 `AsyncSequence`，逐行读 SSE：

```
data: {"choices":[{"delta":{"content":"你"}}]}
data: {"choices":[{"delta":{"content":"好"}}]}
data: [DONE]
```

每行剥掉前缀 `data:`、跳过 `[DONE]`、JSON 解出 `choices[0].delta.content`，
yield 给上层。`ChatStore` 拿到增量就拼到最后那条 assistant 消息上，
SwiftUI 自动重绘，所以是逐字出现的。

中断处理：`continuation.onTermination` 里 `task.cancel()`，输入栏在流式期间
变成红色停止键。
