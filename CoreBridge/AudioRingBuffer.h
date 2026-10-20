// AudioRingBuffer.h — 线程安全音频环形缓冲（int16 立体声交错）
// core 线程写入（audio_sample_batch 回调），音频渲染线程拉取（AVAudioSourceNode）。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioRingBuffer : NSObject

- (instancetype)initWithCapacityFrames:(NSUInteger)capacityFrames;

/// 写入（丢弃溢出的最旧数据，保证低延迟优先）。线程安全。
- (void)writeSamples:(const int16_t *)samples frameCount:(NSUInteger)frameCount;

/// 读取（数据不足时静音补齐）。线程安全。返回实际读取的帧数。
- (NSUInteger)readSamples:(int16_t *)outBuffer frameCount:(NSUInteger)frameCount;

/// 当前可读帧数（含欠载判断用）。
- (NSUInteger)availableFrames;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
