// RetroCore.mm — libretro 内核封装实现。
//
// 架构要点：
//  - core 以独立动态 framework 嵌入，运行时 dlopen + dlsym（三 core 符号互不冲突）
//  - retro_run() 跑在专用串行线程；所有其他 libretro API 经 _coreMutex 串行化
//  - 输入走「键位状态表」（原子位掩码），input_state 回调只读表
//  - 帧：video_refresh（core 线程）→ FramePipeline 双缓冲 → 主线程上传 Metal
//  - 音频：audio_sample_batch（core 线程）→ AudioRingBuffer → AVAudioSourceNode 拉取
#import "RetroCore.h"
#import "FramePipeline.h"
#import "AudioRingBuffer.h"
#import "libretro.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static uint64_t mr_monotonic_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

// MARK: - 函数指针类型

typedef bool (*retro_environment_t)(unsigned cmd, void *data);
typedef void (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);

typedef void (*retro_set_environment_fn)(retro_environment_t);
typedef void (*retro_set_video_refresh_fn)(retro_video_refresh_t);
typedef void (*retro_set_audio_sample_fn)(retro_audio_sample_t);
typedef void (*retro_set_audio_sample_batch_fn)(retro_audio_sample_batch_t);
typedef void (*retro_set_input_poll_fn)(retro_input_poll_t);
typedef void (*retro_set_input_state_fn)(retro_input_state_t);
typedef void (*retro_init_fn)(void);
typedef void (*retro_deinit_fn)(void);
typedef unsigned (*retro_api_version_fn)(void);
typedef void (*retro_get_system_info_fn)(struct retro_system_info *info);
typedef void (*retro_get_system_av_info_fn)(struct retro_system_av_info *info);
typedef void (*retro_set_controller_port_device_fn)(unsigned port, unsigned device);
typedef void (*retro_reset_fn)(void);
typedef void (*retro_run_fn)(void);
typedef size_t (*retro_serialize_size_fn)(void);
typedef bool (*retro_serialize_fn)(void *data, size_t size);
typedef bool (*retro_unserialize_fn)(const void *data, size_t size);
typedef void (*retro_cheat_reset_fn)(void);
typedef void (*retro_cheat_set_fn)(unsigned index, bool enabled, const char *code);
typedef bool (*retro_load_game_fn)(const struct retro_game_info *game);
typedef void (*retro_unload_game_fn)(void);
typedef unsigned (*retro_get_region_fn)(void);
typedef void *(*retro_get_memory_data_fn)(unsigned id);
typedef size_t (*retro_get_memory_size_fn)(unsigned id);

static retro_set_environment_fn p_retro_set_environment;
static retro_set_video_refresh_fn p_retro_set_video_refresh;
static retro_set_audio_sample_fn p_retro_set_audio_sample;
static retro_set_audio_sample_batch_fn p_retro_set_audio_sample_batch;
static retro_set_input_poll_fn p_retro_set_input_poll;
static retro_set_input_state_fn p_retro_set_input_state;
static retro_init_fn p_retro_init;
static retro_deinit_fn p_retro_deinit;
static retro_api_version_fn p_retro_api_version;
static retro_get_system_info_fn p_retro_get_system_info;
static retro_get_system_av_info_fn p_retro_get_system_av_info;
static retro_set_controller_port_device_fn p_retro_set_controller_port_device;
static retro_reset_fn p_retro_reset;
static retro_run_fn p_retro_run;
static retro_serialize_size_fn p_retro_serialize_size;
static retro_serialize_fn p_retro_serialize;
static retro_unserialize_fn p_retro_unserialize;
static retro_cheat_reset_fn p_retro_cheat_reset;
static retro_cheat_set_fn p_retro_cheat_set;
static retro_load_game_fn p_retro_load_game;
static retro_unload_game_fn p_retro_unload_game;
static retro_get_region_fn p_retro_get_region;
static retro_get_memory_data_fn p_retro_get_memory_data;
static retro_get_memory_size_fn p_retro_get_memory_size;

// 回调前向声明（定义在文件末尾，见「libretro 回调」一节）
static bool mr_environment_callback(unsigned cmd, void *data);
static void mr_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch);
static void mr_audio_sample(int16_t left, int16_t right);
static size_t mr_audio_sample_batch(const int16_t *data, size_t frames);
static void mr_input_poll(void);
static int16_t mr_input_state(unsigned port, unsigned device, unsigned index, unsigned id);
static void *mr_run_loop(void *ctx);

// 环境回调所属实例（libretro 无 user data；同时只运行一个实例）
static RetroCore *s_environmentOwner = nil;

/// core 日志转发：过滤 DEBUG（SameBoy 等会刷大量 HW 寄存器调试输出），
/// 只把 INFO/ERROR 送入 NSLog + 内存环形缓冲（供上层判断「缺少 BIOS」这类静默失败）。
static NSMutableArray<NSString *> *gCoreLogLines = nil;
static NSLock *gCoreLogLock = nil;
static const NSUInteger kCoreLogCapacity = 200;

static void mr_append_core_log(NSString *message) {
    if (gCoreLogLock == nil) {
        gCoreLogLock = [NSLock new];
        gCoreLogLines = [NSMutableArray arrayWithCapacity:kCoreLogCapacity];
    }
    [gCoreLogLock lock];
    [gCoreLogLines addObject:message];
    if (gCoreLogLines.count > kCoreLogCapacity) {
        [gCoreLogLines removeObjectsInRange:NSMakeRange(0, gCoreLogLines.count - kCoreLogCapacity)];
    }
    [gCoreLogLock unlock];
}

static void mr_log_callback(enum retro_log_level level, const char *fmt, ...) {
    if (level == RETRO_LOG_DEBUG) {
        return;
    }
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    NSString *message = [NSString stringWithUTF8String:buffer];
    if (message.length == 0) {
        return;
    }
    mr_append_core_log(message);
    NSLog(@"[core:%@] %@", level == RETRO_LOG_ERROR ? @"ERROR" : @"INFO", message);
}

// MARK: - RetroCore

@interface RetroCore () {
    pthread_mutex_t _coreMutex;      // 串行化所有 libretro API（run 循环也持锁）
    pthread_mutex_t _runMutex;       // 保护 running/paused 标志
    pthread_cond_t _runCond;
    pthread_t _runThread;
    BOOL _threadStarted;

    _Atomic bool _running;

    NSString *_saveDirectory;
    NSString *_systemDirectory;
    NSString *_romBaseName;

    _Atomic uint16_t _buttonState[4]; // 每 port 一个位掩码
    _Atomic bool _fastForward;
    _Atomic NSInteger _fastForwardMultiplier;

    NSMutableDictionary<NSString *, NSString *> *_coreVariables;
    double _targetFPS;
}

@property (atomic, assign) BOOL fastForwardActive;
- (BOOL)handleEnvironmentCommand:(unsigned)cmd data:(void *)data;
- (void)handleVideoRefresh:(const void *)data width:(unsigned)width height:(unsigned)height pitch:(size_t)pitch;
- (int16_t)inputStateForPort:(unsigned)port device:(unsigned)device index:(unsigned)index id:(unsigned)buttonID;
- (void)runLoopBody;
- (void)loadCoreSymbolsWithError:(NSError **)error;
- (BOOL)restoreBatterySave;
@end

@implementation RetroCore {
    void *_coreHandle;
    BOOL _coreInitialized;
    BOOL _paused;
    BOOL _shutdownRequested;
    NSUInteger _serializeSize;
    NSString *_lastCoreMessage;
    FramePipeline *_framePipeline;
}

+ (NSArray<NSString *> *)recentCoreLogLines {
    if (gCoreLogLock == nil) { return @[]; }
    [gCoreLogLock lock];
    NSArray *copy = [gCoreLogLines copy];
    [gCoreLogLock unlock];
    return copy;
}

+ (void)clearCoreLogLines {
    if (gCoreLogLock == nil) { return; }
    [gCoreLogLock lock];
    [gCoreLogLines removeAllObjects];
    [gCoreLogLock unlock];
}


- (BOOL)isRunning {
    return atomic_load(&_running);
}

#pragma mark - 生命周期

- (instancetype)initWithCoreNamed:(NSString *)coreName {
    self = [super init];
    if (self) {
        _coreName = [coreName copy];
        _audioRingBuffer = [[AudioRingBuffer alloc] initWithCapacityFrames:8192];
        _coreVariables = [NSMutableDictionary dictionary];
        _videoBaseSize = CGSizeZero;
        _videoAspectRatio = 0.0;
        _pixelFormat = MRPixelFormatXRGB8888;
        _audioSampleRate = 44100;
        _targetFPS = 60.0;
        pthread_mutex_init(&_coreMutex, NULL);
        pthread_mutex_init(&_runMutex, NULL);
        pthread_cond_init(&_runCond, NULL);
        atomic_store(&_fastForward, false);
        atomic_store(&_fastForwardMultiplier, 1);
        for (int i = 0; i < 4; i++) {
            atomic_store(&_buttonState[i], 0);
        }
    }
    return self;
}

- (void)dealloc {
    [self stop];
    pthread_mutex_destroy(&_coreMutex);
    pthread_mutex_destroy(&_runMutex);
    pthread_cond_destroy(&_runCond);
}

#pragma mark - 动态库加载

- (void *)loadCoreSymbol:(const char *)name {
    return dlsym(_coreHandle, name);
}

- (void)loadCoreSymbolsWithError:(NSError **)error {
#define RESOLVE(fn)                                                     \
    p_##fn = (fn##_fn)[self loadCoreSymbol:#fn];                        \
    if (p_##fn == NULL) {                                               \
        if (error) {                                                    \
            *error = [NSError errorWithDomain:@"RetroCore"              \
                                         code:1001                      \
                                     userInfo:@{NSLocalizedDescriptionKey : \
                                        [NSString stringWithFormat:@"缺少符号: %s", #fn]}]; \
        }                                                               \
        return;                                                         \
    }

    RESOLVE(retro_set_environment)
    RESOLVE(retro_set_video_refresh)
    RESOLVE(retro_set_audio_sample)
    RESOLVE(retro_set_audio_sample_batch)
    RESOLVE(retro_set_input_poll)
    RESOLVE(retro_set_input_state)
    RESOLVE(retro_init)
    RESOLVE(retro_deinit)
    RESOLVE(retro_api_version)
    RESOLVE(retro_get_system_info)
    RESOLVE(retro_get_system_av_info)
    RESOLVE(retro_set_controller_port_device)
    RESOLVE(retro_reset)
    RESOLVE(retro_run)
    RESOLVE(retro_serialize_size)
    RESOLVE(retro_serialize)
    RESOLVE(retro_unserialize)
    RESOLVE(retro_cheat_reset)
    RESOLVE(retro_cheat_set)
    RESOLVE(retro_load_game)
    RESOLVE(retro_unload_game)
    RESOLVE(retro_get_region)
    RESOLVE(retro_get_memory_data)
    RESOLVE(retro_get_memory_size)
#undef RESOLVE
}

- (NSString *)coreFrameworkBinaryPath:(NSError **)error {
    NSString *frameworkName = [NSString stringWithFormat:@"%@_core.framework", self.coreName];
    NSString *binaryName = [NSString stringWithFormat:@"%@_core", self.coreName];
    // 候选根目录：iOS 的 privateFrameworks（<App>.app/Frameworks）、bundle 下 Frameworks
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *privateFW = NSBundle.mainBundle.privateFrameworksPath;
    if (privateFW.length > 0) {
        [roots addObject:privateFW];
    }
    [roots addObject:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"]];
    for (NSString *root in roots) {
        // <root>/<name>_core.framework/<name>_core
        NSString *binary = [[root stringByAppendingPathComponent:frameworkName]
                            stringByAppendingPathComponent:binaryName];
        // 注意：不能用 isExecutableFileAtPath —— 模拟器安装（simctl install）会剥掉
        // dylib 的可执行位（-rwxr-xr-x → -rw-r--r--），导致误判「找不到 framework」。
        // dlopen 只需要文件存在且为有效 Mach-O，与 Unix 可执行位无关。
        if ([[NSFileManager defaultManager] fileExistsAtPath:binary]) {
            return binary;
        }
    }
    if (error) {
        *error = [NSError errorWithDomain:@"RetroCore"
                                    code:1000
                                userInfo:@{NSLocalizedDescriptionKey :
                                    [NSString stringWithFormat:@"找不到 core framework: %@（已查找 %@）",
                                     frameworkName, [roots componentsJoinedByString:@", "]]}];
    }
    return nil;
}

- (BOOL)loadCoreWithError:(NSError **)error {
    if (_coreHandle != NULL) {
        return YES;
    }
    NSString *path = [self coreFrameworkBinaryPath:error];
    if (path == nil) {
        return NO;
    }
    void *handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"RetroCore"
                                        code:1002
                                    userInfo:@{NSLocalizedDescriptionKey :
                                        [NSString stringWithFormat:@"dlopen 失败: %s", dlerror()]}];
        }
        return NO;
    }
    _coreHandle = handle;
    [self loadCoreSymbolsWithError:error];
    return error == nil || *error == nil;
}

#pragma mark - ROM 加载

- (BOOL)loadROMAtPath:(NSString *)romPath error:(NSError **)error {
    pthread_mutex_lock(&_coreMutex);
    BOOL ok = NO;
    struct retro_game_info info;
    struct retro_system_info sysInfo;
    NSData *romData = nil;
    if (![self loadCoreWithError:error]) {
        goto unlock;
    }
    if (p_retro_api_version() != RETRO_API_VERSION) {
        if (error) {
            *error = [NSError errorWithDomain:@"RetroCore"
                                        code:1003
                                    userInfo:@{NSLocalizedDescriptionKey : @"core API 版本不匹配"}];
        }
        goto unlock;
    }
    if (!_coreInitialized) {
        s_environmentOwner = self;
        p_retro_set_environment(mr_environment_callback);
        p_retro_set_video_refresh(mr_video_refresh);
        p_retro_set_audio_sample(mr_audio_sample);
        p_retro_set_audio_sample_batch(mr_audio_sample_batch);
        p_retro_set_input_poll(mr_input_poll);
        p_retro_set_input_state(mr_input_state);
        p_retro_init();
        _coreInitialized = YES;
    }

    memset(&info, 0, sizeof(info));
    info.path = romPath.fileSystemRepresentation;

    // 关键：按 core 的 need_fullpath 决定传路径还是传数据。
    //   fceumm  = true  → 只给 path（core 自行 fopen）
    //   SameBoy/mGBA = false → 必须把 ROM 读进内存并通过 info.data 传入
    memset(&sysInfo, 0, sizeof(sysInfo));
    p_retro_get_system_info(&sysInfo);
    if (!sysInfo.need_fullpath) {
        romData = [NSData dataWithContentsOfFile:romPath];
        if (romData.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"RetroCore"
                                            code:1005
                                        userInfo:@{NSLocalizedDescriptionKey :
                                            @"无法读取 ROM 数据（core 要求内存加载）"}];
            }
            goto unlock;
        }
        info.data = romData.bytes;
        info.size = romData.length;
    }

    if (!p_retro_load_game(&info)) {
        if (error) {
            NSString *msg = [NSString stringWithFormat:
                @"retro_load_game 失败（core=%@，ROM 可能损坏或格式不被支持）", self.coreName];
            *error = [NSError errorWithDomain:@"RetroCore"
                                        code:1004
                                    userInfo:@{NSLocalizedDescriptionKey : msg}];
        }
        goto unlock;
    }

    _romBaseName = romPath.lastPathComponent.stringByDeletingPathExtension;

    struct retro_system_av_info avInfo;
    memset(&avInfo, 0, sizeof(avInfo));
    p_retro_get_system_av_info(&avInfo);
    _videoBaseSize = CGSizeMake(avInfo.geometry.base_width, avInfo.geometry.base_height);
    _videoAspectRatio = avInfo.geometry.aspect_ratio;
    _targetFPS = avInfo.timing.fps > 1.0 ? avInfo.timing.fps : 60.0;
    if (avInfo.timing.sample_rate > 0) {
        _audioSampleRate = (NSUInteger)avInfo.timing.sample_rate;
    }
    _serializeSize = p_retro_serialize_size();
    _shutdownRequested = NO;
    // 1024×1024 上限：街机 core 常用 640×480 / 512×384（PGM、CPS3 等），
    // 旧的 512×512 会把超大帧整帧丢弃，表现为「加载成功但永远黑屏」。
    // 双缓冲内存 2×1024×1024×4 = 8MB，对 iPhone/iPad 无压力。
    _framePipeline = [[FramePipeline alloc] initWithMaxWidth:1024 maxHeight:1024];

    [self.audioRingBuffer reset];
    [self.frameDelegate retroCore:self didChangeVideoGeometry:_videoBaseSize aspectRatio:_videoAspectRatio];
    if (self.audioDelegate && [self.audioDelegate respondsToSelector:@selector(retroCore:didChangeAudioSampleRate:)]) {
        [self.audioDelegate retroCore:self didChangeAudioSampleRate:_audioSampleRate];
    }
    [self restoreBatterySave];
    ok = YES;

unlock:
    pthread_mutex_unlock(&_coreMutex);
    return ok;
}

- (void)unloadROM {
    pthread_mutex_lock(&_coreMutex);
    if (_coreInitialized && p_retro_unload_game) {
        p_retro_unload_game();
    }
    pthread_mutex_unlock(&_coreMutex);
}

- (void)start {
    pthread_mutex_lock(&_runMutex);
    if (!_threadStarted) {
        _threadStarted = YES;
        atomic_store(&_running, true);
        pthread_create(&_runThread, NULL, mr_run_loop, (__bridge void *)self);
    }
    pthread_cond_signal(&_runCond);
    pthread_mutex_unlock(&_runMutex);
}

- (void)stop {
    pthread_mutex_lock(&_runMutex);
    BOOL started = _threadStarted;
    _threadStarted = NO;
    atomic_store(&_running, false);
    pthread_cond_broadcast(&_runCond);
    pthread_mutex_unlock(&_runMutex);
    if (started) {
        pthread_join(_runThread, NULL);
    }
}

- (void)pause {
    pthread_mutex_lock(&_runMutex);
    _paused = YES;
    pthread_mutex_unlock(&_runMutex);
}

- (void)resume {
    pthread_mutex_lock(&_runMutex);
    _paused = NO;
    pthread_cond_signal(&_runCond);
    pthread_mutex_unlock(&_runMutex);
}

- (void)reset {
    pthread_mutex_lock(&_coreMutex);
    if (_coreInitialized) {
        p_retro_reset();
    }
    pthread_mutex_unlock(&_coreMutex);
}

#pragma mark - run 循环

static void *mr_run_loop(void *ctx) {
    RetroCore *self = (__bridge RetroCore *)ctx;
    pthread_setname_np("com.miniretro.runloop");
    [self runLoopBody];
    return NULL;
}

- (void)runLoopBody {
    // 帧限速用 POSIX 单调时钟（绕开 mach_timebase_info 字段名跨 SDK 差异：den/denom）
    uint64_t frameInterval = (uint64_t)(1e9 / _targetFPS);
    if (frameInterval == 0) {
        frameInterval = (uint64_t)(1e9 / 60.0);
    }
    uint64_t nextFrame = mr_monotonic_ns();
    while (atomic_load(&_running)) {
        pthread_mutex_lock(&_runMutex);
        while (_paused && atomic_load(&_running)) {
            pthread_cond_wait(&_runCond, &_runMutex);
        }
        BOOL stillRunning = atomic_load(&_running);
        pthread_mutex_unlock(&_runMutex);
        if (!stillRunning) {
            break;
        }

        pthread_mutex_lock(&_coreMutex);
        BOOL fast = atomic_load(&_fastForward);
        NSInteger multiplier = atomic_load(&_fastForwardMultiplier);
        NSInteger frames = fast ? MAX(1, multiplier) : 1;
        for (NSInteger i = 0; i < frames; i++) {
            p_retro_run();
        }
        pthread_mutex_unlock(&_coreMutex);

        // 无论是否快进都必须限速：每轮循环推进「一个显示帧」的时长，
        // 而本轮内部已跑了 frames 帧 → 实际速度恰好为 frames 倍。
        //
        // 旧实现快进时完全不休眠（if (!fast) 才 sleep），循环速度取决于 CPU，
        // 实测远超设定倍率（用户反馈「2×/4× 快太多」）。
        {
            uint64_t now = mr_monotonic_ns();
            nextFrame += frameInterval;
            if (nextFrame < now) {
                nextFrame = now; // 落后太多则丢弃积压，避免追赶式快进
            } else {
                struct timespec sleepTs;
                uint64_t remaining = nextFrame - now;
                sleepTs.tv_sec = (time_t)(remaining / 1000000000ull);
                sleepTs.tv_nsec = (long)(remaining % 1000000000ull);
                nanosleep(&sleepTs, NULL);
            }
        }
    }
}

#pragma mark - 输入状态表

- (void)setButton:(NSUInteger)buttonID pressed:(BOOL)pressed forPort:(NSUInteger)port {
    if (port >= 4 || buttonID > 15) {
        return;
    }
    uint16_t mask = (uint16_t)(1u << buttonID);
    uint16_t current = atomic_load_explicit(&_buttonState[port], memory_order_relaxed);
    uint16_t next = pressed ? (uint16_t)(current | mask) : (uint16_t)(current & ~mask);
    atomic_store_explicit(&_buttonState[port], next, memory_order_relaxed);
}

- (void)clearAllButtonsForPort:(NSUInteger)port {
    if (port < 4) {
        atomic_store_explicit(&_buttonState[port], 0, memory_order_relaxed);
    }
}

- (int16_t)inputStateForPort:(unsigned)port device:(unsigned)device index:(unsigned)index id:(unsigned)buttonID {
    if (device != RETRO_DEVICE_JOYPAD) {
        return 0; // 不支持 ANALOG / MOUSE / POINTER 等设备
    }
    if (index != 0) {
        return 0;
    }
    if (port >= 4 || buttonID > 15) {
        return 0;
    }
    uint16_t state = atomic_load_explicit(&_buttonState[port], memory_order_relaxed);
    return (state & (1u << buttonID)) ? 1 : 0;
}

#pragma mark - 帧

- (void)handleVideoRefresh:(const void *)data width:(unsigned)width height:(unsigned)height pitch:(size_t)pitch {
    if (data == NULL) {
        return; // 跳过帧
    }
    [_framePipeline pushFrame:data width:width height:height pitch:pitch format:self.pixelFormat];
}

- (uint64_t)renderedFrameCount {
    return _framePipeline ? _framePipeline.pushedFrameCount : 0;
}

- (BOOL)copyCurrentFrameToBuffer:(uint8_t *)buffer width:(out NSUInteger *)width height:(out NSUInteger *)height {
    if (_framePipeline == nil) {
        return NO;
    }
    return [_framePipeline copyLatestFrameToBuffer:buffer width:width height:height];
}

#pragma mark - 环境回调

- (BOOL)handleEnvironmentCommand:(unsigned)cmd data:(void *)data {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY: {
            if (data) {
                *(const char **)data = _systemDirectory ? _systemDirectory.fileSystemRepresentation : "";
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            if (data) {
                *(const char **)data = _saveDirectory ? _saveDirectory.fileSystemRepresentation : "";
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            unsigned format = *(const unsigned *)data;
            if (format <= 2) {
                _pixelFormat = (MRPixelFormat)format;
                if (self.frameDelegate && [self.frameDelegate respondsToSelector:@selector(retroCore:didChangePixelFormat:)]) {
                    [self.frameDelegate retroCore:self didChangePixelFormat:_pixelFormat];
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            struct retro_variable *var = (struct retro_variable *)data;
            NSString *key = [NSString stringWithUTF8String:var->key];
            NSString *value = _coreVariables[key];
            if (value == nil || value.length == 0) {
                return false; // 未设置 → core 用默认值
            }
            var->value = strdup(value.UTF8String);
            return true;
        }
        case RETRO_ENVIRONMENT_SET_VARIABLES: {
            const struct retro_variable *vars = (const struct retro_variable *)data;
            if (vars) {
                for (const struct retro_variable *v = vars; v->key != NULL; v++) {
                    NSString *key = [NSString stringWithUTF8String:v->key];
                    if (_coreVariables[key] == nil) {
                        _coreVariables[key] = @""; // 占位，用户设置经 updateVariable 覆盖
                    }
                }
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
            if (data) {
                *(bool *)data = false;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_GEOMETRY: {
            struct retro_game_geometry *geo = (struct retro_game_geometry *)data;
            if (geo && (geo->base_width != (unsigned)_videoBaseSize.width ||
                        geo->base_height != (unsigned)_videoBaseSize.height)) {
                _videoBaseSize = CGSizeMake(geo->base_width, geo->base_height);
                _videoAspectRatio = geo->aspect_ratio;
                [self.frameDelegate retroCore:self didChangeVideoGeometry:_videoBaseSize aspectRatio:_videoAspectRatio];
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_TARGET_SAMPLE_RATE: {
            // 关键：SameBoy 等 core 通过该回调决定内部重采样率。
            // 不实现 → core 回退到 2MHz 输出，导致 AVAudioEngine 无法建格式、无声。
            if (data) {
                *(unsigned *)data = 48000;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            if (data) {
                struct retro_log_callback *cb = (struct retro_log_callback *)data;
                cb->log = mr_log_callback;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SET_MESSAGE: {
            const struct retro_message *msg = (const struct retro_message *)data;
            if (msg && msg->msg) {
                _lastCoreMessage = [NSString stringWithUTF8String:msg->msg];
            }
            return true;
        }
        case RETRO_ENVIRONMENT_SHUTDOWN:
            _shutdownRequested = YES;
            return true;
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
            return true;
        case RETRO_ENVIRONMENT_GET_CURRENT_SOFTWARE_FRAMEBUFFER:
            return false; // 不使用 software framebuffer 通道
        case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
            return false; // RetroArch 专用，本前端不用
        default:
            return false;
    }
}

#pragma mark - 存档

- (NSUInteger)serializeSize {
    return _serializeSize;
}

- (NSData *)serializeState {
    pthread_mutex_lock(&_coreMutex);
    NSData *result = nil;
    size_t size = p_retro_serialize_size ? p_retro_serialize_size() : 0;
    if (size > 0) {
        void *buffer = malloc(size);
        if (buffer && p_retro_serialize(buffer, size)) {
            result = [NSData dataWithBytes:buffer length:size];
        }
        free(buffer);
    }
    pthread_mutex_unlock(&_coreMutex);
    return result;
}

- (BOOL)unserializeState:(NSData *)data {
    if (data.length == 0) {
        return NO;
    }
    pthread_mutex_lock(&_coreMutex);
    BOOL ok = p_retro_unserialize(data.bytes, data.length);
    pthread_mutex_unlock(&_coreMutex);
    return ok;
}

- (void)setSaveDirectory:(NSString *)path {
    pthread_mutex_lock(&_coreMutex);
    _saveDirectory = [path copy];
    pthread_mutex_unlock(&_coreMutex);
}

- (void)setSystemDirectory:(NSString *)path {
    pthread_mutex_lock(&_coreMutex);
    _systemDirectory = [path copy];
    pthread_mutex_unlock(&_coreMutex);
}

- (NSString *)batterySavePath {
    if (_saveDirectory.length == 0 || _romBaseName.length == 0) {
        return nil;
    }
    return [_saveDirectory stringByAppendingPathComponent:[_romBaseName stringByAppendingString:@".sav"]];
}

- (void)flushBatterySave {
    pthread_mutex_lock(&_coreMutex);
    if (_coreInitialized) {
        void *sram = p_retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
        size_t size = p_retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
        NSString *savPath = [self batterySavePath];
        if (sram && size > 0 && savPath) {
            NSData *data = [NSData dataWithBytes:sram length:size];
            [data writeToFile:savPath atomically:YES];
        }
    }
    pthread_mutex_unlock(&_coreMutex);
}

- (BOOL)restoreBatterySave {
    if (!_coreInitialized) {
        return NO;
    }
    NSString *savPath = [self batterySavePath];
    if (savPath == nil) {
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfFile:savPath];
    if (data.length == 0) {
        return NO;
    }
    void *sram = p_retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    size_t size = p_retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (sram && data.length <= size) {
        memcpy(sram, data.bytes, data.length);
        return YES;
    }
    return NO;
}

#pragma mark - 金手指

- (void)resetCheats {
    pthread_mutex_lock(&_coreMutex);
    if (_coreInitialized) {
        p_retro_cheat_reset();
    }
    pthread_mutex_unlock(&_coreMutex);
}

- (void)setCheatAtIndex:(NSUInteger)index enabled:(BOOL)enabled withCode:(NSString *)code {
    pthread_mutex_lock(&_coreMutex);
    if (_coreInitialized) {
        p_retro_cheat_set((unsigned)index, enabled, code.UTF8String ?: "");
    }
    pthread_mutex_unlock(&_coreMutex);
}

#pragma mark - 变量与快进

- (void)updateVariable:(NSString *)key value:(NSString *)value {
    pthread_mutex_lock(&_coreMutex);
    _coreVariables[key] = value ?: @"";
    pthread_mutex_unlock(&_coreMutex);
}

- (void)setFastForwardEnabled:(BOOL)enabled multiplier:(NSInteger)multiplier {
    atomic_store(&_fastForward, enabled);
    atomic_store(&_fastForwardMultiplier, multiplier > 0 ? multiplier : 2);
    self.fastForwardActive = enabled;
}

- (NSInteger)fastForwardMultiplierValue {
    return atomic_load(&_fastForwardMultiplier);
}

@end

// MARK: - libretro 回调（C 函数指针，需在类扩展声明之后定义）

static bool mr_environment_callback(unsigned cmd, void *data) {
    RetroCore *self = s_environmentOwner;
    if (self == nil) {
        return false;
    }
    return [self handleEnvironmentCommand:cmd data:data];
}

static void mr_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    RetroCore *self = s_environmentOwner;
    if (self == nil) {
        return;
    }
    [self handleVideoRefresh:data width:width height:height pitch:pitch];
}

static void mr_audio_sample(int16_t left, int16_t right) {
    RetroCore *self = s_environmentOwner;
    if (self == nil) {
        return;
    }
    int16_t pair[2] = {left, right};
    [self.audioRingBuffer writeSamples:pair frameCount:1];
}

/// 快进时的音频抽取缓冲（单实例预分配，避免回调内 malloc）
static int16_t s_audioFastForwardScratch[8192 * 2];

static size_t mr_audio_sample_batch(const int16_t *data, size_t frames) {
    RetroCore *self = s_environmentOwner;
    if (self == nil || data == NULL || frames == 0) {
        return frames;
    }

    NSInteger decimation = self.fastForwardActive ? self.fastForwardMultiplierValue : 1;
    if (decimation <= 1) {
        [self.audioRingBuffer writeSamples:data frameCount:frames];
        return frames;
    }

    // 快进：每 decimation 帧取 1 帧写入。
    // 输出速率因此与正常播放一致（不再让环形缓冲被 8 倍数据灌爆），
    // 内容仍按倍率跳跃 → 音调升高，但"快进时完全没有声音"的问题消失。
    size_t step = (size_t)decimation;
    size_t outCount = frames / step;
    if (outCount > 8192) {
        outCount = 8192;
    }
    for (size_t i = 0; i < outCount; i++) {
        size_t src = i * step * 2;
        s_audioFastForwardScratch[i * 2] = data[src];
        s_audioFastForwardScratch[i * 2 + 1] = data[src + 1];
    }
    if (outCount > 0) {
        [self.audioRingBuffer writeSamples:s_audioFastForwardScratch frameCount:outCount];
    }
    return frames;
}

static void mr_input_poll(void) {
    // GameController 事件由系统分发直接写状态表，此处无需轮询。
}

static int16_t mr_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    RetroCore *self = s_environmentOwner;
    if (self == nil) {
        return 0;
    }
    return [self inputStateForPort:port device:device index:index id:id];
}
