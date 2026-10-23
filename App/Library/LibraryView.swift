// LibraryView.swift — 游戏库主界面
// 网格/列表、搜索、收藏、批量选择删除、批量导入（文件/文件夹/远程）、封面
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

    // 导入入口
    @State private var showRemoteImport = false
    @State private var showFolderPicker = false
    @State private var importProgress: (done: Int, total: Int)?

    // 批量选择
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmBatchDelete = false
    @State private var pendingDelete: ROMEntry?
    @State private var actionMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    private var visibleROMs: [ROMEntry] {
        model.filteredROMs(searchText: searchText, favoritesOnly: showFavoritesOnly)
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleROMs.isEmpty {
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
                if argv.contains("-MRShowSelection") {
                    isSelecting = true
                    return
                }
                if let idx = argv.firstIndex(of: "-MRRemoteTest"), idx + 1 < argv.count,
                   let url = URL(string: argv[idx + 1]) {
                    runRemoteSelfTest(url)
                    return
                }

                // 自动化/调试入口：-MRAutoPlayFirst 启动时自动打开第一款游戏
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
            .navigationTitle(isSelecting ? "已选 \(selection.count)" : "游戏库")
            .searchable(text: $searchText, prompt: "搜索 ROM")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button(selection.count == visibleROMs.count ? "取消全选" : "全选") {
                            if selection.count == visibleROMs.count {
                                selection.removeAll()
                            } else {
                                selection = Set(visibleROMs.map(\.id))
                            }
                        }
                        .disabled(visibleROMs.isEmpty)
                    } else {
                        Button {
                            showFavoritesOnly.toggle()
                        } label: {
                            Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        }
                        .accessibilityLabel(showFavoritesOnly ? "显示全部" : "只看收藏")
                    }
                }

                if isSelecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            isSelecting = false
                            selection.removeAll()
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showGrid = true
                            } label: {
                                Label("网格视图", systemImage: showGrid ? "checkmark" : "square.grid.2x2")
                            }
                            Button {
                                showGrid = false
                            } label: {
                                Label("列表视图", systemImage: !showGrid ? "checkmark" : "list.bullet")
                            }
                            Divider()
                            Button {
                                isSelecting = true
                            } label: {
                                Label("批量选择", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                model.showImporter = true
                            } label: {
                                Label("选择文件（可多选）", systemImage: "doc.on.doc")
                            }
                            Button {
                                showFolderPicker = true
                            } label: {
                                Label("导入整个文件夹", systemImage: "folder")
                            }
                            Button {
                                showRemoteImport = true
                            } label: {
                                Label("从直链 / WebDAV 导入", systemImage: "globe")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { batchBar }
            }
            .overlay { importProgressOverlay }
            .fullScreenCover(item: $selectedROM) { rom in
                GameView(rom: rom)
            }
            .sheet(isPresented: $model.showImporter) {
                DocumentPicker { urls in
                    startImport(urls)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { folderURL in
                    importFolder(folderURL)
                }
            }
            .sheet(isPresented: $showRemoteImport) {
                RemoteImportView { localFile in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        startImport([localFile])
                        try? FileManager.default.removeItem(at: localFile)
                    }
                }
            }
            .alert("导入结果", isPresented: Binding(
                get: { model.importSummary != nil },
                set: { if !$0 { model.importSummary = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(model.importSummary ?? "")
            }
            .alert("已删除", isPresented: Binding(
                get: { actionMessage != nil },
                set: { if !$0 { actionMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(actionMessage ?? "")
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
            .confirmationDialog(
                "删除选中的 \(selection.count) 款游戏？",
                isPresented: $confirmBatchDelete,
                titleVisibility: .visible
            ) {
                Button("删除 \(selection.count) 款（含存档）", role: .destructive) {
                    deleteSelection()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("每款游戏的 ROM 文件、即时存档、金手指记录都会被删除，无法恢复。")
            }
        }
    }

    // MARK: - 视图

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(visibleROMs) { rom in
                    ROMCard(rom: rom, model: model)
                        .overlay(alignment: .topLeading) { selectionBadge(rom) }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting {
                                toggleSelection(rom)
                            } else {
                                model.markPlayed(rom)
                                selectedROM = rom
                            }
                        }
                        .contextMenu {
                            if !isSelecting {
                                Button {
                                    model.toggleFavorite(rom)
                                } label: {
                                    Label(rom.isFavorite ? "取消收藏" : "收藏",
                                          systemImage: rom.isFavorite ? "star.slash" : "star")
                                }
                                Button(role: .destructive) {
                                    pendingDelete = rom
                                } label: {
                                    Label("从库中移除", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List {
            ForEach(visibleROMs) { rom in
                HStack {
                    if isSelecting {
                        Image(systemName: selection.contains(rom.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(rom.id) ? Color.accentColor : .secondary)
                    }
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
                    if isSelecting {
                        toggleSelection(rom)
                    } else {
                        model.markPlayed(rom)
                        selectedROM = rom
                    }
                }
                .contextMenu {
                    if !isSelecting {
                        Button(role: .destructive) {
                            pendingDelete = rom
                        } label: {
                            Label("从库中移除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func selectionBadge(_ rom: ROMEntry) -> some View {
        Group {
            if isSelecting {
                Image(systemName: selection.contains(rom.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selection.contains(rom.id) ? Color.accentColor : Color.black.opacity(0.45))
                    .padding(6)
            }
        }
    }

    private var batchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text("已选 \(selection.count) 款")
                    .font(.callout)
                Spacer()
                Button(role: .destructive) {
                    confirmBatchDelete = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selection.isEmpty)
            }
            HintText("点卡片选择；删除会连 ROM 文件、即时存档、金手指一起删掉，无法恢复。")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var importProgressOverlay: some View {
        Group {
            if let importProgress {
                VStack(spacing: 8) {
                    ProgressView(value: Double(importProgress.done),
                                 total: Double(max(importProgress.total, 1)))
                        .frame(width: 180)
                    Text("正在导入 \(importProgress.done)/\(importProgress.total)")
                        .font(.caption)
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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

            支持一次选多个文件，或「导入整个文件夹」批量添加；
            也可以从直链 / WebDAV 直接下载导入。
            ROM 由你自行提供，本 App 不含任何游戏数据。
            """)
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func coverImage(for rom: ROMEntry) -> Image {
        Image(crossImage: model.coverImage(for: rom), placeholder: "gamecontroller")
    }

    // MARK: - 批量操作

    private func toggleSelection(_ rom: ROMEntry) {
        if selection.contains(rom.id) {
            selection.remove(rom.id)
        } else {
            selection.insert(rom.id)
        }
    }

    private func deleteSelection() {
        let victims = model.roms.filter { selection.contains($0.id) }
        let count = model.remove(victims)
        selection.removeAll()
        isSelecting = false
        Haptics.success()
        actionMessage = "已删除 \(count) 款游戏，同时清理了各自的存档与金手指。"
    }

    // MARK: - 导入

    /// 统一入口：显示进度、调用模型、隐藏进度
    private func startImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importProgress = (0, urls.count)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            model.importFiles(urls: urls) { done, total in
                Task { @MainActor in importProgress = (done, total) }
            }
            importProgress = nil
        }
    }

    /// 文件夹导入：递归收集支持的文件后走同一条导入流水线
    private func importFolder(_ folder: URL) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let supported: Set<String> = [
            "nes", "fds", "unf", "unif", "gb", "gbc", "gba",
            "zip", "7z", "cht", "srm", "sav",
        ]
        var urls: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                if supported.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
        }
        guard !urls.isEmpty else {
            model.importSummary = "文件夹里没有可导入的文件（支持 .nes/.gb/.gba/.zip/.7z/.cht/.srm/.sav）"
            return
        }
        startImport(urls)
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
                    let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                    NSLog("[MiniRetro] 下载自测：%@ (%lld 字节) → 开始导入", file.lastPathComponent, size)
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

/// 选择整个文件夹（递归导入，适合一次拷一堆 ROM 进来）
struct FolderPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let first = urls.first { onPicked(first) }
        }
    }
}
#endif
