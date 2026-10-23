// CheatEditorView.swift — 金手指管理界面（M2/M3/M4）
import SwiftUI

struct CheatEditorView: View {
    @ObservedObject var viewModel: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newCode = ""
    @State private var newType: CheatEntry.CheatType = .gameShark
    @State private var message: String?
    @State private var showCommunity = false
    @State private var importedFiles: [ImportedCheatFile] = []

    /// 当前系统支持的作弊码类型
    private var supportedTypes: [CheatEntry.CheatType] {
        switch viewModel.rom.system {
        case .gba: return [.rawRAM, .gameShark, .actionReplay, .codeBreaker]
        case .fc, .fds: return [.gameGenie, .rawRAM]
        case .gb, .gbc: return [.gameShark, .gameGenie, .rawRAM]
        case .arcade: return [.gameShark, .rawRAM]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.cheats.cheats) { cheat in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { cheat.isEnabled },
                                set: { _ in viewModel.cheats.toggle(cheat) }
                            ))
                            .labelsHidden()
                            .frame(width: 44)
                            VStack(alignment: .leading) {
                                Text(cheat.name).font(.headline)
                                Text("\(cheat.type.rawValue) · \(cheat.code)")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.cheats.remove(cheat)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                } header: {
                    Text("已启用的金手指（\(viewModel.cheats.cheats.filter(\.isEnabled).count)）")
                }

                Section {
                    Button {
                        showCommunity = true
                    } label: {
                        Label("从社区金手指库查找", systemImage: "magnifyingglass.circle")
                    }
                    HintText("按游戏名搜索 libretro-database 社区库，勾选后一键导入并立即生效；搜索离线完成，只下载选中的代码。")
                } header: {
                    Text("在线查找")
                }

                if !importedFiles.isEmpty {
                    Section {
                        ForEach(importedFiles) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name).font(.callout)
                                    Text("\(CheatFileStore.parse(file, system: viewModel.rom.system).count) 条代码")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("应用") { applyImported(file) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { CheatFileStore.remove(importedFiles[index]) }
                            reloadImported()
                        }
                    } header: {
                        Text("已导入的金手指文件")
                    } footer: {
                        HintText("这些是你用游戏库「+」导入的 .cht 文件（libretro 社区格式）。点「应用」把里面所有代码加到本游戏；左滑删除文件。")
                    }
                }

                Section {
                    TextField("备注名（如：无限生命）", text: $newName)
                    TextField("作弊码（如：金手指代码）", text: $newCode)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("类型", selection: $newType) {
                        ForEach(supportedTypes, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    HintText("类型只是标注，代码会原样交给内核：Game Genie 形如 SXIOPO；内存写入形如 00AE:41（地址:值）。")
                    Button("添加并生效") {
                        addCheat()
                    }
                    .disabled(newCode.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("手动添加")
                }

                Section {
                    Text("金手指通过 libretro `retro_cheat_set` 下发：FC 为 Game Genie 或 `地址:值`，GB/GBC 为 GameShark/Game Genie，GBA 为 GameShark/Action Replay/CodeBreaker。")
                    Text("修改后立即生效，并保存在 Cheats/<游戏ID>.json，下次进游戏自动套用。街机（FBNeo）社区库没有归档，只能手动录入或导入 .cht。")
                } header: {
                    Text("说明")
                } footer: {
                    HintText("代码来源不可靠时可能卡死或花屏，出问题先关掉全部金手指再排查。")
                }
            }
            .navigationTitle("金手指")
            
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .sheet(isPresented: $showCommunity) {
                CommunityCheatView(viewModel: viewModel)
            }
            .onAppear { reloadImported() }
        }
    }

    private func reloadImported() {
        importedFiles = CheatFileStore.list()
    }

    /// 把导入的 .cht 文件里所有代码加到当前游戏
    private func applyImported(_ file: ImportedCheatFile) {
        let parsed = CheatFileStore.parse(file, system: viewModel.rom.system)
        guard !parsed.isEmpty else {
            message = "这个 .cht 里没有可解析的代码（文件可能不是 libretro 格式）"
            return
        }
        for cheat in parsed {
            viewModel.cheats.add(name: cheat.desc, code: cheat.code, type: cheat.type)
        }
        Haptics.success()
        message = "已从 \(file.name) 导入 \(parsed.count) 条"
    }

    private func addCheat() {
        let code = newCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.cheats.add(
            name: name.isEmpty ? "金手指 \(viewModel.cheats.cheats.count + 1)" : name,
            code: code,
            type: newType
        )
        newName = ""
        newCode = ""
        Haptics.success()
    }
}
