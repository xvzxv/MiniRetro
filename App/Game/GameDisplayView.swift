// GameDisplayView.swift — MTKView 的 SwiftUI 包装（M1）
import MetalKit
import SwiftUI

struct GameDisplayView: UIViewRepresentable {
    let viewModel: EmulatorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.backgroundColor = .black
        metalView.contentMode = .scaleToFill
        let renderer = EmulatorRenderer(metalView: metalView, retroCore: viewModel.retroCore)
        context.coordinator.renderer = renderer
        viewModel.attachRenderer(renderer)
        return metalView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // 不要手动设置 drawableSize：首次布局时 bounds 仍为 0，
        // 强制赋值会让 MTKView 永久停止出图（autoResizeDrawable 默认已正确管理）
        if uiView.bounds.width > 0, uiView.bounds.height > 0, uiView.isPaused {
            uiView.isPaused = false
        }
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        uiView.delegate = nil
    }

    final class Coordinator {
        var renderer: EmulatorRenderer?
    }
}
