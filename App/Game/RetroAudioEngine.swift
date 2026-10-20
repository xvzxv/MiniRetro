// RetroAudioEngine.swift — AVAudioEngine 音频输出（M1）
// core 线程写 AudioRingBuffer → AVAudioSourceNode render block 拉取 + 线性重采样
import AVFoundation
import Foundation

final class RetroAudioEngine {
    private let engine = AVAudioEngine()
    private let ringBuffer: AudioRingBuffer
    private var sourceNode: AVAudioSourceNode?
    private var inputRate: Double = 44100
    private var volume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }
    private(set) var isRunning = false

    init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
    }

    /// 启动音频（应在 ROM 加载、拿到采样率后调用）
    func start(sampleRate: Double, volume: Float) {
        stop()
        inputRate = sampleRate > 0 ? sampleRate : 44100
        self.volume = volume

        guard let format = AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: 2) else {
            MRLog.error("AVAudioFormat 创建失败 sampleRate=\(inputRate)")
            return
        }

        // 源节点按输入采样率提供数据；AVAudioEngine 内部重采样到硬件格式
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let frames = Int(frameCount)
            // 环形缓冲为 int16 交错 [L,R,...]，拆为引擎要求的非交错 float
            var scratch = [Int16](repeating: 0, count: max(frames * 2, 2))
            scratch.withUnsafeMutableBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                self.ringBuffer.readSamples(base, frameCount: UInt(frames))
                for i in 0..<frames {
                    left[i] = Float(base[i * 2]) / 32768.0
                    right[i] = Float(base[i * 2 + 1]) / 32768.0
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        do {
            try engine.start()
            sourceNode = node
            isRunning = true
            MRLog.info("音频启动 sampleRate=\(inputRate)")
        } catch {
            MRLog.error("AVAudioEngine 启动失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        if isRunning {
            engine.stop()
            isRunning = false
        }
        ringBuffer.reset()
    }

    func setVolume(_ value: Float) {
        volume = max(0, min(1, value))
        engine.mainMixerNode.outputVolume = volume
    }

    /// 音频延迟估计（ms）：环形缓冲帧数 / 输入采样率
    func estimatedLatencyMs() -> Double {
        Double(ringBuffer.availableFrames()) / inputRate * 1000.0
    }
}
