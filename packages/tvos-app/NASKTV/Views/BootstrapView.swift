import SwiftUI

// MARK: - BootstrapView (等待管理员授权 - 参考安卓端 pages/Bootstrap.tsx)
struct BootstrapView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if viewModel.isRegistering {
                ProgressView()
                    .scaleEffect(1.5)
                Text("正在注册设备...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else if let error = viewModel.bootstrapError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Text("连接失败")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button("重试") {
                    Task { await viewModel.bootstrap() }
                }
                .buttonStyle(.borderedProminent)
            } else if let room = viewModel.room {
                // 显示房间码，等待管理员授权
                VStack(spacing: 16) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)

                    Text("等待管理员授权")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("请在管理端使用以下房间码授权此设备")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    // Room code display
                    HStack(spacing: 8) {
                        ForEach(Array(room.code), id: \.self) { char in
                            Text(String(char))
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .frame(width: 44, height: 56)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 8)

                    // Connection status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.wsStatus == .connected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.wsStatus == .connected ? "已连接" : "连接中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(32)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(16)
            }

            Spacer()

            // Bottom actions
            HStack(spacing: 16) {
                Button("重新配置") {
                    viewModel.clearConfig()
                }
                .buttonStyle(.bordered)

                if !viewModel.isRegistering && viewModel.bootstrapError == nil {
                    Button("重新注册") {
                        Task { await viewModel.bootstrap() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 20)
        }
        .padding()
    }
}
