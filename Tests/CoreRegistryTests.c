// CoreRegistryTests.c — ROM 识别逻辑的独立可执行测试（macOS 上直接跑）
// 用法：clang -o /tmp/cr_test CoreRegistryTests.c ../CoreRegistry.c && /tmp/cr_test
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../CoreBridge/CoreRegistry.h"

static int g_failures = 0;

static void expect_core(const char *label, MRCoreMatch m, const char *core, const char *system) {
    int ok = 1;
    if (core == NULL) {
        ok = (m.core_name == NULL);
    } else {
        ok = (m.core_name != NULL && strcmp(m.core_name, core) == 0);
        if (ok && system != NULL) {
            ok = (m.system_id != NULL && strcmp(m.system_id, system) == 0);
        }
    }
    printf("%s %-42s core=%-8s system=%-4s magic=%d\n",
           ok ? "[PASS]" : "[FAIL]", label,
           m.core_name ? m.core_name : "(null)",
           m.system_id ? m.system_id : "(null)",
           m.by_magic);
    if (!ok) {
        g_failures++;
    }
}

int main(void) {
    unsigned char rom[512];
    memset(rom, 0, sizeof(rom));

    // 1. iNES 头
    rom[0] = 'N'; rom[1] = 'E'; rom[2] = 'S'; rom[3] = 0x1A;
    expect_core("iNES 魔数", mr_core_for_rom(rom, sizeof(rom)), "fceumm", "nes");

    // 2. FDS 头
    memset(rom, 0, sizeof(rom));
    rom[0] = 'F'; rom[1] = 'D'; rom[2] = 'S'; rom[3] = 0x1A;
    expect_core("FDS 魔数", mr_core_for_rom(rom, sizeof(rom)), "fceumm", "fds");

    // 3. GBA 头（0xB2 固定值 0x96 + logo 区非零）
    memset(rom, 0, sizeof(rom));
    rom[0xA0] = 0x24; rom[0xB2] = 0x96;
    expect_core("GBA 魔数", mr_core_for_rom(rom, sizeof(rom)), "mgba", "gba");

    // 4. GB 头（DMG：无 CGB 标志）
    memset(rom, 0, sizeof(rom));
    rom[0x104] = 0xCE; rom[0x105] = 0xED; rom[0x106] = 0x66; rom[0x107] = 0x66;
    rom[0x143] = 0x00;
    expect_core("GB 魔数（DMG）", mr_core_for_rom(rom, sizeof(rom)), "sameboy", "gb");

    // 5. GBC 头（CGB 兼容 0x80）
    rom[0x143] = 0x80;
    expect_core("GBC 魔数（兼容）", mr_core_for_rom(rom, sizeof(rom)), "sameboy", "gbc");

    // 6. GBC only（0xC0）
    rom[0x143] = 0xC0;
    expect_core("GBC 魔数（专属）", mr_core_for_rom(rom, sizeof(rom)), "sameboy", "gbc");

    // 7. 无法识别
    memset(rom, 0xAA, sizeof(rom));
    expect_core("随机数据（应无匹配）", mr_core_for_rom(rom, sizeof(rom)), NULL, NULL);

    // 8. 过小文件
    expect_core("空文件", mr_core_for_rom(rom, 0), NULL, NULL);

    // 9. 扩展名兜底（GBA ROM 头缺失时）
    expect_core("扩展名 .gba", mr_core_for_extension("gba"), "mgba", "gba");
    expect_core("扩展名 .GBC（大小写）", mr_core_for_extension("GBC"), "sameboy", "gbc");
    expect_core("扩展名 .nes", mr_core_for_extension("nes"), "fceumm", "nes");
    expect_core("扩展名 .txt（应无匹配）", mr_core_for_extension("txt"), NULL, NULL);

    // 10. 展示名 / framework 名
    printf("%s display(gba)=%s framework(mgba)=%s\n",
           strcmp(mr_system_display_name("gba"), "GBA") == 0 &&
                   strcmp(mr_core_framework_name("mgba"), "mgba_core") == 0
               ? "[PASS]" : "[FAIL]",
           mr_system_display_name("gba"), mr_core_framework_name("mgba"));

    printf("\n%s\n", g_failures == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    return g_failures == 0 ? 0 : 1;
}
