// FramePipeline.h — 软渲帧 → 像素缓冲（Metal 纹理上传由 Swift 侧 MTKView 完成）
// core 线程写入，主线程读取；双缓冲 + 锁，避免阻塞 core 线程。
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "RetroCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface FramePipeline : NSObject

- (instancetype)initWithMaxWidth:(NSUInteger)maxWidth maxHeight:(NSUInteger)maxHeight;

/// core 线程调用：提交一帧（内部拷贝，调用方缓冲可立即释放）。
- (void)pushFrame:(const void *)data width:(NSUInteger)width height:(NSUInteger)height pitch:(size_t)pitch format:(MRPixelFormat)format;

/// 主线程调用：取最新一帧到 outBuffer（XRGB8888，R/G/B 字节序，每像素 4 字节）。
/// 返回 NO 表示自上次读取以来没有新帧。
- (BOOL)copyLatestFrameToBuffer:(uint8_t *)outBuffer width:(out NSUInteger *)width height:(out NSUInteger *)height;

@property (atomic, readonly) BOOL hasNewFrame;
@property (atomic, readonly) CGSize lastFrameSize;

@end

NS_ASSUME_NONNULL_END
