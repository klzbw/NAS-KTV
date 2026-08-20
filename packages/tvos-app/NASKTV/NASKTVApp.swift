import SwiftUI

@main
struct NASKTVApp: App {
    @StateObject private var serverViewModel = ServerViewModel()
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var libraryViewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if serverViewModel.isConnected {
                    MainTabView()
                        .environmentObject(serverViewModel)
                        .environmentObject(playerViewModel)
                        .environmentObject(libraryViewModel)
                } else {
                    ServerSetupView()
                        .environmentObject(serverViewModel)
                }
            }
            .onAppear {
                serverViewModel.loadSavedServers()
            }
        }
    }
}

// MARK: - 主标签视图
struct MainTabView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                QueueView()
            }
            .tabItem {
                Label("队列", systemImage: "list.bullet")
            }
        }
        .overlay(alignment: .bottom) {
            if playerViewModel.currentSong != nil {
                MiniPlayerView()
                    .padding(.bottom, 20)
            }
        }
    }
}
