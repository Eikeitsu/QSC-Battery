# 常见问题

## 刷入后没有效果？

1. 确认已重启
2. WebUI 中确认模块总开关已打开
3. 查看 `data/log.log` 是否有「未找到有效充电控制节点」
4. 若机型较新，可执行诊断脚本：

```bash
sh /data/adb/modules/QSC_Battery/bin/diagnose.sh
```

报告在 `/sdcard/qsc_diagnose.txt`，可反馈给维护者适配。

## WebUI 打不开？

确认模块管理器支持 WebUI（如 KernelSU / SukiSU 等），并检查模块目录下 `webroot/index.html` 是否存在。

## 主题 / 莫奈 / 分页设置丢了？

这些选项保存在 WebView 的 `localStorage`，清应用数据或换管理器打开后可能重置，与 `config.conf` 无关。

## 停充后无法恢复充电？

检查恢复电量 / 恢复温度是否合理；也可临时关闭模块总开关，或卸载模块后重启。

## 配置改完没反应？

配置即时写入 `config.conf`。若仍无效，看日志是否报错节点权限或机型未适配。

## 与其它充电类模块冲突？

尽量不要同时安装多个控制充电开关的模块，以免互相覆盖节点状态。
