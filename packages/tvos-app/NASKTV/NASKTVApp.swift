import SwiftUI

@main
struct NASKTVApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if !viewModel.isLoaded {
                    ProgressView("加载中...")
                } else if !viewModel.isConfigured {
                    SetupView()
                        .environmentObject(viewModel)
                } else if !viewModel.authorized {
                    BootstrapView()
                        .environmentObject(viewModel)
                } else {
                    HomeView()
                        .environmentObject(viewModel)
                }
            }
            .onAppear {
                if viewModel.isConfigured && viewModel.room == nil {
                    Task { await viewModel.registerDevice() }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    viewModel.handleAppForeground()
                case .background:
                    viewModel.handleAppBackground()
                default:
                    break
                }
            }
        }
    }
}
