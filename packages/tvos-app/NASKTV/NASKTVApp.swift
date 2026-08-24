import SwiftUI

// MARK: - NASKTVApp (参考安卓端 App.tsx + router/index.tsx)
@main
struct NASKTVApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if !viewModel.isLoaded {
                    // 加载中
                    ProgressView()
                        .scaleEffect(1.5)
                } else if !viewModel.isConfigured {
                    // 未配置 → SetupView (参考安卓端 /setup)
                    SetupView()
                        .environmentObject(viewModel)
                } else if viewModel.room == nil && !viewModel.isRegistering {
                    // 无房间 → 自动 bootstrap
                    SetupView()
                        .environmentObject(viewModel)
                        .onAppear {
                            Task { await viewModel.bootstrap() }
                        }
                } else if !viewModel.authorized && viewModel.room != nil {
                    // 未授权 → BootstrapView (参考安卓端 /bootstrap)
                    BootstrapView()
                        .environmentObject(viewModel)
                } else if viewModel.authorized && viewModel.room != nil {
                    // 已授权 → NowPlayingView (参考安卓端默认路由 /)
                    NowPlayingView()
                        .environmentObject(viewModel)
                } else {
                    // 加载/注册中
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在连接...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                // 首次启动时如果已配置，自动 bootstrap
                if viewModel.isLoaded && viewModel.isConfigured && viewModel.room == nil {
                    Task { await viewModel.bootstrap() }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    viewModel.handleAppForeground()
                case .background, .inactive:
                    viewModel.handleAppBackground()
                @unknown default:
                    break
                }
            }
        }
    }
}
