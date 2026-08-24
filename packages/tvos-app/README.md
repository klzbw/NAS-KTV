# NASKTV for tvOS / iOS

NAS-KTV 系统的 Apple TV / iPhone / iPad 原生客户端，基于 Swift/SwiftUI 开发，支持 tvOS 15+ 和 iOS 15+。

## 功能特性

- 服务器连接配置（API + WebSocket 地址，支持多服务器）
- 设备自动注册与房间码生成
- 管理员授权等待页面
- WebSocket 实时同步（队列、播放状态、授权状态）
- 播放队列管理
- 正在播放页面（歌曲信息、播放控制）
- 歌词同步显示（自动滚动、当前行高亮）
- 原伴唱切换（原唱 / 伴奏 / 人声）
- 迷你播放器悬浮条
- 设置页面（服务器信息、设备信息、连接状态）
- 遥控器焦点导航优化
- 后台音频播放

## 系统要求

- tvOS 15.0+ / iOS 15.0+
- Xcode 15.0+
- Swift 5.9+

## 项目结构

```
NASKTV/
├── NASKTVApp.swift              # 应用入口
├── Models/
│   ├── Models.swift              # 数据模型（Room, Song, Queue, PlayerState）
│   └── WebSocketMessages.swift   # WebSocket 消息类型与 Payload
├── Services/
│   ├── APIService.swift          # REST API 客户端
│   ├── WebSocketService.swift    # WebSocket 实时通信（含心跳重连）
│   └── PlayerService.swift       # AVFoundation 音频播放
├── ViewModels/
│   └── AppViewModel.swift        # 主视图模型（状态管理）
├── Views/
│   ├── SetupView.swift           # 服务器配置
│   ├── BootstrapView.swift       # 设备注册/等待授权
│   ├── HomeView.swift            # 主页面（TabView + 设置）
│   ├── NowPlayingView.swift      # 正在播放（歌词 + 控制）
│   └── QueueView.swift           # 播放队列 + 迷你播放器
├── Assets.xcassets/              # 资源文件
└── Info.plist
```

## API 对接

后端 API 主要接口：
- `POST /api/rooms/register` - 设备注册
- `GET /api/rooms/:code` - 获取房间信息
- `GET /api/songs/:id/lyrics` - 获取歌词
- `WS /ws/room?roomCode=XXX&role=tv` - WebSocket 实时同步

## 构建

### 本地构建（需要 Mac）

```bash
cd packages/tvos-app
xcodebuild -project NASKTV.xcodeproj -scheme NASKTV -configuration Release -sdk appletvos build
```

### GitHub Actions 自动构建

推送代码到 `packages/tvos-app/` 目录自动触发，或手动运行 `tvOS/iOS Unsigned IPA Build` 工作流，生成未签名 IPA。

## 未签名 IPA 安装

未签名 IPA 需要通过以下方式安装：
- Xcode → Window → Devices and Simulators → 选择设备 → 添加 IPA
- Apple Configurator 2
- 第三方签名工具（如 AltStore、TrollStore）

## 许可证

MIT
