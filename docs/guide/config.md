# 配置说明

推荐用 **WebUI** 或 **伴侣 APP** 修改。也可用 `bin/qsc.sh config` 或直接编辑文件。

| 文件                  | 内容                                                 |
| --------------------- | ---------------------------------------------------- |
| `config/config.conf`  | 停充阈值、温控、无线、App 停充、历史/曲线等          |
| `config/power.conf`   | 省电档位、息屏/夜间/深睡、循环间隔、守护、简介、持锁 |
| `config/notify.conf`  | 充电事件通知、勿扰时段、常显功耗通知                 |
| `config/current.json` | 电流控制（仅安装该组件时存在）                       |
| `data/device.profile` | 机型探测结果（MCA、preferred 等）                    |

`current.json` 在机上用 awk/sed 解析（不依赖 jq）。仓库源可带 `//` 注释，打包时剥成严格 JSON。

路径前缀：`/data/adb/modules/QSC_Battery/`。旧版把省电/通知挤在 `config.conf` 时，启动会**一次性迁到** `power.conf` / `notify.conf`。

## 模块软开关

| 方式                     | 说明                                  |
| ------------------------ | ------------------------------------- |
| WebUI / APP 总开关       | 关闭写入 `data/module_off`，逻辑暂停  |
| `qsc.sh on\|off\|toggle` | 同上                                  |
| 快捷脚本                 | `打开充电控制.sh` / `关闭充电控制.sh` |

---

## `config.conf` 常用项

### 电量停充

| 键                    | 默认     | 含义                                     |
| --------------------- | -------- | ---------------------------------------- |
| `power_stop`          | 100      | 停充电量；`110` = 关闭电量停充           |
| `power_start`         | 95       | 恢复电量（须小于停止值）                 |
| `power_stop_time`     | 3        | 触发停充前延时（秒）；充满再停开启时无效 |
| `charge_full`         | 0        | `1` = 充满再停                           |
| `power_reset`         | 0        | `1` = 自动拔插                           |
| `power_stop_schedule` | （注释） | 多行 `HH:MM-HH:MM`；留空=全天电量停充    |
| `power_switch`        | （注释） | 多行自定义供电开关，优先于自动扫描       |

::: tip
澎湃等机型建议停止与恢复电量间隔 **≥ 10%**。
:::

### 温度停充

| 键                         | 默认 | 含义       |
| -------------------------- | ---- | ---------- |
| `temperature_switch`       | 1    | 温控总开关 |
| `temperature_switch_stop`  | 60   | 停充温度 ℃ |
| `temperature_switch_start` | 50   | 恢复温度 ℃ |

### 行为

| 键                     | 默认     | 含义                             |
| ---------------------- | -------- | -------------------------------- |
| `compatibility_mode`   | 0        | `1` = 跳过本模块电流控制         |
| `unplug_restore`       | 1        | 拔线是否立刻还原节点并清停充标记 |
| `charge_full_mode`     | auto     | `auto` / `current` / `time`      |
| `charge_full_wait_sec` | 600      | 时间支路等待秒数（UI 不暴露）    |
| `wireless_policy`      | same     | `same` / `ignore`                |
| `app_stop`             | 0        | 按 App 停充                      |
| `app_stop_list`        | （注释） | 逗号分隔包名                     |
| `history_enable`       | 1        | 插电采样曲线                     |
| `history_interval_sec` | 60       | 采样间隔                         |
| `switch_verify_sec`    | 1        | 停充校验等待                     |
| `switch_batch_blind`   | 1        | 全量盲写停充节点                 |

---

## `power.conf`（省电）

入口：WebUI **策略 → 省电策略**；APP **进阶 → 省电策略**。

未插电为**事件驱动驻停**（qscd 阻塞在插拔 uevent），不是杀进程，也不是绝对「零耗电」。
主循环在确认未插电后进入 **lean**：再醒时几乎只 wait；简介/XP 管家仅在拔电首轮或配置变更时跑。
配置按文件 mtime 哨兵加载（未变不重读）；App/WebUI 保存会 bump `data/conf_reload_req`（手改 conf 靠 mtime 即可）。

未插电时大致时间线（默认均衡档）：

1. **亮屏日用**：快路径跳过满轮 + qscd 长睡（兜底约 600s）
2. **连续息屏 ≥ `screen_off_enter_sec`（默认 90s）** → 息屏加强（放大 idle、停动态简介）
3. **再连续息屏 ≥ `deep_after_sec`（默认 600s）** → 深睡（兜底约 900s）
4. **开启夜间且命中时段** → 直接按深睡参数（不要求先满 10 分钟息屏）

亮灭闪动：不足约 90s 不会进息屏加强；过短驻停也不写 INFO 总结。

| 键                              | 默认        | 含义                                                         |
| ------------------------------- | ----------- | ------------------------------------------------------------ |
| `power_saver`                   | 1           | 省电总开关                                                   |
| `power_profile`                 | balanced    | `balanced` / `aggressive` / `custom`                         |
| `screen_off_saver`              | 1           | 息屏加强                                                     |
| `screen_off_enter_sec`          | 90          | 连续息屏多久才进息屏加强；`0`=立刻                           |
| `night_saver`                   | 0           | 夜间省电                                                     |
| `night_schedule`                | 23:00-07:00 | 多行 `HH:MM-HH:MM`；**支持跨天**；`night_saver=0` 时不生效   |
| `deep_idle_enable`              | 1           | 深睡（息屏持续或夜间）                                       |
| `deep_after_sec`                | 600         | 息屏多久后深睡                                               |
| `deep_idle_sec`                 | 900         | 深睡未插电兜底秒数                                           |
| `deep_full_gap_sec`             | 7200        | 深睡强制满轮间隔                                             |
| `heartbeat_sec`                 | 180         | 心跳写盘间隔                                                 |
| `loop_interval_idle_sec`        | 90          | 无守护时未插电轻量间隔                                       |
| `loop_interval_idle_native_sec` | 600         | 有 qscd 时未插电超时兜底                                     |
| `loop_interval_*`               | 见模板      | 自定义档可调；插电近阈值不受 DeepPark 放松                   |
| `native_daemon` / `native_impl` | 1 / rust    | 事件守护                                                     |
| `description_enable`            | 1           | 动态简介                                                     |
| `desc_viewer_pkgs`              | （空）      | 逗号追加管理器包名；Magisk 会尽量从 `requester` 识别随机包名 |
| `stop_hold_wakelock`            | auto        | `auto`=魅族/MCA 仅息屏·夜间持锁；`1`=持续持锁（挡 Doze）     |

动态简介默认**按需刷新**：仅当模块管理器在前台时勤刷电量；无人看列表时可不更新电量数字（打开管理器会立即对齐）。停充/复充/关模块等状态变化仍会写入。关 `description_enable` 则固定文案并停 worker。

守护实际版本写在 `data/native_version`（安装/下载时更新，只读状态，不是手改项）。

档位：`balanced` 默认；`aggressive` 拉长 idle/心跳并强制静态简介；`custom` 用手调秒数。

自查省电：`qsc diagnostic on` + `qsc stats`，或见 [FAQ](/guide/faq#standby)。

---

## `notify.conf`（通知）

| 键                      | 默认             | 含义                         |
| ----------------------- | ---------------- | ---------------------------- |
| `notify_charge_event`   | 0                | 停充/恢复/失败通知           |
| `notify_charge_kinds`   | stop,resume,fail | 种类                         |
| `notify_quiet_schedule` | （注释）         | 勿扰时段（失败仍通知）       |
| `notify_power_status`   | 0                | 常显功耗通知（费电，默认关） |

---

## 电流控制

见 `config/current.json`（安装时可选）。字段说明见 WebUI「电流控制」与 [功能介绍](/guide/features)。
