# 命令行 CLI

装完模块后：

```bash
/data/adb/qsc/bin/qsc help
/data/adb/qsc/bin/qsc status
```

入口在 `/data/adb/qsc/bin/`，**不挂载** `system/bin`（避免暴露 Magisk）。需 Root（`adb shell` / `su`）。

底层仍是模块内 `bin/qsc.sh`；`qsc` 是原生薄包装（无 NDK 时安装 shell 回退）。

## 常用命令

| 命令                                         | 作用                        |
| -------------------------------------------- | --------------------------- |
| `status` / `status --raw`                    | 当前状态摘要 / 原始字段     |
| `on` / `off` / `toggle`                      | 软开关（`data/module_off`） |
| `config list`                                | 列出配置键                  |
| `config get <key>`                           | 读一项                      |
| `config set <key> <value>`                   | 写一项（白名单键）          |
| `log`                                        | 运行日志尾部                |
| `events`                                     | 充电事件尾部                |
| `diagnose`                                   | 生成诊断（同 Action 思路）  |
| `test-switch`                                | 测停充开关（**须插电**）    |
| `detect`                                     | 重新探测设备档案            |
| `daemon status\|check\|install\|use\|remove` | 管理 qscd                   |
| `version`                                    | 版本信息                    |

## 示例

```bash
/data/adb/qsc/bin/qsc status
/data/adb/qsc/bin/qsc config set power_stop 80
/data/adb/qsc/bin/qsc config set power_start 70
/data/adb/qsc/bin/qsc off
/data/adb/qsc/bin/qsc on
/data/adb/qsc/bin/qsc events
/data/adb/qsc/bin/qsc diagnose
# 插电后：
/data/adb/qsc/bin/qsc test-switch
```

## 相关脚本

| 脚本                                  | 说明           |
| ------------------------------------- | -------------- |
| `/data/adb/qsc/bin/qsc`               | 外部 CLI 入口  |
| `bin/qsc.sh`                          | 实际命令实现   |
| `bin/diagnose.sh`                     | 诊断报告       |
| `bin/test_switch.sh`                  | 完整测开关     |
| `bin/detect_device.sh`                | 机型探测       |
| `bin/qscd_fetch.sh`                   | 守护下载与切换 |
| `打开充电控制.sh` / `关闭充电控制.sh` | 软开关快捷方式 |

多行配置（如 `power_stop_schedule`）更适合用 WebUI / 直接编辑 `config.conf`；CLI `config set` 覆盖常用单行键。
