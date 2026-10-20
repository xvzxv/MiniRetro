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
                                model.remove(rom)
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
            Text("点击右上角 + 导入 ROM（.nes / .gb / .gbc / .gba / .zip）\nROM 由你自行提供，本 App 不含任何游戏数据")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func coverImage(for rom: ROMEntry) -> Image {
        Image(crossImage: model.coverImage(for: rom), placeholder: "gamecontroller")
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
