# NASKTV for tvOS

NAS-KTV 系统的 Apple TV 原生客户端，基于 Swift/SwiftUI 开发。

## 功能特性

- 服务器连接配置（支持多服务器保存）
- 歌曲库浏览（按歌手、分类、语种、年代）
- 搜索歌曲
- 播放控制（原伴唱切换、播放/暂停、上下曲）
- 歌词同步显示
- 点歌队列管理
- 遥控器焦点导航优化
- 设备授权（与后端授权机制对接）

## 系统要求

- tvOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## 构建说明

### 方式一：本地构建（需要Mac）

1. 用 Xcode 打开 `NASKTV.xcodeproj`
2. 选择 Apple TV 模拟器或真机
3. 按 `Cmd + R` 运行

### 方式二：GitHub Actions 自动构建

项目已配置 CI 工作流，推送代码后自动构建 tvOS 应用。

## 项目结构

```
NASKTV/
├── NASKTVApp.swift          # 应用入口
├── Models/                   # 数据模型
│   ├── ServerConfig.swift
│   ├── Song.swift
│   ├── Artist.swift
│   ├── Category.swift
│   └── QueueItem.swift
├── Services/                 # 服务层
│   ├── APIService.swift      # REST API 客户端
│   ├── WebSocketService.swift # WebSocket 实时通信
│   └── PlayerService.swift   # 音频播放服务
├── ViewModels/               # 视图模型
│   ├── ServerViewModel.swift
│   ├── LibraryViewModel.swift
│   ├── PlayerViewModel.swift
│   └── SearchViewModel.swift
├── Views/                    # 视图
│   ├── ServerSetupView.swift # 服务器配置
│   ├── HomeView.swift        # 首页
│   ├── SongListView.swift    # 歌曲列表
│   ├── PlayerView.swift      # 播放器
│   ├── SearchView.swift      # 搜索
│   └── QueueView.swift       # 队列
└── Assets.xcassets/          # 资源文件
```

## API 对接

后端 API 文档见 `docs/API.md`，主要接口：

- `POST /api/auth/login` - 登录
- `GET /api/songs` - 获取歌曲列表
- `GET /api/artists` - 获取歌手列表
- `GET /api/categories` - 获取分类列表
- `POST /api/queue` - 添加到播放队列
- `GET /api/queue` - 获取队列
- `WS /ws` - WebSocket 实时同步

## 许可证

MIT
