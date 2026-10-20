// CoreRegistry.c — 实现见头文件注释。
#include "CoreRegistry.h"

#include <string.h>
#include <strings.h>

static MRCoreMatch make_match(const char *core, const char *system, bool by_magic) {
    MRCoreMatch m;
    m.core_name = core;
    m.system_id = system;
    m.by_magic = by_magic;
    return m;
}

static MRCoreMatch no_match(void) {
    return make_match(NULL, NULL, false);
}

/// iNES / NES 2.0 头：'N' 'E' 'S' 0x1A
static bool is_nes_magic(const uint8_t *d, size_t n) {
    return n >= 16 && d[0] == 'N' && d[1] == 'E' && d[2] == 'S' && d[3] == 0x1A;
}

/// Famicom Disk System 镜像：'F' 'D' 'S' 0x1A
static bool is_fds_magic(const uint8_t *d, size_t n) {
    return n >= 16 && d[0] == 'F' && d[1] == 'D' && d[2] == 'S' && d[3] == 0x1A;
}

/// UNIF：早期汉化/外星科技等非 iNES 封装，文件头为 ASCII "UNIF"。
/// fceumm 的 valid_extensions 含 unf|unif，且能自行解析 UNIF 容器。
static bool is_unif_magic(const uint8_t *d, size_t n) {
    return n >= 32 && d[0] == 'U' && d[1] == 'N' && d[2] == 'I' && d[3] == 'F';
}

/// GBA：0xB2 固定值单元 0x96；辅以 0xA0..0xAB（任天堂 logo 区）非零校验。
static bool is_gba_magic(const uint8_t *d, size_t n) {
    if (n < 0xC0 || d[0xB2] != 0x96) {
        return false;
    }
    for (size_t i = 0xA0; i <= 0xAB; i++) {
        if (d[i] != 0x00) {
            return true;
        }
    }
    return false;
}

/// GB/GBC：0x104..0x107 任天堂 logo 特征字节（CE ED 66 66 …）+ 0x143 CGB 标志合法值。
static bool is_gb_magic(const uint8_t *d, size_t n) {
    if (n < 0x148) {
        return false;
    }
    if (d[0x104] != 0xCE || d[0x105] != 0xED || d[0x106] != 0x66 || d[0x107] != 0x66) {
        return false;
    }
    uint8_t cgb = d[0x143];
    return cgb == 0x00 || cgb == 0x80 || cgb == 0xC0;
}

static const char *gb_system_for_header(const uint8_t *d) {
    uint8_t cgb = d[0x143];
    return (cgb == 0x80 || cgb == 0xC0) ? "gbc" : "gb";
}

MRCoreMatch mr_core_for_rom(const uint8_t *data, size_t size) {
    if (data == NULL || size == 0) {
        return no_match();
    }
    if (is_nes_magic(data, size)) {
        return make_match("fceumm", "nes", true);
    }
    if (is_fds_magic(data, size)) {
        return make_match("fceumm", "fds", true);
    }
    if (is_unif_magic(data, size)) {
        return make_match("fceumm", "unf", true);
    }
    if (is_gba_magic(data, size)) {
        return make_match("mgba", "gba", true);
    }
    if (is_gb_magic(data, size)) {
        return make_match("sameboy", gb_system_for_header(data), true);
    }
    return no_match();
}

MRCoreMatch mr_core_for_extension(const char *ext) {
    if (ext == NULL || *ext == '\0') {
        return no_match();
    }
    if (strcasecmp(ext, "nes") == 0 || strcasecmp(ext, "fds") == 0 ||
        strcasecmp(ext, "unf") == 0 || strcasecmp(ext, "unif") == 0) {
        const char *system = strcasecmp(ext, "fds") == 0 ? "fds"
                           : (strcasecmp(ext, "unf") == 0 || strcasecmp(ext, "unif") == 0) ? "unf"
                           : "nes";
        return make_match("fceumm", system, false);
    }
    if (strcasecmp(ext, "gb") == 0) {
        return make_match("sameboy", "gb", false);
    }
    if (strcasecmp(ext, "gbc") == 0) {
        return make_match("sameboy", "gbc", false);
    }
    if (strcasecmp(ext, "gba") == 0) {
        return make_match("mgba", "gba", false);
    }
    return no_match();
}

const char *mr_system_display_name(const char *system_id) {
    if (system_id == NULL) {
        return "未知";
    }
    if (strcmp(system_id, "gba") == 0) {
        return "GBA";
    }
    if (strcmp(system_id, "gb") == 0) {
        return "GB";
    }
    if (strcmp(system_id, "gbc") == 0) {
        return "GBC";
    }
    if (strcmp(system_id, "nes") == 0) {
        return "FC/NES";
    }
    if (strcmp(system_id, "fds") == 0) {
        return "FDS";
    }
    return "未知";
}

const char *mr_core_framework_name(const char *core_name) {
    if (core_name == NULL) {
        return "";
    }
    if (strcmp(core_name, "mgba") == 0) {
        return "mgba_core";
    }
    if (strcmp(core_name, "sameboy") == 0) {
        return "sameboy_core";
    }
    if (strcmp(core_name, "fceumm") == 0) {
        return "fceumm_core";
    }
    return "";
}
