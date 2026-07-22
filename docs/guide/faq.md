# 常见问题

## 刷入后没有效果？

1. 确认已重启
2. WebUI 中确认模块总开关已打开
3. 查看 `data/log.log` 是否有「未找到有效充电控制节点」
4. 红米 K90U（骁龙8至尊版）应看到日志含 `MCA` / `handle_state`；建议 `power_stop` 与 `power_start` 间隔至少 10
5. 若机型较新，可执行诊断脚本：

```bash
sh /data/adb/modules/QSC_Battery/bin/diagnose.sh
```

报告在 `/sdcard/qsc_diagnose.txt`，可反馈给维护者适配。

## WebUI 打不开？

确认安装时选择了 WebUI、模块管理器支持 WebUI（如 KernelSU / SukiSU 等），并检查模块目录下 `webroot/index.html` 是否存在。若曾选择不安装 WebUI，可重新刷入同版本并按音量上选择安装；配置处理仍会单独询问。

## 更新后配置会恢复默认吗？

更新同 ID 的 `QSC_Battery` 时，安装脚本会询问是否保留原有 `config.conf`：音量上保留，音量下使用新版默认值；20 秒未选择时默认保留。旧 ID `QuantitativeStopCharging_switch` 仍按旧版清理流程处理，不迁移其配置。

## 主题 / 莫奈 / 分页设置丢了？

这些选项保存在 WebView 的 `localStorage`，清应用数据或换管理器打开后可能重置，与 `config.conf` 无关。

## 停充后无法恢复充电？

检查恢复电量 / 恢复温度是否合理；也可临时关闭模块总开关，或卸载模块后重启。

## 配置改完没反应？

配置即时写入 `config.conf`。若仍无效，看日志是否报错节点权限或机型未适配。

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

尽量不要同时安装多个控制充电开关的模块，以免互相覆盖节点状态。
