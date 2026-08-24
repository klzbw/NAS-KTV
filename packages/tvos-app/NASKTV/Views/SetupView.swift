import SwiftUI

// MARK: - SetupView
struct SetupView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var apiUrlInput: String = ""
    @State private var wsUrlInput: String = ""

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Text("N")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                Text("NAS-KTV")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("请配置后端服务器地址")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Form
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API 地址")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://192.168.3.16:3000", text: $apiUrlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("WebSocket 地址")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("ws://192.168.3.16:3000", text: $wsUrlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: {
                    let api = apiUrlInput.trimmingCharacters(in: .whitespaces)
                    let ws = wsUrlInput.trimmingCharacters(in: .whitespaces)
                    viewModel.saveConfig(apiUrl: api, wsUrl: ws)
                    Task { await viewModel.registerDevice() }
                }) {
                    HStack {
                        if viewModel.isRegistering {
                            ProgressView()
                        }
                        Text("连接并注册设备")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(apiUrlInput.isEmpty || viewModel.isRegistering)
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .padding()
        .onAppear {
            apiUrlInput = viewModel.apiUrl
            wsUrlInput = viewModel.wsUrl
        }
    }
}
