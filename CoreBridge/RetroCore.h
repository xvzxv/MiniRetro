// RetroCore.h — libretro 内核封装协议（ADR-001：App 层唯一允许接触模拟器的入口）
//
// 设计约束（来自项目计划书 3.2）：
//  - 只有 CoreBridge 能碰 libretro.h；App 层不得直接调用内核
//  - retro_run() 跑在专用串行线程；主线程只做 UI 与事件投递
//  - 输入统一走「键位状态表」：虚拟按键 / 手柄事件 → 状态表 → retro_input_state
//  - core 以动态 framework 形式嵌入，运行时 dlopen + dlsym（符号互不冲突）
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class AudioRingBuffer;
@class RetroCore;

typedef NS_ENUM(NSInteger, MRPixelFormat) {
    MRPixelFormat0RGB1555 = 0,
    MRPixelFormatXRGB8888 = 1,
    MRPixelFormatRGB565 = 2,
};

@protocol RetroCoreFrameDelegate <NSObject>
/// 视频几何信息就绪（retro_load_game + retro_get_system_av_info 之后）或发生变化。
- (void)retroCore:(RetroCore *)core didChangeVideoGeometry:(CGSize)baseSize aspectRatio:(CGFloat)aspectRatio;
/// 像素格式确定（SET_PIXEL_FORMAT 回调之后）。
- (void)retroCore:(RetroCore *)core didChangePixelFormat:(MRPixelFormat)format;
@end

@protocol RetroCoreAudioDelegate <NSObject>
/// 音频采样率确定/变化（Hz）。
- (void)retroCore:(RetroCore *)core didChangeAudioSampleRate:(NSUInteger)sampleRate;
@end

/// 联机会话预留点（M9 只定义不实现，见 specs/online-play-design.md）。
/// 未来 netplay 通过该协议接入，不改变 RetroCore 现有接口。
@protocol RetroSessionPlaceholder <NSObject>
@end

@interface RetroCore : NSObject

/// core_name ∈ {mgba, sameboy, fceumm}（对应 CoreRegistry 分派结果）。
- (instancetype)initWithCoreNamed:(NSString *)coreName NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, copy, readonly) NSString *coreName;
@property (nonatomic, weak, nullable) id<RetroCoreFrameDelegate> frameDelegate;
@property (nonatomic, weak, nullable) id<RetroCoreAudioDelegate> audioDelegate;

/// 音频环形缓冲（core 线程写、音频渲染线程读；由本类持有）。
@property (nonatomic, strong, readonly) AudioRingBuffer *audioRingBuffer;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) CGSize videoBaseSize;      ///< 逻辑分辨率（如 256×240）
@property (nonatomic, readonly) CGFloat videoAspectRatio;  ///< 显示宽高比
@property (nonatomic, readonly) MRPixelFormat pixelFormat;
@property (nonatomic, readonly) NSUInteger audioSampleRate; ///< 运行后有效，默认 44100

// MARK: - 生命周期

- (BOOL)loadROMAtPath:(NSString *)romPath error:(NSError **)error
    NS_SWIFT_NAME(loadROM(atPath:));
- (void)unloadROM;
- (void)start;   ///< 启动 run 线程（幂等）
- (void)stop;    ///< 停止 run 线程（不卸载 ROM）
- (void)pause;   ///< 暂停 run 循环（保留线程）
- (void)resume;
- (void)reset;   ///< 软复位（相当于按 Reset）

// MARK: - 输入（状态表，任意线程可调用）

/// libretro 按键 ID：B=0 Y=1 Select=2 Start=3 Up=4 Down=5 Left=6 Right=7 A=8 X=9 L=10 R=11
- (void)setButton:(NSUInteger)buttonID pressed:(BOOL)pressed forPort:(NSUInteger)port
    NS_SWIFT_NAME(setButton(_:pressed:forPort:));
- (void)clearAllButtonsForPort:(NSUInteger)port;

// MARK: - 帧数据（主线程调用）

/// 把最新一帧复制到调用方缓冲区（BGRA，每像素 4 字节）。返回 NO 表示暂无新帧。
/// buffer 至少需要 width*height*4 字节。
- (BOOL)copyCurrentFrameToBuffer:(uint8_t *)buffer
                          width:(out NSUInteger *)width
                         height:(out NSUInteger *)height
    NS_SWIFT_NAME(copyCurrentFrame(toBuffer:width:height:));

// MARK: - 存档

@property (nonatomic, readonly) NSUInteger serializeSize;   ///< 0 = 当前 core 不支持即时存档
- (nullable NSData *)serializeState;
- (BOOL)unserializeState:(NSData *)data NS_SWIFT_NAME(unserializeState(_:));
/// 电池存档目录（core 通过 SET_SAVE_DIRECTORY 获知，或由本类 flush）。
- (void)setSaveDirectory:(NSString *)path;
- (void)setSystemDirectory:(NSString *)path;
/// 若 core 暴露 SRAM 内存接口，则立即写盘（.sav）；否则 core 自行落盘。
- (void)flushBatterySave;

// MARK: - 金手指（retro_cheat_reset / retro_cheat_set，见 ADR-003）

- (void)resetCheats;
/// index 为作弊码序号；code 为空表示移除该槽。
- (void)setCheatAtIndex:(NSUInteger)index enabled:(BOOL)enabled withCode:(nullable NSString *)code
    NS_SWIFT_NAME(setCheat(at:enabled:withCode:));

// MARK: - core 变量（core options，持久化由上层 SettingsStore 负责）

- (void)updateVariable:(NSString *)key value:(nullable NSString *)value;

// MARK: - 快进

/// multiplier ∈ {2,4}；enabled=NO 恢复常速。
- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(NSInteger)multiplier
    NS_SWIFT_NAME(setFastForward(enabled:multiplier:));

@end

NS_ASSUME_NONNULL_END
