// LibraryView.swift — 游戏库主界面（M5）
// 网格/列表切换、搜索、收藏、最近游玩、系统角标、封面
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

struct LibraryView: View {
    @StateObject private var model = LibraryViewModel()
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var showGrid = true
    @State private var selectedROM: ROMEntry?
    @State private var importMessage: String?
    @State private var showRemoteImport = false
    @State private var pendingDelete: ROMEntry?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if model.filteredROMs(searchText: searchText, favoritesOnly: showFavoritesOnly).isEmpty {
                    emptyState
                } else if showGrid {
                    gridView
                } else {
                    listView
                }
            }
            .task {
                // 自动化/调试入口：-MRRemoteTest <url>
                //   url 以 "/" 结尾 → 当作 WebDAV 目录列一次；否则下载并导入
                // （模拟器里没法点按钮，靠它验证远程导入全链路）
                let argv = ProcessInfo.processInfo.arguments
                if argv.contains("-MRShowRemoteImport") {
                    showRemoteImport = true
                    return
                }
                if let idx = argv.firstIndex(of: "-MRRemoteTest"), idx + 1 < argv.count,
                   let url = URL(string: argv[idx + 1]) {
                    runRemoteSelfTest(url)
                    return
                }

                // 自动化/调试入口：-MRAutoPlayFirst 启动时自动打开第一款游戏
                // （供模拟器/CI 验证渲染与运行链路；正常启动无任何影响）
                let args = ProcessInfo.processInfo.arguments
                let wantsAutoPlay = args.contains("-MRAutoPlayFirst")
                    || UserDefaults.standard.bool(forKey: "MRAutoPlayFirst")
                NSLog("[MiniRetro] autoPlay=%@ args=%@ roms=%ld", wantsAutoPlay ? "yes" : "no",
                      args.joined(separator: " "), model.filteredROMs(searchText: "", favoritesOnly: false).count)
                guard wantsAutoPlay else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let first = model.filteredROMs(searchText: "", favoritesOnly: false).first {
                    NSLog("[MiniRetro] autoPlay opening %@", first.fileName)
                    selectedROM = first
                }
            }
            .navigationTitle("游戏库")
            .searchable(text: $searchText, prompt: "搜索 ROM")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFavoritesOnly.toggle()
                    } label: {
                        Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showGrid = true
                        } label: {
                            Label("网格视图", systemImage: showGrid ? "checkmark" : "")
                        }
                        Button {
                            showGrid = false
                        } label: {
                            Label("列表视图", systemImage: !showGrid ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: showGrid ? "square.grid.2x2" : "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRemoteImport = true
                    } label: {
                        Image(systemName: "globe")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(item: $selectedROM) { rom in
                GameView(rom: rom)
            }
            .sheet(isPresented: $model.showImporter) {
                DocumentPicker { urls in
                    model.importFiles(urls: urls)
                }
            }
            .sheet(isPresented: $showRemoteImport) {
                RemoteImportView { localFile in
                    // 下载到临时目录后走同一套导入流程（zip 会自动解压/拆街机包）
                    let urls = [localFile]
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        model.importFiles(urls: urls)
                        try? FileManager.default.removeItem(at: localFile)
                    }
                }
            }
            .confirmationDialog(
                "移除「\(pendingDelete?.displayName ?? "")」？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除游戏文件与存档", role: .destructive) {
                    if let rom = pendingDelete { model.remove(rom) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("会同时删除 ROM 文件、这个游戏的即时存档与金手指记录，无法恢复。只是不想看到它的话，可以先加收藏。")
            }
            .alert("导入结果", isPresented: Binding(
                get: { model.importSummary != nil },
                set: { if !$0 { model.importSummary = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(model.importSummary ?? "")
            }
        }
    }

    // MARK: - 视图

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.filteredROMs(searchText: searchText, favoritesOnly: showFavoritesOnly)) { rom in
                    ROMCard(rom: rom, model: model)
                        .onTapGesture {
                            model.markPlayed(rom)
                            selectedROM = rom
                        }
                        .contextMenu {
                            Button {
                                model.toggleFavorite(rom)
                            } label: {
                                Label(rom.isFavorite ? "取消收藏" : "收藏", systemImage: rom.isFavorite ? "star.slash" : "star")
                            }
                            Button(role: .destructive) {
                                pendingDelete = rom
                            } label: {
                                Label("从库中移除", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List {
            ForEach(model.filteredROMs(searchText: searchText, favoritesOnly: showFavoritesOnly)) { rom in
                HStack {
                    coverImage(for: rom)
                        .frame(width: 52, height: 52)
                        .cornerRadius(6)
                    VStack(alignment: .leading) {
                        Text(rom.displayName).lineLimit(1)
                        Text("\(rom.system.displayName) · \(ByteCountFormatter.string(fromByteCount: rom.fileSize, countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if rom.isCorrupted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                    if rom.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.markPlayed(rom)
                    selectedROM = rom
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("还没有游戏")
                .font(.title2)
            Text("""
            点右上角 + 选择文件，App 会自动归类：
            · 游戏：.nes .fds .gb .gbc .gba，街机整套 .zip / .7z
            · BIOS：neogeo.zip / pgm.zip（自动装到 System）
            · 金手指：.cht（存进金手指库，游戏内可套用）
            · 电池存档：.srm / .sav（按同名 ROM 归档）

            也可以点右上角 🌐 从直链或 WebDAV 直接下载导入。
            ROM 由你自行提供，本 App 不含任何游戏数据。
            """)
            .font(.callout)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func coverImage(for rom: ROMEntry) -> Image {
        Image(crossImage: model.coverImage(for: rom), placeholder: "gamecontroller")
    }

    /// 远程导入自测（-MRRemoteTest）：下载/列目录 → 走正常导入流程 → 打日志
    private func runRemoteSelfTest(_ url: URL) {
        Task { @MainActor in
            do {
                if url.absoluteString.hasSuffix("/") {
                    guard let base = URL(string: "\(url.scheme ?? "http")://\(url.host ?? "127.0.0.1"):\(url.port ?? 80)/") else {
                        NSLog("[MiniRetro] WebDAV 自测：地址非法")
                        return
                    }
                    let credential = WebDAVCredential(
                        server: base.absoluteString,
                        username: "tester",
                        password: "secret"
                    )
                    let items = try await RemoteImportService.listWebDAV(
                        server: base,
                        path: String(url.path.dropFirst()),
                        credential: credential
                    )
                    NSLog("[MiniRetro] WebDAV 自测：%ld 项 → %@", items.count,
                          items.prefix(6).map { "\($0.isDirectory ? "[D]" : "[F]")\($0.name)" }
                              .joined(separator: " "))
                } else {
                    let file = try await RemoteImportService.download(url: url) { _ in }
                    let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
                    NSLog("[MiniRetro] 下载自测：%@ (%lld 字节) → 开始导入", file.lastPathComponent, size ?? 0)
                    model.importFiles(urls: [file])
                    NSLog("[MiniRetro] 导入自测结果：%@", model.importSummary ?? "无")
                    try? FileManager.default.removeItem(at: file)
                }
            } catch {
                NSLog("[MiniRetro] 远程自测失败：%@", error.localizedDescription)
            }
        }
    }
}

// MARK: - ROM 卡片

struct ROMCard: View {
    let rom: ROMEntry
    @ObservedObject var model: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let image = model.coverImage(for: rom) {
                    Image(crossImage: image)
                        .resizable()
                        .aspectRatio(3.0 / 4.0, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        )
                }
                Text(rom.system.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundColor(.white)
                    .padding(6)
            }
            .cornerRadius(8)

            HStack {
                Text(rom.displayName)
                    .font(.caption)
                    .lineLimit(1)
                if rom.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
            if rom.isCorrupted {
                Text("文件损坏")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - 文档选择器（iOS）

#if canImport(UIKit)
struct DocumentPicker: UIViewControllerRepresentable {
    let onPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supported: [UTType] = [
            UTType(filenameExtension: "nes") ?? .data,
            UTType(filenameExtension: "gb") ?? .data,
            UTType(filenameExtension: "gbc") ?? .data,
            UTType(filenameExtension: "gba") ?? .data,
            UTType(filenameExtension: "fds") ?? .data,
            // 街机 romset（西游释厄传/三国战纪/拳皇等，整套 zip 原样交给 FBNeo）
            UTType(filenameExtension: "7z") ?? .data,
            // 金手指文件（libretro .cht）与电池存档（.srm/.sav）：导入时自动识别归类
            UTType(filenameExtension: "cht") ?? .data,
            UTType(filenameExtension: "srm") ?? .data,
            UTType(filenameExtension: "sav") ?? .data,
            UTType.zip,
            .data,
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supported, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: ([URL]) -> Void

        init(onPicked: @escaping ([URL]) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPicked(urls)
        }
    }
}

#endif
