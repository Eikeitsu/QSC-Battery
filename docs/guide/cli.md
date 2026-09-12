# 命令行 CLI

模块内统一入口：

```bash
sh /data/adb/modules/QSC_Battery/bin/qsc.sh help
```

需 Root（adb root / su）。

## 常用命令

| 命令 | 作用 |
| ---- | ---- |
| `status` / `status --raw` | 当前状态摘要 / 原始字段 |
| `on` / `off` / `toggle` | 软开关（`data/off_qsc`） |
| `config list` | 列出配置键 |
| `config get <key>` | 读一项 |
| `config set <key> <value>` | 写一项（白名单键） |
| `log` | 运行日志尾部 |
| `events` | 充电事件尾部 |
| `diagnose` | 生成诊断（同 Action 思路） |
| `test-switch` | 测停充开关（**须插电**） |
| `detect` | 重新探测设备档案 |
| `daemon status\|check\|install\|use\|remove` | 管理 qscd |
| `version` | 版本信息 |

## 示例

```bash
MOD=/data/adb/modules/QSC_Battery
sh $MOD/bin/qsc.sh status
sh $MOD/bin/qsc.sh config set power_stop 80
sh $MOD/bin/qsc.sh config set power_start 70
sh $MOD/bin/qsc.sh off          # 暂停逻辑
sh $MOD/bin/qsc.sh on
sh $MOD/bin/qsc.sh events
sh $MOD/bin/qsc.sh diagnose
# 插电后：
sh $MOD/bin/qsc.sh test-switch
```

## 相关脚本

| 脚本 | 说明 |
| ---- | ---- |
| `bin/diagnose.sh` | 诊断报告 |
| `bin/test_switch.sh` | 完整测开关 |
| `bin/detect_device.sh` | 机型探测 |
| `bin/qscd_fetch.sh` | 守护下载与切换 |
| `打开充电控制.sh` / `关闭充电控制.sh` | 软开关快捷方式 |

多行配置（如 `power_stop_schedule`）更适合用 WebUI / 直接编辑 `config.conf`；CLI `config set` 覆盖常用单行键。
