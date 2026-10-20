// VideoShaders.metal — 视频滤镜（M7）
// 约定：输入为 BGRA8Unorm 帧纹理（FramePipeline 输出），输出到 MTKView drawable。
// - integer: 最近邻采样（默认，像素风）
// - smooth:  线性采样
// - crt:     CRT 扫描线 + 暗角 + 轻微色差
// - lcd:     GB LCD 点阵
#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 clipPos [[position]];
    float2 uv;
} RasterizerData;

struct FilterUniforms {
    float2 textureSize;   // 逻辑纹理尺寸（如 256x240）
    float2 screenSize;    // 绘制目标尺寸（像素）
    float  intensity;     // 滤镜强度 0-1
    float  time;          // 秒
};

static RasterizerData video_vertex_impl(uint vid [[vertex_id]]) {
    float2 positions[4] = { float2(-1.0, 1.0), float2(1.0, 1.0), float2(-1.0, -1.0), float2(1.0, -1.0) };
    float2 uvs[4] = { float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0) };
    // 注意：帧纹理行序与 Metal 纹理坐标一致（y=0 在顶部）
    RasterizerData out;
    out.clipPos = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

vertex RasterizerData video_vertex(uint vid [[vertex_id]]) {
    return video_vertex_impl(vid);
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

    // 每个逻辑像素映射为 grid×grid 点阵
    float grid = 3.0;
    float2 cell = 1.0 / (uniforms.textureSize * grid);
    float2 cellIndex = floor(in.uv / cell);
    float2 withinCell = fract(in.uv / cell);

    // 取该逻辑像素中心的颜色（点阵只显示中心亮点）
    float2 logicCenter = (cellIndex + 0.5) * cell;
    float3 color = frameTexture.sample(nearestSampler, logicCenter).rgb;

    // 点阵掩码：亮点 + 网格暗线
    float2 dotMask = smoothstep(0.5, 0.42, abs(withinCell - 0.5));
    float mask = dotMask.x * dotMask.y;
    float3 lcdBase = float3(0.42, 0.52, 0.32); // GB LCD 底色
    float3 result = mix(lcdBase * 0.35, color, mask * 0.92 + 0.08);
    return float4(result, 1.0);
}
