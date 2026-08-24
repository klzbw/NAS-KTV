import SwiftUI

// MARK: - BootstrapView (Waiting for authorization)
struct BootstrapView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            if viewModel.isRegistering {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在注册设备...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else if let room = viewModel.room {
                VStack(spacing: 24) {
                    // Logo
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Text("N")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.accentColor)
                    }

                    Text("NAS-KTV")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("等待管理员授权")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Room code card
                    VStack(spacing: 16) {
                        Text("房间码")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .tracking(4)

                        Text(room.code)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .tracking(8)

                        Text(room.deviceId)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(32)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                    )

                    if let expiresAt = viewModel.expiresAt {
                        Text("授权即将到期: \(expiresAt)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Text("请管理员在后台审核并授权此设备")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 60)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("连接失败")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重新配置") {
                        viewModel.clearConfig()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }

            Spacer()

            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.wsStatus == .connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(viewModel.wsStatus == .connected ? "已连接" : viewModel.wsStatus == .connecting ? "连接中..." : "未连接")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .padding()
        .onAppear {
            if viewModel.room != nil && !viewModel.authorized {
                viewModel.startAuthorizationPolling()
            }
        }
        .onDisappear {
            viewModel.stopAuthorizationPolling()
        }
    }
}
