# NAS-KTV tvOS/iOS Client

原生 Swift/SwiftUI 客户端，复刻自 [NAS-KTV 安卓端](../tv-app)。

## 功能

- 设备注册与房间码管理
- WebSocket 实时同步（队列、播放状态、授权状态）
- 手机扫码点歌二维码
- 播放控制（上一首/下一首/暂停）
- 歌词同步显示
- 点歌队列查看
- 管理员授权流程
- 前后台自动重连

## 架构

参考安卓端 `packages/tv-app` 的核心逻辑：

| 安卓端 | tvOS/iOS 端 |
|--------|------------|
| `App.tsx` bootstrap | `NASKTVApp.swift` + `AppViewModel.bootstrap()` |
| `stores/room.ts` | `AppViewModel` room 状态 |
| `hooks/useRoomSync.ts` | `WebSocketService` + `AppViewModel` WS handlers |
| `hooks/useJoinTicket.ts` | `AppViewModel.startJoinTicketRefresh()` |
| `pages/NowPlaying.tsx` (默认路由 `/`) | `NowPlayingView` (默认页) |
| `pages/Queue.tsx` | `QueueView` |
| `pages/Setup.tsx` | `SetupView` |
| `pages/Bootstrap.tsx` | `BootstrapView` |
| `pages/Unauthorized.tsx` | `UnauthorizedView` |
| `components/QrCode.tsx` | `QRCodeImageView` |

## 构建

通过 GitHub Actions 构建未签名 IPA：

```
工作流: tvos-ios-unsigned-ipa.yml
平台: tvos / ios / both
配置: Debug / Release
```

## 部署目标

- tvOS 16.0+
- iOS 16.0+
