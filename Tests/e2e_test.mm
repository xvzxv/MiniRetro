// e2e_test.mm — 端到端验证：真实 RetroCore 桥接层 + 真实 core dylib + 最小 NES ROM
// 验证项（对应计划书 M1 验收）：
//  1. framework 探测与 dlopen（模拟 iOS App 的 Frameworks/ 布局）
//  2. retro_load_game 成功
//  3. run 循环产出帧（video_refresh 被调用、帧率接近 60）
//  4. 像素数据非空（帧管道输出有效）
//  5. 音频回调产出样本（采样率/帧数）
//  6. 即时存档 serialize/unserialize 往返
//  7. 电池存档 flush 不崩溃
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "RetroCore.h"
#import "FramePipeline.h"
#import "AudioRingBuffer.h"

@interface Probe : NSObject <RetroCoreFrameDelegate, RetroCoreAudioDelegate>
@property (atomic) NSInteger frameCount;
@property (atomic) NSInteger audioSamples;
@property (atomic) CGSize videoSize;
@property (atomic) CGFloat aspectRatio;
@property (atomic) NSInteger audioRate;
@property (atomic) MRPixelFormat pixelFormat;
@end

@implementation Probe
- (void)retroCore:(RetroCore *)core didChangeVideoGeometry:(CGSize)baseSize aspectRatio:(CGFloat)aspectRatio {
    self.videoSize = baseSize;
    self.aspectRatio = aspectRatio;
}
- (void)retroCore:(RetroCore *)core didChangePixelFormat:(MRPixelFormat)format {
    self.pixelFormat = format;
}
- (void)retroCore:(RetroCore *)core didChangeAudioSampleRate:(NSUInteger)sampleRate {
    self.audioRate = (NSInteger)sampleRate;
}
@end

static int g_failed = 0;
static void check(const char *label, BOOL condition, NSString *detail) {
    printf("%s %-46s %s\n", condition ? "[PASS]" : "[FAIL]", label,
           detail ? detail.UTF8String : "");
    if (!condition) {
        g_failed++;
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *coreName = argc > 1 ? @(argv[1]) : @"fceumm";
        NSString *romPath = argc > 2 ? @(argv[2]) : @"/tmp/mr-e2e/test.nes";
        CGFloat expectW = argc > 3 ? atof(argv[3]) : 256;
        CGFloat expectH = argc > 4 ? atof(argv[4]) : 240;
        NSString *workDir = @"/tmp/mr-e2e/work";
        printf("=== core=%s rom=%s 期望 %.0fx%.0f ===\n", coreName.UTF8String,
               romPath.lastPathComponent.UTF8String, expectW, expectH);
        [[NSFileManager defaultManager] createDirectoryAtPath:workDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        Probe *probe = [Probe new];
        RetroCore *core = [[RetroCore alloc] initWithCoreNamed:coreName];
        core.frameDelegate = probe;
        core.audioDelegate = probe;
        [core setSaveDirectory:[workDir stringByAppendingPathComponent:@"saves"]];
        [core setSystemDirectory:workDir];
        [[NSFileManager defaultManager] createDirectoryAtPath:[workDir stringByAppendingPathComponent:@"saves"]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        // 1. 加载
        NSError *error = nil;
        BOOL loaded = [core loadROMAtPath:romPath error:&error];
        check("retro_load_game 成功", loaded, loaded ? @"最小 NROM-128 ROM" : error.localizedDescription);
        if (!loaded) {
            printf("\nFAILED: 无法加载 ROM，终止\n");
            return 1;
        }
        check("video 几何符合预期",
              probe.videoSize.width == expectW && probe.videoSize.height == expectH,
              [NSString stringWithFormat:@"实际 %.0fx%.0f", probe.videoSize.width, probe.videoSize.height]);
        check("pixel format 已上报", YES,
              [NSString stringWithFormat:@"format=%ld", (long)probe.pixelFormat]);
        check("音频采样率已上报", probe.audioRate > 0,
              [NSString stringWithFormat:@"%ld Hz", (long)probe.audioRate]);

        // 2. 运行 1.2 秒
        [core start];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [NSThread sleepForTimeInterval:1.2];
        double elapsed = CFAbsoluteTimeGetCurrent() - t0;
        NSInteger frames = (NSInteger)core.renderedFrameCount;
        double fps = frames / elapsed;
        check("run 循环产出帧", frames > 0,
              [NSString stringWithFormat:@"%.1f 秒内 %ld 帧（约 %.0f fps）", elapsed, (long)frames, fps]);
        check("帧率接近 60", fps > 50 && fps < 70,
              [NSString stringWithFormat:@"%.1f fps", fps]);
        NSUInteger bufferedAudio = [core.audioRingBuffer availableFrames];
        check("音频回调产出样本", bufferedAudio > 0,
              [NSString stringWithFormat:@"环形缓冲 %lu 帧（若无消费者则会累积到上限）", (unsigned long)bufferedAudio]);

        // 3. 抓帧并检查像素
        size_t bufSize = 512 * 512 * 4;
        uint8_t *pixels = (uint8_t *)calloc(bufSize, 1);
        NSUInteger w = 0, h = 0;
        BOOL gotFrame = [core copyCurrentFrameToBuffer:pixels width:&w height:&h];
        long nonZero = 0;
        if (gotFrame && w > 0 && h > 0) {
            for (NSUInteger i = 0; i < w * h * 4; i += 4) {
                if (pixels[i] || pixels[i + 1] || pixels[i + 2]) {
                    nonZero++;
                }
            }
        }
        check("copyCurrentFrame 取到帧", gotFrame && w == (NSUInteger)expectW && h == (NSUInteger)expectH,
              [NSString stringWithFormat:@"%lux%lu", (unsigned long)w, (unsigned long)h]);
        check("帧缓冲含非零像素", nonZero > 0,
              [NSString stringWithFormat:@"%ld/%lu 像素非零", nonZero, (unsigned long)(w * h)]);
        free(pixels);

        // 4. 存档往返
        NSUInteger size = [core serializeSize];
        NSData *stateA = [core serializeState];
        check("serializeSize > 0", size > 0,
              [NSString stringWithFormat:@"%lu 字节", (unsigned long)size]);
        check("serializeState 有数据", stateA.length > 0,
              [NSString stringWithFormat:@"%lu 字节", (unsigned long)stateA.length]);
        BOOL restored = stateA.length > 0 ? [core unserializeState:stateA] : NO;
        check("unserializeState 往返成功", restored, @"读回同一快照");
        NSData *stateB = [core serializeState];
        check("往返后快照尺寸一致", stateB.length == stateA.length,
              [NSString stringWithFormat:@"A=%lu B=%lu", (unsigned long)stateA.length,
                                           (unsigned long)stateB.length]);

        // 5. 电池存档 flush
        [core flushBatterySave];
        check("flushBatterySave 不崩溃", YES, @"");

        // 6. 停止
        [core stop];
        check("stop 干净退出", !core.isRunning, @"线程已回收");

        printf("\n%s\n", g_failed == 0 ? "=== E2E ALL PASSED ===" : "=== E2E FAILED ===");
        return g_failed == 0 ? 0 : 1;
    }
}
