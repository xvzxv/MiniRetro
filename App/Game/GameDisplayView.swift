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
        // 布局变化时刷新 drawableSize
        uiView.drawableSize = uiView.bounds.size
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        uiView.delegate = nil
    }

    final class Coordinator {
        var renderer: EmulatorRenderer?
    }
}
