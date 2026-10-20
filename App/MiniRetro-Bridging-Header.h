// MiniRetro-Bridging-Header.h — Swift ↔ C/ObjC 桥接
// 约束：只有 CoreBridge 暴露给 App 层（libretro.h 不直接进入 Swift）
#import "RetroCore.h"
#import "CoreRegistry.h"
#import "AudioRingBuffer.h"
#import "FramePipeline.h"
