// FramePipeline.mm — 统一输出 BGRA（B,G,R,A 内存序），Swift 侧直接上传 BGRA8Unorm。
#import "FramePipeline.h"

#include <pthread.h>
#include <string.h>
#include <stdlib.h>

@interface FramePipeline () {
    uint8_t *_bufferA;
    uint8_t *_bufferB;
    NSUInteger _maxWidth;
    NSUInteger _maxHeight;
    NSUInteger _frameBytes;      // 单缓冲字节数
    BOOL _frontIsA;              // YES = A 为最新帧
    BOOL _dirty;
    pthread_mutex_t _mutex;
}
@end

@implementation FramePipeline

- (instancetype)initWithMaxWidth:(NSUInteger)maxWidth maxHeight:(NSUInteger)maxHeight {
    self = [super init];
    if (self) {
        _maxWidth = maxWidth > 0 ? maxWidth : 512;
        _maxHeight = maxHeight > 0 ? maxHeight : 512;
        _frameBytes = _maxWidth * _maxHeight * 4;
        _bufferA = (uint8_t *)malloc(_frameBytes);
        _bufferB = (uint8_t *)malloc(_frameBytes);
        _frontIsA = YES;
        _dirty = NO;
        _lastFrameSize = CGSizeZero;
        pthread_mutex_init(&_mutex, NULL);
    }
    return self;
}

- (void)dealloc {
    free(_bufferA);
    free(_bufferB);
    pthread_mutex_destroy(&_mutex);
}

- (uint8_t *)backBuffer {
    return _frontIsA ? _bufferB : _bufferA;
}

- (void)pushFrame:(const void *)data width:(NSUInteger)width height:(NSUInteger)height pitch:(size_t)pitch format:(MRPixelFormat)format {
    if (data == NULL || width == 0 || height == 0) {
        return;
    }
    if (width > _maxWidth || height > _maxHeight) {
        return; // 超出预设上限，丢弃（core 不应超过 512×512）
    }
    pthread_mutex_lock(&_mutex);
    uint8_t *dst = [self backBuffer];
    const size_t rowBytes = width * 4;

    if (format == MRPixelFormatXRGB8888) {
        // libretro XRGB8888 内存字节序即 B,G,R,X → BGRA，仅需补 Alpha
        const uint8_t *src = (const uint8_t *)data;
        for (NSUInteger y = 0; y < height; y++) {
            const uint8_t *srow = src + y * pitch;
            uint8_t *drow = dst + y * rowBytes;
            for (NSUInteger x = 0; x < width; x++) {
                drow[x * 4 + 0] = srow[x * 4 + 0];
                drow[x * 4 + 1] = srow[x * 4 + 1];
                drow[x * 4 + 2] = srow[x * 4 + 2];
                drow[x * 4 + 3] = 0xFF;
            }
        }
    } else if (format == MRPixelFormatRGB565) {
        const uint16_t *src = (const uint16_t *)data;
        const size_t srcRow = pitch / 2;
        for (NSUInteger y = 0; y < height; y++) {
            const uint16_t *srow = src + y * srcRow;
            uint8_t *drow = dst + y * rowBytes;
            for (NSUInteger x = 0; x < width; x++) {
                uint16_t p = srow[x];
                drow[x * 4 + 0] = (uint8_t)((p & 0x1F) << 3);          // B
                drow[x * 4 + 1] = (uint8_t)(((p >> 5) & 0x3F) << 2);  // G
                drow[x * 4 + 2] = (uint8_t)(((p >> 11) & 0x1F) << 3); // R
                drow[x * 4 + 3] = 0xFF;
            }
        }
    } else { // MRPixelFormat0RGB1555
        const uint16_t *src = (const uint16_t *)data;
        const size_t srcRow = pitch / 2;
        for (NSUInteger y = 0; y < height; y++) {
            const uint16_t *srow = src + y * srcRow;
            uint8_t *drow = dst + y * rowBytes;
            for (NSUInteger x = 0; x < width; x++) {
                uint16_t p = srow[x];
                drow[x * 4 + 0] = (uint8_t)((p & 0x1F) << 3);
                drow[x * 4 + 1] = (uint8_t)(((p >> 5) & 0x1F) << 3);
                drow[x * 4 + 2] = (uint8_t)(((p >> 10) & 0x1F) << 3);
                drow[x * 4 + 3] = 0xFF;
            }
        }
    }

    _frontIsA = !_frontIsA;
    _dirty = YES;
    _lastFrameSize = CGSizeMake(width, height);
    pthread_mutex_unlock(&_mutex);
}

- (BOOL)copyLatestFrameToBuffer:(uint8_t *)outBuffer width:(out NSUInteger *)width height:(out NSUInteger *)height {
    if (outBuffer == NULL) {
        return NO;
    }
    pthread_mutex_lock(&_mutex);
    BOOL has = _dirty;
    if (has) {
        const uint8_t *front = _frontIsA ? _bufferA : _bufferB;
        NSUInteger w = (NSUInteger)_lastFrameSize.width;
        NSUInteger h = (NSUInteger)_lastFrameSize.height;
        memcpy(outBuffer, front, w * h * 4);
        if (width) { *width = w; }
        if (height) { *height = h; }
        _dirty = NO;
    }
    pthread_mutex_unlock(&_mutex);
    return has;
}

- (BOOL)hasNewFrame {
    return _dirty;
}

@end
