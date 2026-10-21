## 这个 PR 做了什么

<!-- 一两句话说明目的；关联 issue 请写 Fixes #123 -->

## 改动类型

- [ ] 缺陷修复
- [ ] 新功能
- [ ] 内核升级 / 构建调整
- [ ] 文档 / 注释
- [ ] 重构（无行为变化）

## 自测情况

请勾选你实际跑过的项（没跑就留空，不要虚勾）：

- [ ] `./Tools/run_romlib_test.sh` 通过（不需要设备）
- [ ] `./Tools/run_e2e.sh` 通过（需要 macOS）
- [ ] `./Tools/build.sh --skip-cores` 构建成功
- [ ] 模拟器/真机手工验证：<说明验证了哪些路径>

## 注意事项

- [ ] 若改动了默认按键布局：已递增 `ControlLayouts.currentVersion`，并同步 `LayoutStoreTests`
- [ ] 若新增/升级了内核：已更新 `docs/adr-log.md`、`.gitmodules` 头部说明与 `THIRD-PARTY-NOTICES.md`
- [ ] 若改动了 `relativePath` / 索引结构：已考虑旧 `index.json` 的兼容与自愈
- [ ] 未提交任何 ROM / BIOS / 构建产物（`dist/`、`build*/`、`Tools/vendor/`）
