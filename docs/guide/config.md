# 配置说明

推荐用 **WebUI** 或 **伴侣 APP** 修改。也可用 `bin/qsc.sh config` 或直接编辑文件。

| 文件                  | 内容                                           |
| --------------------- | ---------------------------------------------- |
| `config/config.conf`  | 停充、省电、守护、通知、无线、App 停充、历史等 |
| `config/current.json` | 电流控制（仅安装该组件时存在）                 |
| `data/device.profile` | 机型探测结果（MCA、preferred 等）              |

`current.json` 在机上用 awk/sed 解析（不依赖 jq）。仓库源可带 `//` 注释，打包时剥成严格 JSON。

路径前缀：`/data/adb/modules/QSC_Battery/`。

## 模块软开关

| 方式                     | 说明                                  |
| ------------------------ | ------------------------------------- |
| WebUI / APP 总开关       | 关闭写入 `data/off_qsc`，逻辑暂停     |
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

### 行为与通知

| 键                      | 默认             | 含义                     |
| ----------------------- | ---------------- | ------------------------ |
| `Compatibility_mode`    | 0                | `1` = 跳过本模块电流控制 |
| `stop_hold_wakelock`    | auto             | `0` / `1` / `auto`       |
| `wireless_policy`       | same             | `same` / `ignore`        |
| `app_stop`              | 0                | 按 App 停充              |
| `app_stop_list`         | （注释）         | 逗号分隔包名             |
| `notify_charge_event`   | 0                | 停充/恢复/失败通知       |
| `notify_charge_kinds`   | stop,resume,fail | 通知种类                 |
| `notify_quiet_schedule` | （注释）         | 勿扰时段（失败仍通知）   |
| `notify_power_status`   | 0                | 常显电量/温度/电流通知   |

### 省电与守护

| 键                                 | 默认       | 含义                                         |
| ---------------------------------- | ---------- | -------------------------------------------- |
| `power_saver`                      | 1          | 省电模式（强烈建议保持开启）                 |
| `loop_interval_sec`                | 3          | 近阈值检查间隔（秒）                         |
| `loop_interval_maintain_sec`       | 8          | 停充维持间隔                                 |
| `loop_interval_idle_sec`           | 90         | 未插电、无 qscd 时间隔                       |
| `loop_interval_idle_native_sec`    | 300        | 未插电、有 qscd 时超时兜底                   |
| `loop_interval_plugged_sec`        | 15         | 插电、离阈值远                               |
| `loop_interval_plugged_native_sec` | 90         | 插电、有 watch 时                            |
| `loop_interval_near_window`        | 3          | 「接近阈值」窗口（%）                        |
| `native_daemon`                    | 1          | 启用事件守护                                 |
| `native_impl`                      | rust       | `rust` / `c` / `off`                         |
| `native_version`                   | （运行时） | 当前守护版本元数据（只读/状态）              |
| `switch_verify_sec`                | 1          | 写开关后校验等待（非全量盲写兜底等）         |
| `switch_batch_blind`               | 1          | `1`=0814 全量盲写+每轮重申；`0`=首成功后重申 |

### 历史与曲线

| 键                     | 默认            | 含义                           |
| ---------------------- | --------------- | ------------------------------ |
| `history_enable`       | 1               | 插电历史采样                   |
| `history_interval_sec` | 60              | 采样间隔                       |
| `chart_show`           | 常由 WebUI 写入 | 首页曲线显示；关时可联动停采样 |

### 自定义供电开关格式

每行一条，常见形态：

```text
/sys/.../path,start=1,stop=0
```

勿把 `night_charging` / `cool_mode` 等**策略类**节点当供电开关。详见 FAQ。

### 遗留键

`Shut_down` 在部分脚本仍可读到，但**当前无实际关机逻辑**，请勿依赖。

---

## `current.json`（电流控制）

仅安装电流组件后存在。常用字段（默认总开关关）：

| 字段                                               | 含义                                       |
| -------------------------------------------------- | ------------------------------------------ |
| `current_control`                                  | 总开关                                     |
| `bypass_enable`                                    | 旁路总开关                                 |
| `battery_stop` / `bypass_temp` / `bypass_schedule` | 旁路触发条件（或）                         |
| `bypass_mode`                                      | `sim` 模拟写电流 / `auto` 优先硬件旁路节点 |
| `safety_temp_max`                                  | 旁路过热改小电流                           |
| `slow_charge`                                      | 慢充阈值（110=关）                         |
| `default_current_max`                              | 默认上限（µA）                             |
| `temperature_current` 及一限/二限温度电流          | 阶梯限流                                   |
| `app_limit` / `app_current_max` / `app_list`       | 游戏/前台限流                              |
| `battery_current` / `restricted`                   | 节点列表与策略                             |

完整注释见模块内 `config/current.json` 模板。

---

## 运行时数据（勿手改除非排查）

| 路径                      | 说明               |
| ------------------------- | ------------------ |
| `data/off_qsc`            | 软关闭             |
| `data/power_switch`       | 当前处于停充写入态 |
| `data/device.profile`     | 机型档案           |
| `data/log.log`            | 运行日志           |
| `data/charge_events.log`  | 充电事件           |
| `data/charge_history.csv` | 曲线采样           |
| `data/list_switch`        | 开关扫描缓存       |

清除开关缓存：删 `list_switch` + `device.profile` 后重启，或 WebUI「测开关与缓存」。
