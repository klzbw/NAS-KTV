# GitHub Actions CI 构建配置指南

本指南将帮助你配置 GitHub Actions 自动构建 NASKTV tvOS 应用。

## 目录

1. [工作流说明](#工作流说明)
2. [前置条件](#前置条件)
3. [配置 Apple Developer 证书](#配置-apple-developer-证书)
4. [配置 GitHub Secrets](#配置-github-secrets)
5. [触发构建](#触发构建)
6. [下载构建产物](#下载构建产物)
7. [常见问题](#常见问题)

---

## 工作流说明

工作流文件位置：`.github/workflows/tvos-build.yml`

### 触发方式

1. **推送 Tag**：推送 `v*` 格式的 tag（如 `v1.0.0`）自动触发签名构建
2. **代码变更**：修改 `packages/tvos-app/` 目录下的文件自动触发未签名构建
3. **手动触发**：在 GitHub Actions 页面手动运行，可选择配置和是否签名

### 构建类型

| 类型 | 用途 | 是否需要证书 |
|------|------|-------------|
| 未签名（模拟器） | 模拟器测试 | 否 |
| 签名（真机） | 真机部署 / App Store | 是 |

---

## 前置条件

### 必需

- GitHub 账号
- Apple ID（免费账号可用于开发，但无法发布到 App Store）

### 可选（签名构建需要）

- Apple Developer Program 会员（$99/年）
- 已注册的 Apple TV 设备 UDID

---

## 配置 Apple Developer 证书

> **注意**：这一步需要 Mac 电脑操作。如果没有 Mac，可以先使用未签名构建（模拟器版本）。

### 1. 创建 App ID

1. 登录 [Apple Developer 后台](https://developer.apple.com/account/)
2. 进入 **Certificates, Identifiers & Profiles**
3. 点击 **Identifiers** → **+**
4. 选择 **App IDs** → Continue
5. 填写：
   - Description: `NASKTV`
   - Bundle ID: `com.nasktv.app`（Explicit）
   - Capabilities: 勾选需要的功能（如 Audio, Background Modes）
6. 点击 Continue → Register

### 2. 创建 Distribution 证书

1. 在 **Certificates** 页面点击 **+**
2. 选择 **Apple Distribution** → Continue
3. 按照提示在 Mac 上创建 CSR 文件（使用钥匙串访问）
4. 上传 CSR 文件 → Continue → Download 证书（`.cer`）
5. 双击下载的证书，在钥匙串中安装
6. 在钥匙串中找到该证书，右键导出为 `.p12` 格式，设置密码

### 3. 注册设备（开发测试需要）

1. 在 **Devices** 页面点击 **+**
2. 填写设备名称和 UDID
   - Apple TV 的 UDID 可通过 Xcode → Window → Devices and Simulators 查看
   - 或通过 Apple Configurator 查看
3. 点击 Continue → Register

### 4. 创建 Provisioning Profile

1. 在 **Profiles** 页面点击 **+**
2. 选择 **App Store**（发布）或 **Ad Hoc**（测试）→ Continue
3. 选择刚才创建的 App ID → Continue
4. 选择 Distribution 证书 → Continue
5. （Ad Hoc 时）选择要包含的设备 → Continue
6. 输入 Profile 名称：`NASKTV tvOS` → Generate
7. 下载 `.mobileprovision` 文件

---

## 配置 GitHub Secrets

在 GitHub 仓库页面：

1. 进入 **Settings** → **Secrets and variables** → **Actions**
2. 点击 **New repository secret**
3. 添加以下 Secrets：

### 必需的 Secrets（签名构建）

| Secret 名称 | 说明 | 获取方式 |
|------------|------|---------|
| `IOS_DISTRIBUTION_CERTIFICATE` | p12 证书的 Base64 编码 | 见下方说明 |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | p12 证书密码 | 导出时设置的密码 |
| `TVOS_PROVISIONING_PROFILE` | mobileprovision 的 Base64 编码 | 见下方说明 |
| `APPLE_TEAM_ID` | Apple 团队 ID | [会员详情页](https://developer.apple.com/account/#/membership) 查看 |

### 生成 Base64 编码

在 Mac 终端执行：

```bash
# 证书 p12 文件转 Base64
base64 -i certificate.p12 -o certificate_base64.txt
cat certificate_base64.txt | pbcopy  # 复制到剪贴板

# Provisioning Profile 转 Base64
base64 -i NASKTV_tvOS.mobileprovision -o profile_base64.txt
cat profile_base64.txt | pbcopy  # 复制到剪贴板
```

将复制的内容粘贴到对应的 GitHub Secret 中。

---

## 触发构建

### 方式一：手动触发（推荐先测试）

1. 进入仓库 **Actions** 页面
2. 左侧选择 **tvOS Build**
3. 点击 **Run workflow**
4. 选择：
   - Configuration: `Release` 或 `Debug`
   - Sign: 勾选则签名构建（需要配置证书），不勾选则未签名构建
5. 点击 **Run workflow**

### 方式二：推送 Tag 触发

```bash
# 创建并推送 tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

推送 tag 后会自动触发签名构建，并上传到 GitHub Release。

### 方式三：代码变更自动触发

修改 `packages/tvos-app/` 目录下的文件并推送，会自动触发未签名构建（模拟器版本）。

---

## 下载构建产物

### 从 Actions 下载

1. 进入 **Actions** 页面
2. 点击对应的构建运行记录
3. 滚动到页面底部 **Artifacts** 区域
4. 点击下载：
   - `NASKTV-tvOS-Simulator`：模拟器版本（.app 打包的 zip）
   - `NASKTV-tvOS`：签名版本（.ipa）

### 从 Release 下载（Tag 构建）

推送 tag 后，构建产物会自动上传到 GitHub Release：
1. 进入仓库主页
2. 点击右侧 **Releases**
3. 找到对应的版本，下载 `.ipa` 文件

---

## 安装到 Apple TV

### 模拟器版本（.app）

1. 打开 Xcode
2. 打开 tvOS 模拟器（Xcode → Open Developer Tool → Simulator）
3. 将 `.app` 文件拖到模拟器窗口
4. 或使用命令行：
   ```bash
   xcrun simctl install booted NASKTV.app
   ```

### 真机版本（.ipa）

**方式一：使用 Xcode**
1. 连接 Apple TV 到 Mac（USB-C 或网络）
2. 打开 Xcode → Window → Devices and Simulators
3. 选择 Apple TV
4. 点击 **+** 选择 `.ipa` 文件安装

**方式二：使用 Apple Configurator**
1. 安装 [Apple Configurator](https://apps.apple.com/app/apple-configurator/id1037126344)
2. 连接 Apple TV
3. 将 `.ipa` 拖到设备上

**方式三：TestFlight（App Store 构建）**
1. 上传构建到 App Store Connect
2. 在 TestFlight 中添加测试人员
3. 在 Apple TV 上安装 TestFlight 应用并下载

---

## 常见问题

### Q: 没有 Mac 能配置证书吗？

A: 创建证书和 Provisioning Profile 需要 Mac 来生成 CSR 和导出 p12。如果没有 Mac，可以：
- 先使用未签名构建（模拟器版本）
- 借用朋友的 Mac 完成证书配置
- 使用第三方 CI 服务（如 Codemagic）提供的自动证书管理

### Q: 构建失败，提示 "No signing certificate"

A: 这是因为选择了签名构建但未配置证书。请：
1. 检查 GitHub Secrets 是否正确配置
2. 或手动触发时取消勾选 "Sign" 选项

### Q: 模拟器版本能在真机运行吗？

A: 不能。模拟器版本是为 x86/arm64 模拟器架构编译的，真机需要签名的 `.ipa` 文件。

### Q: 如何修改 Bundle ID？

A: 修改 `packages/tvos-app/NASKTV.xcodeproj/project.pbxproj` 中的 `PRODUCT_BUNDLE_IDENTIFIER`，同时在 Apple Developer 后台创建对应的 App ID。

### Q: 构建时间多长？

A: 通常 5-10 分钟。首次构建可能稍长（需要安装依赖）。

### Q: 如何查看构建日志？

A: 在 Actions 页面点击对应的构建运行记录，展开各个步骤即可查看详细日志。

---

## 下一步

1. ✅ 工作流文件已创建
2. ⬜ 配置 Apple Developer 证书（有 Mac 时）
3. ⬜ 配置 GitHub Secrets
4. ⬜ 手动触发一次未签名构建测试
5. ⬜ 下载模拟器版本测试
6. ⬜ 配置证书后触发签名构建
7. ⬜ 安装到 Apple TV 真机测试

如有问题，查看构建日志或参考 [Apple 官方文档](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。
