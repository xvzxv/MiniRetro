// LayoutStoreTests.swift — 布局模型与持久化（M6 验收：自定义布局重启不丢失）
import XCTest
@testable import MiniRetro

final class LayoutStoreTests: XCTestCase {
    func testDefaultLayoutsCoverExpectedButtons() {
        let fc = ControlLayouts.default(system: .fc, skin: .classic)
        // FC 不应包含 Y/X/L/R
        XCTAssertNil(fc.button(.l))
        XCTAssertNil(fc.button(.r))
        XCTAssertNotNil(fc.button(.a))
        XCTAssertNotNil(fc.button(.b))
        XCTAssertNotNil(fc.button(.start))
        XCTAssertNotNil(fc.button(.select))
        // 新增连发键：方向4 + select/start 2 + A/B 2 + 连发 2 = 10
        XCTAssertNotNil(fc.button(.turboA), "FC 应包含连发 A 键")
        XCTAssertNotNil(fc.button(.turboB), "FC 应包含连发 B 键")
        XCTAssertEqual(fc.buttons.count, 10)

        let gba = ControlLayouts.default(system: .gba, skin: .minimal)
        XCTAssertNotNil(gba.button(.l))
        XCTAssertNotNil(gba.button(.r))
        XCTAssertNotNil(gba.button(.turboA))
        XCTAssertEqual(gba.buttons.count, 12)

        // 布局几何：A/B 应与方向键同高，连发键在 A/B 上方
        let dpadY = fc.button(.left)?.relativeY ?? 0
        XCTAssertEqual(fc.button(.a)?.relativeY ?? -1, dpadY, accuracy: 0.001,
                       "A 应与方向键同一水平线")
        XCTAssertEqual(fc.button(.b)?.relativeY ?? -1, dpadY, accuracy: 0.001,
                       "B 应与方向键同一水平线")
        XCTAssertLessThan(fc.button(.turboA)?.relativeY ?? 1, dpadY, "连发键应在 A/B 上方")
        // A 在左、B 在右
        XCTAssertLessThan(fc.button(.a)?.relativeX ?? 1, fc.button(.b)?.relativeX ?? 0)
        // SELECT/START 为椭圆
        XCTAssertGreaterThan(fc.button(.select)?.aspect ?? 1, 1.5, "SELECT 应为椭圆")
    }

    func testArcadeLayoutHasFourActionButtons() {
        let arcade = ControlLayouts.default(system: .arcade, skin: .classic)
        // 方向 4 + SELECT/START 2 + A/B/C/D 4 = 10
        XCTAssertEqual(arcade.buttons.count, 10)
        // 四键齐全：A/B/C/D 复用 libretro 的 A/B/Y/X 位，靠 label 显示
        let labels = Set(arcade.buttons.compactMap { $0.label })
        XCTAssertEqual(labels, ["A", "B", "C", "D"])
        // 街机键位必须是 2×2：A/B 在下，C/D 在上
        let a = arcade.button(.a)!
        let c = arcade.button(.y)!
        XCTAssertEqual(a.relativeY, arcade.button(.b)!.relativeY, accuracy: 0.001)
        XCTAssertEqual(c.relativeY, arcade.button(.x)!.relativeY, accuracy: 0.001)
        XCTAssertLessThan(c.relativeY, a.relativeY, "C/D 应在 A/B 上方")
        // 方向上 A 在左、B 在右
        XCTAssertLessThan(a.relativeX, arcade.button(.b)!.relativeX)
    }

    func testLayoutRoundTrip() throws {
        var layout = ControlLayouts.default(system: .gba, skin: .classic)
        if let idx = layout.buttons.firstIndex(where: { $0.button == .a }) {
            layout.buttons[idx].relativeX = 0.42
            layout.buttons[idx].opacity = 0.55
        }
        LayoutStore.save(layout)
        let loaded = LayoutStore.load(system: .gba, skin: .classic)
        XCTAssertEqual(loaded.button(.a)?.relativeX ?? -1, 0.42, accuracy: 0.001)
        XCTAssertEqual(loaded.button(.a)?.opacity ?? -1, 0.55, accuracy: 0.001)
        LayoutStore.reset(system: .gba, skin: .classic)
    }

    func testLayoutNormalizationRange() {
        let layout = ControlLayouts.default(system: .gb, skin: .classic)
        for button in layout.buttons {
            XCTAssertTrue((0...1).contains(button.relativeX))
            XCTAssertTrue((0...1).contains(button.relativeY))
            XCTAssertGreaterThan(button.relativeSize, 0)
        }
    }
}
