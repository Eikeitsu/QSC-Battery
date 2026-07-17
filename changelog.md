## 2026.07.17

- 修复在线更新：`versionCode` 改为 `yyyyMMdd * 100 + 修订号`（如 `2026071701`）
- 发版规范：首发 `2026.07.17`；同日再发 `2026.07.17.2`
- WebUI：悬浮分页、莫奈开关、卡片紧凑、顶栏固定等

## 20260716

- 仓库更名为 QSC-Battery，模块 id 更名为 `QSC_Battery`
- 安装时若检测到旧版 `QuantitativeStopCharging_switch`，自动卸载旧版（不再迁移配置）
- WebUI：外观主题支持浅色 / 深色 / 跟随系统，同步状态栏 theme-color
- 模块：接入 Magisk / KernelSU 在线更新（updateJson）
