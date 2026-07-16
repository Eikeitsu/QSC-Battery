# 功能介绍

QSC（Quantitative Stop Charging）定量停充，是一款运行在 Magisk / KernelSU 上的充电控制模块。

## 它能做什么

- **按电量停充**：电量达到设定上限后停止充电，降到恢复值后再继续充
- **按温度停充**：电池温度过高时停充，温度回落后恢复
- **充满再停**：到达 100% 后等待涓流结束再停充，更贴近「真正充满」
- **自动拔插**：插入充电器时模拟一次拔插，有助于激活快充
- **WebUI**：图形界面改配置，实时状态与日志一目了然

## 适用场景

| 场景 | 建议 |
|------|------|
| 过夜充电 | 停止 80–90%，保护电池 |
| 游戏 / 导航 | 开启温控，高温自动停充 |
| 需要满电出门 | 临时把停止电量设为 100，或关闭电量停充 |

## 运行方式

开机后 `service.sh` 循环执行核心脚本，约每 3 秒检查一次电量与温度，满足条件时写入充电控制节点。

配置文件：

```text
/data/adb/modules/QuantitativeStopCharging_switch/config/config.conf
```

运行日志：

```text
/data/adb/modules/QuantitativeStopCharging_switch/data/log.log
```
