// CoreRegistry.h — ROM 识别与 core 分派（M4/M5 双保险：魔数 + 扩展名）
// 规则：魔数优先；魔数不可用时回退扩展名；都无法识别返回 core_name == NULL。
#ifndef MiniRetroCoreRegistry_h
#define MiniRetroCoreRegistry_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *core_name;   ///< "mgba" / "sameboy" / "fceumm"；NULL 表示无法识别
    const char *system_id;   ///< "gba" / "gb" / "gbc" / "nes" / "fds"；与 core_name 对应
    bool by_magic;           ///< true = 文件头魔数识别，false = 仅扩展名兜底
} MRCoreMatch;

/// 依据 ROM 内容识别（至少需要 16 字节头）。文件过小时退化为扩展名判断。
MRCoreMatch mr_core_for_rom(const uint8_t *data, size_t size);

/// 依据扩展名识别（不带前导点，大小写不敏感，如 "gba"）。
MRCoreMatch mr_core_for_extension(const char *ext);

/// 系统 ID 的中文展示名（静态字符串）。
const char *mr_system_display_name(const char *system_id);

/// 该 core 对应的 framework 嵌入名（如 "mgba" -> "mgba_core"）。
const char *mr_core_framework_name(const char *core_name);

#ifdef __cplusplus
}
#endif

#endif /* MiniRetroCoreRegistry_h */
