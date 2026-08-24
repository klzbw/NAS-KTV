import SwiftUI

// MARK: - UnauthorizedView (授权被撤销 - 参考安卓端 pages/Unauthorized.tsx)
struct UnauthorizedView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("设备授权已撤销")
                .font(.title)
                .fontWeight(.bold)

            Text("此设备的访问权限已被管理员撤销。\n请联系管理员重新授权。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if let room = viewModel.room {
                VStack(spacing: 8) {
                    Text("房间码")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Array(room.code), id: \.self) { char in
                            Text(String(char))
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .frame(width: 36, height: 44)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer()

            HStack(spacing: 16) {
                Button("重新配置") {
                    viewModel.clearConfig()
                }
                .buttonStyle(.bordered)

                Button("重新注册") {
                    Task { await viewModel.bootstrap() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 20)
        }
        .padding()
    }
}
