// romlib_test.swift — ROM 库逻辑回归测试（macOS 命令行可执行，无需模拟器）
//
// 覆盖用户反馈的「每次重启每个 ROM 多出一个文件已损坏条目」：
//   1. 旧索引里带 ROMs/ 前缀的失效条目 → 必须被归一化/清理，不能变成损坏条目
//   2. 索引里指向已删除文件的条目 → 必须被自愈删除
//   3. 重复导入同一 ROM → 只保留一条，且不再生成 x-1.nes 副本
//   4. 真 ROM（水浒神兽）识别为 fc + fceumm
//
// 运行：Tools/run_romlib_test.sh
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("  ✅ \(label)")
    } else {
        print("  ❌ \(label)")
        failures += 1
    }
}

let fm = FileManager.default
let docs = fm.documentsDirectory
let romsDir = ROMImporter.romsDirectory
let indexURL = docs.appendingPathComponent("Library/index.json")

// 干净环境
try? fm.removeItem(at: romsDir)
try? fm.removeItem(at: docs.appendingPathComponent("Library"))
fm.ensureDirectory(romsDir)
fm.ensureDirectory(indexURL.deletingLastPathComponent())

print("[1] 真实 ROM 识别")
let romSource = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_ROM"] ?? "")
let romData = (try? Data(contentsOf: romSource)) ?? Data()
check(!romData.isEmpty, "测试 ROM 可读（\(romData.count) 字节）")
if let identified = ROMImporter.identify(data: romData, fileName: romSource.lastPathComponent) {
    check(identified.system == .fc, "识别为 FC（实际 \(identified.system.rawValue)）")
    check(identified.coreName == "fceumm", "分派 fceumm（实际 \(identified.coreName)）")
} else {
    check(false, "ROM 识别成功")
}

print("[2] 首次导入 + 重复导入去重")
var index = LibraryIndex()
let first = ROMImporter.importFile(from: romSource, into: &index)
check(first.imported.count == 1, "首次导入 1 款（实际 \(first.imported.count)）")
let second = ROMImporter.importFile(from: romSource, into: &index)
check(second.imported.isEmpty, "重复导入不再新增（实际新增 \(second.imported.count)）")
check(second.skippedDuplicates == 1, "重复导入记为跳过 1 次（实际 \(second.skippedDuplicates)）")
let filesInFc = (try? fm.contentsOfDirectory(atPath: romsDir.appendingPathComponent("fc").path)) ?? []
check(filesInFc.count == 1, "ROMs/fc 下只有 1 份文件（实际 \(filesInFc.count)：\(filesInFc)）")
check(index.roms.count == 1, "索引 1 条（实际 \(index.roms.count)）")

print("[3] 旧索引带 ROMs/ 前缀 + 幽灵条目（复现用户 bug）")
// 手工构造旧版本索引：一条带前缀的失效路径 + 一条指向已删除文件
if let real = index.roms.first {
    var legacy = LibraryIndex()
    var prefixed = real
    prefixed.relativePath = "ROMs/\(real.relativePath)"   // 旧版写法：路径多了一层 ROMs/
    prefixed.isCorrupted = true
    var ghost = real
    ghost.id = UUID()
    ghost.fileName = "已删除的游戏.nes"
    ghost.relativePath = "fc/已删除的游戏.nes"
    ghost.isCorrupted = true
    legacy.roms = [prefixed, ghost]
    if let data = try? JSONEncoder().encode(legacy) {
        try? data.write(to: indexURL)
    }
}
var loaded = (try? JSONDecoder().decode(LibraryIndex.self, from: fm.contents(atPath: indexURL.path) ?? Data())) ?? LibraryIndex()
loaded.normalize()
let scan = ROMImporter.scanExisting(into: &loaded)
print("  · 扫描新增 \(scan.imported.count) 条")
check(loaded.roms.count == 1, "清理后只剩 1 条（实际 \(loaded.roms.count)：\(loaded.roms.map(\.relativePath))）")
check(loaded.roms.allSatisfy { !$0.isCorrupted }, "没有任何条目被标记为损坏")
check(loaded.roms.first?.relativePath == index.roms.first?.relativePath,
      "路径已归一化为 \(index.roms.first?.relativePath ?? "?")")

print("[4] 二次扫描幂等（模拟「再次打开 App」）")
let before = loaded.roms.count
_ = ROMImporter.scanExisting(into: &loaded)
check(loaded.roms.count == before, "再次扫描条目数不变（\(before) → \(loaded.roms.count)）")
check(loaded.roms.allSatisfy { !$0.isCorrupted }, "再次扫描后依然没有损坏条目")

print("[5] zip 语义区分（压缩包 vs 街机 romset）")
if let arcadeZipPath = ProcessInfo.processInfo.environment["ARCADE_ZIP"], !arcadeZipPath.isEmpty {
    var arcadeIndex = LibraryIndex()
    let result = ROMImporter.importFile(from: URL(fileURLWithPath: arcadeZipPath), into: &arcadeIndex)
    check(result.imported.count == 1, "街机 zip 入库 1 条（实际 \(result.imported.count)，失败 \(result.failed.map(\.reason))）")
    check(result.imported.first?.system == .arcade,
          "系统识别为 arcade（实际 \(result.imported.first?.system.rawValue ?? "nil")）")
    check(result.imported.first?.relativePath.hasPrefix("arcade/") == true,
          "存放于 ROMs/arcade/（实际 \(result.imported.first?.relativePath ?? "nil")）")
} else {
    print("  ⏳ 跳过（未提供 ARCADE_ZIP）")
}

print("[6] 社区金手指解析（libretro .cht 格式）")
let sampleCHT = """
cheats = 3

cheat0_desc = "Infinite Lives"
cheat0_code = "SXIOPO"
cheat0_enable = false

cheat1_desc = "99 Lives"
cheat1_code = "A2-B3-C4"
cheat1_enable = false

cheat2_desc = "No Code (should be skipped)"
cheat2_code = ""
cheat2_enable = false
"""
let parsedCheats = CommunityCheatService.parse(text: sampleCHT, system: .fc)
check(parsedCheats.count == 2, "解析出 2 条（空代码被跳过，实际 \(parsedCheats.count)）")
check(parsedCheats.first?.desc == "Infinite Lives", "名称解析正确（\(parsedCheats.first?.desc ?? "nil")）")
check(parsedCheats.first?.code == "SXIOPO", "代码解析正确（\(parsedCheats.first?.code ?? "nil")）")
check(parsedCheats.first?.type == .gameGenie, "FC 字母型代码推断为 Game Genie")
check(parsedCheats[1].type == .gameShark, "FC 纯 hex 代码推断为 GameShark")
check(CommunityCheatService.inferType(code: "01FF0FD2", system: .gb) == .gameShark,
      "GB 8 位 hex 推断为 GameShark")
check(CommunityCheatService.inferType(code: "00A-17B-C49", system: .gb) == .gameGenie,
      "GB 9 位 hex 三段式推断为 Game Genie")
check(CommunityCheatService.inferType(code: "00AE:41", system: .fc) == .rawRAM,
      "社区库 `地址:值` 格式推断为内存写入")
check(CommunityCheatService.parse(text: "cheats = 1\n\ncheat0_desc = \"Invincible\"\ncheat0_code = \"00AE:41\"\n",
                                  system: .fc).first?.type == .rawRAM,
      "真实 Contra 写法解析为内存写入")

if let indexData = ProcessInfo.processInfo.environment["CHEAT_INDEX"],
   let data = FileManager.default.contents(atPath: indexData),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let platforms = json["platforms"] as? [String: Any] {
    print("[7] 内置金手指索引")
    for key in ["fc", "gb", "gbc", "gba"] {
        let count = (platforms[key] as? [String: Any])?["files"] as? [String] ?? []
        check(!count.isEmpty, "\(key) 索引非空（\(count.count) 个文件）")
    }
} else {
    print("[7] ⏳ 跳过索引检查（未提供 CHEAT_INDEX）")
}

print("[8] 真实街机整合包（壳包）解析")
if let pkg = ProcessInfo.processInfo.environment["ARCADE_PACKAGE"], !pkg.isEmpty {
    var arcadeIndex = LibraryIndex()
    let result = ROMImporter.importFile(from: URL(fileURLWithPath: pkg), into: &arcadeIndex)
    let names = result.imported.map(\.fileName)
    check(result.imported.count == 1, "壳包拆出 1 个 romset（实际 \(result.imported.count)：\(names)）")
    check(names.first?.lowercased() == "kovsh.zip", "取到内层 romset 而非外层壳包（实际 \(names.first ?? "nil")）")
    check(!names.contains(where: { $0.lowercased().hasPrefix("kovsh_v13") }),
          "外层壳包未入库（否则驱动名不匹配必然加载失败）")
    let storedPath = result.imported.first.map {
        ROMImporter.romsDirectory.appendingPathComponent($0.relativePath).path
    }
    let storedSize = storedPath.flatMap { FileManager.default.contents(atPath: $0)?.count } ?? 0
    check(storedSize > 15 * 1024 * 1024, "内层 romset 完整（\(storedSize / 1024 / 1024) MB，压缩态）")
} else {
    print("  ⏳ 跳过（未提供 ARCADE_PACKAGE）")
}

print("[9] 手柄方向合并（十字键 + 摇杆同时开启）")
do {
    var merger = DirectionInputMerger()
    // 按住十字键「上」
    for (button, pressed) in DirectionInputMerger.dpadDirections(up: true, down: false, left: false, right: false) {
        merger.setDpad(button, pressed)
    }
    check(merger.merged(.up), "十字键按住时方向为上")

    // 摇杆每帧回调、停在死区内（全 false）——旧实现就是在这里把方向清掉的
    for (button, pressed) in DirectionInputMerger.stickDirections(x: 0.1, y: 0.05) {
        merger.setStick(button, pressed)
    }
    check(merger.merged(.up), "摇杆回中后，十字键的「上」仍然保持（v1.8 的 bug 点）")

    // 摇杆推右，与十字键的上同时成立
    for (button, pressed) in DirectionInputMerger.stickDirections(x: 0.9, y: 0.1) {
        merger.setStick(button, pressed)
    }
    check(merger.merged(.up) && merger.merged(.right), "两个输入源可同时生效")

    // 摇杆回中，上仍保持
    for (button, pressed) in DirectionInputMerger.stickDirections(x: 0, y: 0) {
        merger.setStick(button, pressed)
    }
    check(merger.merged(.up) && !merger.merged(.right), "摇杆回中只撤销摇杆自己的方向")
}

print("")
if failures == 0 {
    print("全部通过 ✅")
} else {
    print("失败 \(failures) 项 ❌")
}
exit(failures == 0 ? 0 : 1)
