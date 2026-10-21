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
                    Text("按游戏名在 libretro-database 社区库中搜索，勾选后一键导入并立即生效。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("添加金手指") {
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
                    Button("添加并生效") {
                        addCheat()
                    }
                    .disabled(newCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    Text("金手指通过 libretro retro_cheat_set 接口下发（FC 为 Game Genie，GB/GBC 为 GameShark/Game Genie，GBA 为 GameShark/Action Replay/CodeBreaker）。修改后立即生效，重启游戏保留。")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        }
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
