// AudioRingBuffer.mm
#import "AudioRingBuffer.h"

#include <os/lock.h>
#include <string.h>
#include <stdlib.h>

@interface AudioRingBuffer () {
    int16_t *_buffer;
    NSUInteger _capacity;   // 帧数（每帧 2 声道）
    NSUInteger _readIdx;
    NSUInteger _writeIdx;
    NSUInteger _available;
    os_unfair_lock _lock;
}
@end

@implementation AudioRingBuffer

- (instancetype)initWithCapacityFrames:(NSUInteger)capacityFrames {
    self = [super init];
    if (self) {
        _capacity = capacityFrames > 1024 ? capacityFrames : 1024;
        _buffer = (int16_t *)calloc(_capacity * 2, sizeof(int16_t));
        _readIdx = 0;
        _writeIdx = 0;
        _available = 0;
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)dealloc {
    free(_buffer);
}

- (void)writeSamples:(const int16_t *)samples frameCount:(NSUInteger)frameCount {
    if (samples == NULL || frameCount == 0) {
        return;
    }
    os_unfair_lock_lock(&_lock);
    // 溢出时丢弃最旧数据（低延迟优先）
    if (frameCount > _capacity) {
        samples += (frameCount - _capacity) * 2;
        frameCount = _capacity;
    }
    NSUInteger overflow = frameCount > (_capacity - _available) ? frameCount - (_capacity - _available) : 0;
    if (overflow > 0) {
        _readIdx = (_readIdx + overflow) % _capacity;
        _available -= overflow;
    }
    NSUInteger first = MIN(frameCount, _capacity - _writeIdx);
    memcpy(_buffer + _writeIdx * 2, samples, first * 2 * sizeof(int16_t));
    if (first < frameCount) {
        memcpy(_buffer, samples + first * 2, (frameCount - first) * 2 * sizeof(int16_t));
    }
    _writeIdx = (_writeIdx + frameCount) % _capacity;
    _available += frameCount;
    os_unfair_lock_unlock(&_lock);
}

- (NSUInteger)readSamples:(int16_t *)outBuffer frameCount:(NSUInteger)frameCount {
    if (outBuffer == NULL || frameCount == 0) {
        return 0;
    }
    os_unfair_lock_lock(&_lock);
    NSUInteger toRead = MIN(frameCount, _available);
    NSUInteger first = MIN(toRead, _capacity - _readIdx);
    memcpy(outBuffer, _buffer + _readIdx * 2, first * 2 * sizeof(int16_t));
    if (first < toRead) {
        memcpy(outBuffer + first * 2, _buffer, (toRead - first) * 2 * sizeof(int16_t));
    }
    _readIdx = (_readIdx + toRead) % _capacity;
    _available -= toRead;
    // 欠载补静音，保证音频流连续
    if (toRead < frameCount) {
        memset(outBuffer + toRead * 2, 0, (frameCount - toRead) * 2 * sizeof(int16_t));
    }
    os_unfair_lock_unlock(&_lock);
    return toRead;
}

- (NSUInteger)availableFrames {
    os_unfair_lock_lock(&_lock);
    NSUInteger v = _available;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (void)reset {
    os_unfair_lock_lock(&_lock);
    _readIdx = 0;
    _writeIdx = 0;
    _available = 0;
    os_unfair_lock_unlock(&_lock);
}

@end
