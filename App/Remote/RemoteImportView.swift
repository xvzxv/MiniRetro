// RemoteImportView.swift — 远程导入（直链 / WebDAV）（v1.9）
import SwiftUI

struct RemoteImportView: View {
    /// 下载完成后的本地文件交给调用方（复用 LibraryViewModel.importFiles）
    let onDownloaded: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case direct = "直链下载"
        case webdav = "WebDAV"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .direct

    // 直链
    @State private var directURL = ""

    // WebDAV
    @State private var server = WebDAVCredentialStore.server
    @State private var username = WebDAVCredentialStore.username
    @State private var password = WebDAVCredentialStore.password(for: WebDAVCredentialStore.server)
    @State private var connected = false
    @State private var path: [RemoteFileItem] = []
    @State private var items: [RemoteFileItem] = []

    @State private var isBusy = false
    @State private var progress: Double = 0
    @State private var status: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("方式", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isBusy)
                }

                if mode == .direct {
                    directSection
                } else {
                    webdavSection
                }

                Section {
                    Text("只支持导入你自己的文件：直链可以是任何 http(s) 地址（网盘直链、自建服务器、NAS）；"
                         + "WebDAV 支持群晖、坚果云、Nextcloud、InfiniCLOUD 等。\n"
                         + "本 App 不提供、也不内置任何游戏下载源。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("远程导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if mode == .webdav, connected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("断开") {
                            connected = false
                            items = []
                            path = []
                        }
                    }
                }
            }
            .overlay {
                if isBusy {
                    VStack(spacing: 10) {
                        ProgressView(value: progress)
                            .frame(width: 200)
                        Text(status ?? "处理中…")
                            .font(.caption)
                    }
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("出错了", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: - 直链

    private var directSection: some View {
        Section("文件直链") {
            HintText("支持任意 http(s) 直链，也支持网盘的「直链/下载链接」。链接要以 .zip/.7z/.nes/.gb/.gba/.cht/.srm 结尾，或服务器能正确返回文件名。")
            TextField("https://example.com/game.zip", text: $directURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("下载并导入") { downloadDirect() }
                .disabled(directURL.isEmpty || isBusy)
        }
    }

    private func downloadDirect() {
        guard let url = URL(string: directURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            errorText = RemoteImportError.badURL.errorDescription
            return
        }
        runDownload(url: url, headers: [:])
    }

    // MARK: - WebDAV

    private var webdavSection: some View {
        Group {
            Section("服务器") {
                HintText("填 WebDAV 根地址：群晖 https://NAS:5006/、坚果云 https://dav.jianguoyun.com/dav/、Nextcloud https://域名/remote.php/dav/files/用户名/。")
                TextField("https://dav.example.com/dav", text: $server)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码 / 应用密码", text: $password)
                HintText("坚果云、群晖建议用「应用密码」而不是登录密码；密码只存本机钥匙串。")
                Button(connected ? "重新连接" : "连接") { connect() }
                    .disabled(server.isEmpty || isBusy)
            }

            if connected {
                Section(pathTitle) {
                    if items.isEmpty {
                        Text(isBusy ? "加载中…" : "（空目录）")
                            .foregroundColor(.secondary)
                    }
                    ForEach(items) { item in
                        Button {
                            item.isDirectory ? enter(item) : download(item)
                        } label: {
                            HStack {
                                Image(systemName: item.isDirectory ? "folder" : "doc")
                                    .foregroundColor(item.isDirectory ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if !item.displaySize.isEmpty {
                                        Text(item.displaySize)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if item.isImportable {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .disabled(isBusy)
                    }
                    if !path.isEmpty {
                        Button("返回上一级") { goUp() }
                    }
                }
            }
        }
    }

    private var pathTitle: String {
        let names = path.map(\.name)
        return names.isEmpty ? "根目录" : names.joined(separator: " / ")
    }

    private var credential: WebDAVCredential {
        WebDAVCredential(server: server, username: username, password: password)
    }

    private func connect() {
        guard let base = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorText = RemoteImportError.badURL.errorDescription
            return
        }
        WebDAVCredentialStore.server = server
        WebDAVCredentialStore.username = username
        WebDAVCredentialStore.setPassword(password, for: server)

        isBusy = true
        status = "连接中…"
        Task {
            do {
                let list = try await RemoteImportService.listWebDAV(
                    server: base, path: pathString, credential: credential
                )
                await MainActor.run {
                    items = list
                    connected = true
                    isBusy = false
                    status = nil
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    connected = false
                    status = nil
                    errorText = error.localizedDescription
                }
            }
        }
    }

    /// 目录路径（相对服务器根），WebDAV 的 href 是绝对路径，这里按层级推算
    private var pathString: String {
        guard let base = URL(string: server) else { return "" }
        guard let first = path.first else { return "" }
        let basePath = base.path
        let full = first.url.path
        if full.hasPrefix(basePath) {
            return String(full.dropFirst(basePath.count))
        }
        return full
    }

    private func enter(_ item: RemoteFileItem) {
        // 用绝对路径直接列目录，避免层层拼接出错
        guard var components = URLComponents(url: item.url, resolvingAgainstBaseURL: false) else { return }
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let target = components.url else { return }
        isBusy = true
        Task {
            do {
                let list = try await RemoteImportService.listWebDAV(
                    server: target, path: "", credential: credential
                )
                await MainActor.run {
                    items = list
                    path.append(item)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func goUp() {
        guard !path.isEmpty else { return }
        path.removeLast()
        isBusy = true
        Task {
            do {
                let list = try await RemoteImportService.listWebDAV(
                    server: URL(string: server)!, path: pathString, credential: credential
                )
                await MainActor.run { items = list; isBusy = false }
            } catch {
                await MainActor.run { isBusy = false; errorText = error.localizedDescription }
            }
        }
    }

    private func download(_ item: RemoteFileItem) {
        runDownload(url: item.url, headers: RemoteImportService.basicAuthHeader(credential))
    }

    // MARK: - 下载

    private func runDownload(url: URL, headers: [String: String]) {
        isBusy = true
        progress = 0
        status = "下载 0%"
        Task {
            do {
                let file = try await RemoteImportService.download(url: url, headers: headers) { value in
                    Task { @MainActor in
                        progress = value
                        status = String(format: "下载 %.0f%%", value * 100)
                    }
                }
                await MainActor.run {
                    isBusy = false
                    onDownloaded(file)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    progress = 0
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
