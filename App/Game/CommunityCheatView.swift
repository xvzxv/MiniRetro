// CommunityCheatView.swift — 从社区金手指库自动查找（v1.7 新增）
// 交互：搜索游戏 → 选文件 → 勾选代码 → 一键导入本地金手指列表
import SwiftUI

struct CommunityCheatView: View {
    @ObservedObject var viewModel: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var files: [CommunityCheatFile] = []
    @State private var selectedFile: CommunityCheatFile?
    @State private var cheats: [CommunityCheat] = []
    @State private var isLoading = false
    @State private var statusText: String?
    @State private var didSearch = false

    init(viewModel: EmulatorViewModel) {
        self.viewModel = viewModel
        // 用 ROM 名做初始关键词（去掉扩展名，保留完整信息供用户改写）
        _query = State(initialValue: (viewModel.rom.fileName as NSString).deletingPathExtension)
    }

    private var system: SystemType { viewModel.rom.system }

    private var selectedCount: Int { cheats.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            Group {
                if system == .arcade {
                    ContentUnavailableView(
                        "街机金手指请手动录入",
                        systemImage: "exclamationmark.triangle",
                        description: Text("社区库（libretro-database）没有按街机 romset 归档的作弊码，可在上一页手动添加。")
                    )
                } else if let selectedFile {
                    cheatList(for: selectedFile)
                } else if files.isEmpty {
                    emptyState
                } else {
                    resultList
                }
            }
            .navigationTitle(selectedFile == nil ? "社区金手指" : "选择代码")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "游戏名（建议英文，如 Contra / Pokemon）")
            .onSubmit(of: .search) { search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedFile != nil {
                        Button("返回") {
                            selectedFile = nil
                            cheats = []
                        }
                    } else {
                        Button("关闭") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedFile != nil {
                        Button("导入 \(selectedCount) 条") { importSelected() }
                            .disabled(selectedCount == 0 || isLoading)
                    } else {
                        Button("搜索") { search() }
                            .disabled(isLoading)
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView().controlSize(.large)
                }
            }
            .alert("提示", isPresented: Binding(
                get: { statusText != nil },
                set: { if !$0 { statusText = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(statusText ?? "")
            }
        }
    }

    // MARK: - 子视图

    private var emptyState: some View {
        ContentUnavailableView {
            Label(didSearch ? "没有找到匹配" : "搜索社区金手指", systemImage: "magnifyingglass")
        } description: {
            if didSearch {
                Text("换个关键词试试：社区库用的是标准英文名（如 Contra、KOF 98）")
            } else {
                Text("数据来自 libretro-database 社区维护的金手指库\n搜索离线完成，只有选中的代码才会联网下载")
            }
        } actions: {
            if didSearch {
                Button("用英文名再搜一次") {
                    query = ""
                }
            } else {
                Button("搜索「\(query)」") { search() }
            }
        }
    }

    private var resultList: some View {
        List(files) { file in
            Button {
                open(file)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayTitle)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(file.folder)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func cheatList(for file: CommunityCheatFile) -> some View {
        List {
            Section {
                ForEach($cheats) { $cheat in
                    Toggle(isOn: $cheat.isSelected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cheat.desc)
                            Text("\(cheat.type.rawValue) · \(cheat.code)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("\(file.displayTitle)（\(cheats.count) 条）")
            } footer: {
                Text("勾选需要的条目后点右上角导入；导入后会立即下发到当前运行的游戏。")
            }

            Section {
                Button(selectedCount == cheats.count ? "取消全选" : "全选") {
                    let allSelected = selectedCount == cheats.count
                    for idx in cheats.indices { cheats[idx].isSelected = !allSelected }
                }
            }
        }
    }

    // MARK: - 动作

    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        didSearch = true
        files = CommunityCheatService.search(query: keyword, system: system)
        if files.isEmpty {
            // 首轮没命中时，用 ROM 名的首个词（去掉中文修饰）再试一次
            let fallback = CommunityCheatService.normalize(keyword)
                .split(separator: " ")
                .first
                .map(String.init) ?? keyword
            if fallback != keyword {
                files = CommunityCheatService.search(query: fallback, system: system)
            }
        }
    }

    private func open(_ file: CommunityCheatFile) {
        selectedFile = file
        cheats = []
        isLoading = true
        Task {
            do {
                let fetched = try await CommunityCheatService.fetchCheats(for: file, system: system)
                await MainActor.run {
                    cheats = fetched
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    statusText = error.localizedDescription
                    selectedFile = nil
                }
            }
        }
    }

    private func importSelected() {
        let picked = cheats.filter(\.isSelected)
        guard !picked.isEmpty else { return }
        for cheat in picked {
            viewModel.cheats.add(name: cheat.desc, code: cheat.code, type: cheat.type)
        }
        Haptics.success()
        statusText = "已导入 \(picked.count) 条金手指"
        dismiss()
    }
}
