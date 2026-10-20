// EmulatorRenderer.swift — MTKView 渲染器（M1/M7）
// 每帧从 RetroCore 拉取最新软渲帧 → 上传 MTLTexture → 按滤镜绘制全屏 quad
import Metal
import MetalKit
import QuartzCore

#if canImport(UIKit)
import UIKit
#endif

/// 与 VideoShaders.metal 的 FilterUniforms 内存布局一致（float2, float2, float, float）
struct FilterUniforms {
    var textureSize: SIMD2<Float> = .zero
    var screenSize: SIMD2<Float> = .zero
    var intensity: Float = 1.0
    var time: Float = 0
}

final class EmulatorRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var retroCore: RetroCore?
    private let colorPixelFormat: MTLPixelFormat

    private var frameTexture: MTLTexture?
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0
    private var frameBuffer: [UInt8]
    private var hasFrame = false

    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var samplerState: MTLSamplerState?
    private var uniformsBuffer: MTLBuffer?

    /// 最近帧率统计（FPS 显示）
    private(set) var measuredFPS: Double = 0
    private var frameCountWindow: Int = 0
    private var windowStart: CFAbsoluteTime = 0

    init(metalView: MTKView, retroCore: RetroCore) {
        self.device = metalView.device!
        self.commandQueue = device.makeCommandQueue()!
        self.retroCore = retroCore
        self.frameBuffer = [UInt8](repeating: 0, count: 512 * 512 * 4)
        self.colorPixelFormat = metalView.colorPixelFormat
        super.init()
        buildPipelines()
        samplerState = makeLinearSampler()
        uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<FilterUniforms>.stride,
            options: .storageModeShared
        )
        metalView.delegate = self
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 60
    }

    private func makeLinearSampler() -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            MRLog.error("Metal 默认库不可用（检查 VideoShaders.metal 是否加入 target）")
            return
        }
        guard let vertexFunction = library.makeFunction(name: "video_vertex") else {
            MRLog.error("缺少 shader function: video_vertex")
            return
        }
        let names = ["video_filter_integer", "video_filter_smooth", "video_filter_crt", "video_filter_lcd"]
        for name in names {
            guard let fragmentFunction = library.makeFunction(name: name) else {
                MRLog.error("缺少 shader function: \(name)")
                continue
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            do {
                pipelines[name] = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                MRLog.error("pipeline \(name) 创建失败: \(error.localizedDescription)")
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let retroCore,
              let currentDrawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else { return }

        // 1. 拉取最新帧
        var width: Int = 0
        var height: Int = 0
        let updated = frameBuffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return retroCore.copyCurrentFrame(toBuffer: base, width: &width, height: &height)
        }
        if updated, width > 0, height > 0 {
            frameWidth = width
            frameHeight = height
            hasFrame = true
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            if let texture = device.makeTexture(descriptor: descriptor) {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: frameBuffer,
                    bytesPerRow: width * 4
                )
                frameTexture = texture
            }
        }

        // 2. 按滤镜绘制
        if hasFrame, let texture = frameTexture {
            let shaderName = SettingsStore.shared.effectiveFilter.metalShaderName
            if let pipeline = pipelines[shaderName] {
                if let buffer = uniformsBuffer {
                    var uniforms = FilterUniforms()
                    uniforms.textureSize = SIMD2<Float>(Float(frameWidth), Float(frameHeight))
                    uniforms.screenSize = SIMD2<Float>(
                        Float(view.drawableSize.width),
                        Float(view.drawableSize.height)
                    )
                    uniforms.intensity = 1.0
                    uniforms.time = Float(CACurrentMediaTime())
                    memcpy(buffer.contents(), &uniforms, MemoryLayout<FilterUniforms>.stride)
                }
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                if shaderName == "video_filter_smooth" {
                    encoder.setFragmentSamplerState(samplerState, index: 0)
                }
                if shaderName == "video_filter_crt" || shaderName == "video_filter_lcd" {
                    encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
                }
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }

        encoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()

        // 3. FPS 统计（1 秒窗口）
        let now = CACurrentMediaTime()
        if windowStart == 0 { windowStart = now }
        frameCountWindow += 1
        if now - windowStart >= 1.0 {
            measuredFPS = Double(frameCountWindow) / (now - windowStart)
            frameCountWindow = 0
            windowStart = now
        }
    }
}
