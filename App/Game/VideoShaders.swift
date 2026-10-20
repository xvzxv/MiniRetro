// VideoShaders.swift — 视频滤镜 shader 源码（运行时编译）
//
// 为什么运行时编译而不是 .metal 文件：
//   Xcode 26+ 把 Metal 编译器拆成独立组件（MetalToolchain），未安装时
//   `xcodebuild` 直接失败（cannot execute tool 'metal'）。运行时用
//   MTLDevice.makeLibrary(source:) 编译，构建零外部依赖、可复现。
//   4 个 fragment shader 的编译开销约几十毫秒，仅首次创建渲染器时一次。
//
// 与 App/Resources/VideoShaders.metal 保持一致（该文件保留为源码参考，不参与编译）。
import Metal

enum VideoShaderSource {
    static let all = """
    #include <metal_stdlib>
    using namespace metal;

    struct RasterizerData {
        float4 clipPos [[position]];
        float2 uv;
    };

    struct FilterUniforms {
        float2 textureSize;
        float2 screenSize;
        float  intensity;
        float  time;
    };

    vertex RasterizerData video_vertex(uint vid [[vertex_id]]) {
        float2 positions[4] = { float2(-1.0, 1.0), float2(1.0, 1.0),
                                float2(-1.0, -1.0), float2(1.0, -1.0) };
        float2 uvs[4] = { float2(0.0, 0.0), float2(1.0, 0.0),
                          float2(0.0, 1.0), float2(1.0, 1.0) };
        RasterizerData out;
        out.clipPos = float4(positions[vid], 0.0, 1.0);
        out.uv = uvs[vid];
        return out;
    }

    fragment float4 video_filter_integer(RasterizerData in [[stage_in]],
                                         texture2d<float> frameTexture [[texture(0)]]) {
        constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        return frameTexture.sample(nearestSampler, in.uv);
    }

    fragment float4 video_filter_smooth(RasterizerData in [[stage_in]],
                                        texture2d<float> frameTexture [[texture(0)]],
                                        sampler linearSampler [[sampler(0)]]) {
        return frameTexture.sample(linearSampler, in.uv);
    }

    fragment float4 video_filter_crt(RasterizerData in [[stage_in]],
                                     texture2d<float> frameTexture [[texture(0)]],
                                     constant FilterUniforms &uniforms [[buffer(0)]]) {
        constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float2 texel = 1.0 / uniforms.textureSize;

        // 轻微色差：RGB 通道水平偏移半个物理像素
        float scanlinePixels = max(uniforms.screenSize.y / uniforms.textureSize.y, 1.0);
        float offset = texel.x * 0.5 / scanlinePixels;
        float r = frameTexture.sample(nearestSampler, in.uv + float2(offset, 0.0)).r;
        float g = frameTexture.sample(nearestSampler, in.uv).g;
        float b = frameTexture.sample(nearestSampler, in.uv - float2(offset, 0.0)).b;
        float3 color = float3(r, g, b);

        // 扫描线：按物理行衰减
        float row = in.uv.y * uniforms.screenSize.y;
        float scan = 1.0 - 0.18 * uniforms.intensity * fract(row);
        color *= scan;

        // 暗角
        float2 d = in.uv - 0.5;
        float vignette = 1.0 - uniforms.intensity * 0.35 * dot(d, d);
        color *= vignette;

        return float4(color, 1.0);
    }

    fragment float4 video_filter_lcd(RasterizerData in [[stage_in]],
                                     texture2d<float> frameTexture [[texture(0)]],
                                     constant FilterUniforms &uniforms [[buffer(0)]]) {
        constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

        // 每个逻辑像素映射为 3x3 点阵
        float grid = 3.0;
        float2 cell = 1.0 / (uniforms.textureSize * grid);
        float2 cellIndex = floor(in.uv / cell);
        float2 withinCell = fract(in.uv / cell);

        float2 logicCenter = (cellIndex + 0.5) * cell;
        float3 color = frameTexture.sample(nearestSampler, logicCenter).rgb;

        float2 dotMask = smoothstep(0.5, 0.42, abs(withinCell - 0.5));
        float mask = dotMask.x * dotMask.y;
        float3 lcdBase = float3(0.42, 0.52, 0.32);
        float3 result = mix(lcdBase * 0.35, color, mask * 0.92 + 0.08);
        return float4(result, 1.0);
    }
    """

    /// 编译 shader 库（失败返回 nil 并记录原因，不崩溃）
    static func makeLibrary(device: MTLDevice) -> MTLLibrary? {
        do {
            let options = MTLCompileOptions()
            // mathMode 需 iOS 18+；部署目标 17.0 → 旧系统回退 fastMathEnabled
            if #available(iOS 18.0, macOS 15.0, *) {
                options.mathMode = .fast
            } else {
                options.fastMathEnabled = true
            }
            return try device.makeLibrary(source: all, options: options)
        } catch {
            MRLog.error("Metal shader 编译失败: \(error.localizedDescription)")
            return nil
        }
    }
}
