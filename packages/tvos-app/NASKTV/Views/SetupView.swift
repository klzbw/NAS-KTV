import SwiftUI

// MARK: - SetupView
struct SetupView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var apiUrlInput: String = ""
    @State private var wsUrlInput: String = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

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

            Text("配置服务器地址")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Input fields
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API 地址")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://192.168.1.100:3000/api", text: $apiUrlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("WebSocket 地址")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("ws://192.168.1.100:3000", text: $wsUrlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 40)

            if let error = viewModel.bootstrapError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            // Save button
            Button(action: {
                let api = apiUrlInput.trimmingCharacters(in: .whitespaces)
                let ws = wsUrlInput.trimmingCharacters(in: .whitespaces)
                guard !api.isEmpty else { return }
                let wsFinal = ws.isEmpty ? api.replacingOccurrences(of: "/api", with: "").replacingOccurrences(of: "http", with: "ws") : ws
                viewModel.saveConfig(apiUrl: api, wsUrl: wsFinal)
                Task { await viewModel.bootstrap() }
            }) {
                if viewModel.isRegistering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("保存并连接")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(apiUrlInput.isEmpty || viewModel.isRegistering)

            Spacer()
        }
        .padding()
        .onAppear {
            apiUrlInput = viewModel.apiUrl
            wsUrlInput = viewModel.wsUrl
        }
    }
}
