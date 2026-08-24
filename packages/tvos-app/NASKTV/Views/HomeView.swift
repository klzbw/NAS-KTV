import SwiftUI

// MARK: - HomeView
struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            // Now Playing tab
            NowPlayingView()
                .tabItem {
                    Label("播放", systemImage: "music.note.tv")
                }

            // Queue tab
            QueueView()
                .tabItem {
                    Label("队列", systemImage: "list.bullet")
                }

            // Settings tab
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
        .overlay(alignment: .bottom) {
            if viewModel.currentItem != nil {
                MiniPlayerView()
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("服务器") {
                    HStack {
                        Text("API 地址")
                        Spacer()
                        Text(viewModel.apiUrl)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("WebSocket")
                        Spacer()
                        Text(viewModel.wsUrl)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("连接状态")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.wsStatus == .connected ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(viewModel.wsStatus == .connected ? "已连接" : "未连接")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("设备") {
                    HStack {
                        Text("设备 ID")
                        Spacer()
                        Text(viewModel.deviceId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let room = viewModel.room {
                        HStack {
                            Text("房间码")
                            Spacer()
                            Text(room.code)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("重新配置服务器")
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .alert("确认重新配置", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认", role: .destructive) {
                    WebSocketService.shared.disconnect()
                    viewModel.clearConfig()
                }
            } message: {
                Text("将清除当前服务器配置，需要重新输入地址并注册设备。")
            }
        }
    }
}
