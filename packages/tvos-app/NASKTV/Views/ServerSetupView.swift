import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var viewModel: ServerViewModel
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "3000"
    @State private var username: String = "admin"
    @State private var password: String = ""
    @State private var showAddForm: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    // Logo和标题
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.tv")
                            .font(.system(size: 80))
                            .foregroundStyle(.tint)

                        Text("NAS-KTV")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("家庭KTV系统")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)

                    // 已保存的服务器
                    if !viewModel.servers.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("已保存的服务器")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ForEach(viewModel.servers) { server in
                                ServerCard(server: server) {
                                    viewModel.connect(to: server)
                                } onDelete: {
                                    viewModel.removeServer(server)
                                } onSetDefault: {
                                    viewModel.setDefault(server)
                                }
                            }
                        }
                        .padding(.horizontal, 80)
                    }

                    // 添加新服务器按钮
                    Button {
                        showAddForm = true
                    } label: {
                        Label("添加新服务器", systemImage: "plus.circle.fill")
                            .font(.title2)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 40)
                    }
                    .buttonStyle(.borderedProminent)

                    // 错误提示
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    // 连接中
                    if viewModel.isConnecting {
                        ProgressView("正在连接...")
                    }
                }
                .padding(.bottom, 60)
            }
            .sheet(isPresented: $showAddForm) {
                AddServerSheet(
                    name: $name,
                    host: $host,
                    port: $port,
                    username: $username,
                    password: $password
                ) {
                    let config = ServerConfig(
                        name: name,
                        host: host,
                        port: Int(port) ?? 3000,
                        username: username,
                        password: password
                    )
                    viewModel.addServer(config)
                    viewModel.connect(to: config)
                    showAddForm = false
                    resetForm()
                }
            }
        }
    }

    private func resetForm() {
        name = ""
        host = ""
        port = "3000"
        username = "admin"
        password = ""
    }
}

// MARK: - 服务器卡片
struct ServerCard: View {
    let server: ServerConfig
    let onConnect: () -> Void
    let onDelete: () -> Void
    let onSetDefault: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(server.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if server.isDefault {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                Text("\(server.host):\(server.port)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("连接", action: onConnect)
                .buttonStyle(.borderedProminent)

            Menu {
                Button("设为默认", action: onSetDefault)
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title)
            }
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 添加服务器表单
struct AddServerSheet: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var port: String
    @Binding var username: String
    @Binding var password: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器信息") {
                    TextField("名称（如：客厅NAS）", text: $name)
                    TextField("IP地址", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("登录信息") {
                    TextField("用户名", text: $username)
                    SecureField("密码", text: $password)
                }
            }
            .navigationTitle("添加服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并连接", action: onSave)
                        .disabled(name.isEmpty || host.isEmpty)
                }
            }
        }
    }
}
