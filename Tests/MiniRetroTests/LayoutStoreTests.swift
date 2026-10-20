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
        XCTAssertEqual(fc.buttons.count, 8)

        let gba = ControlLayouts.default(system: .gba, skin: .minimal)
        XCTAssertNotNil(gba.button(.l))
        XCTAssertNotNil(gba.button(.r))
        XCTAssertEqual(gba.buttons.count, 10)
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
