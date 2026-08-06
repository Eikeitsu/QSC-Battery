# 常见问题

## 刷入后没有效果？

1. 确认已重启
2. WebUI 中确认模块总开关已打开
3. 查看 `data/log.log` 是否有「未找到有效充电控制节点」
4. 红米 K90U（骁龙8至尊版）等 MCA 机型：安装/启动后查看 `data/device.profile` 应为 `mca=1` 且含 `handle_state` 路径；日志停充条目含 `MCA`。建议 `power_stop` 与 `power_start` 间隔至少 10
5. 若机型较新或停充无效，可在模块管理器打开 **Action**：音量上刷新权限，音量下进入诊断菜单（逐项上=执行 / 下=跳过），运行 `diagnose`；**插电后**建议再运行「停充开关实测」（`test_switch`），将有效节点写入 `device.profile` 的 `preferred_switch`。也可手动执行：

```bash
sh /data/adb/modules/QSC_Battery/bin/diagnose.sh
# 插电后：
sh /data/adb/modules/QSC_Battery/bin/test_switch.sh
```

报告在 `/sdcard/qsc_diagnose.txt`，可反馈给维护者适配。诊断菜单还可「重新探测设备配置」。含写入测试的 `testing` / `diag2` 仅在调试包 `QSC-Battery_v*-debug.zip` 中提供；正式包已含受控的 `test_switch`（测完必恢复充电）。

## WebUI 打不开？

确认安装时选择了 WebUI、模块管理器支持 WebUI（如 KernelSU / SukiSU 等），并检查模块目录下 `webroot/index.html` 是否存在。若曾选择不安装 WebUI，可重新刷入同版本并按音量上选择安装；配置处理仍会单独询问。

## 配置页没有「电流控制」？

安装时若选择不安装电流控制，相关脚本与 `current.json` 不会写入，WebUI 也会隐藏入口。重新刷入并选择安装即可；装入后还需打开「电流控制总开关」（默认关闭）。

## 更新后配置会恢复默认吗？

更新同 ID 的 `QSC_Battery` 时，安装脚本会询问是否保留原有配置：音量上保留 `config.conf`（以及已有的 `current.json`），音量下使用新版默认值；20 秒未选择时默认保留。旧版 `QSC定量停充` / `QSC定量停充_独立开关版` 会自动卸载且**不迁移**配置。

## 主题 / 莫奈 / 分页设置丢了？

这些选项保存在 WebView 的 `localStorage`，清应用数据或换管理器打开后可能重置，与配置文件无关。

## 停充后无法恢复充电？

检查恢复电量 / 恢复温度是否合理；多条件同时触发时需全部满足恢复条件。也可临时关闭模块总开关，或卸载模块后重启。

## 配置改完没反应？

停充写入 `config.conf`，电流控制写入 `current.json`，一般即时生效。若仍无效，看日志是否报错节点权限或机型未适配。

## 模块列表简介一直显示「启动中」？

简介由运行脚本动态更新。确认已重启且 `service.sh` 在循环；可看 `data/log.log` / `data/service_start.log`。正常后会变为充电中、未充电、已停充等状态。

## 检查更新没反应？

`versionCode` 必须是不超过 `2147483647` 的整数。若发布时把 `versionCode` 写成了 12 位日期时间（如 `202607171330`），Magisk / KernelSU 会解析失败，从而不提示更新。

本仓库发版会自动规范为：`version=2026.07.17`、`versionCode=2026071701`；同日第二版输入 `20260717.2` → `2026.07.17.2` / `2026071702`。也可在浏览器打开：

```text
https://raw.githubusercontent.com/Eikeitsu/QSC-Battery/main/update.json
```

确认其中 `versionCode` 为普通整数，且大于手机里已安装模块的 `versionCode`。

手机上也可在浏览器打开（国内更稳）：

```text
https://eikeitsu.github.io/QSC-Battery/update.json
```

若本机模块 `module.prop` 里没有 `updateJson=` 这一行，管理器**根本不会去检查更新**，只改 `versionCode` 没用。

## 与其它充电类模块冲突？

尽量不要同时安装多个控制充电开关或强行写入电流的模块，以免互相覆盖节点状态。仅用本模块停充时，可不安装电流控制，或保持其总开关关闭；若仍抢写电流，在 WebUI / `config.conf` 开启 **兼容模式**（`Compatibility_mode=1`），本模块将完全不写电流节点。电流控制一般不抢温控文件；若对方也写电流节点仍可能冲突。
