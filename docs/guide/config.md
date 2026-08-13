# 配置说明

推荐通过 **WebUI** 修改。停充与电流控制使用**两套配置文件**，互不混写。

| 文件                  | 内容                                          |
| --------------------- | --------------------------------------------- |
| `config/config.conf`  | 电量 / 温度停充、充满再停、自动拔插、兼容模式 |
| `config/current.json` | 电流控制（安装时可选；未安装则无此文件）      |

`current.json` 由 `bin/lib/jsonc.sh` 在机上用 **awk/sed** 解析（不依赖 `jq` / Python）。仓库源文件可带 `//` 注释方便开发；`npm run package:module` 打包时会剥注释写成严格 JSON。WebUI 保存亦为无注释 JSON。字段含义见下表。

## 模块开关

| 方式                | 说明                                               |
| ------------------- | -------------------------------------------------- |
| WebUI「模块总开关」 | 关闭后写入 `data/off_qsc`，逻辑暂停                |
| 快捷脚本            | 模块目录下的 `打开充电控制.sh` / `关闭充电控制.sh` |

## 电量停充（`config.conf`）

| 配置项               | 含义                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------ |
| `power_stop`         | 停止充电电量；填 `110` 表示关闭电量停充                                                    |
| `power_start`        | 恢复充电电量，须小于停止值                                                                 |
| `power_stop_time`    | 触发停充前的延时（秒）                                                                     |
| `charge_full`        | `1` = 充满再停                                                                             |
| `power_reset`        | `1` = 自动拔插                                                                             |
| `Compatibility_mode` | `1` = 兼容模式：跳过本模块电流控制，仅保留电量/温度停充；与其它快充/限流模块同装时建议开启 |
| `power_switch`       | 可选，可多行。自定义供电开关，格式见下节；填写后优先于自动扫描                             |

::: tip
澎湃 OS 3.0 建议停止与恢复电量间隔 **至少 10%**。
:::

### 自定义供电开关（`power_switch`）

自动扫描无效或效果不佳时，可按如下格式自行填写，**每行一个**：

```text
power_switch=[/sys/class/power_supply/battery/batt_slate_mode start=0 stop=1]
power_switch=[/proc/mtk_battery_cmd/current_cmd start=0::0 stop=0::1]
```

| 字段    | 含义                          |
| ------- | ----------------------------- |
| 路径    | sysfs / proc 下的可写充电开关 |
| `start` | 恢复充电时写入的值            |
| `stop`  | 停止充电时写入的值            |

- 值中的空格可用 `::` 代替（写入时还原为空格）
- WebUI「策略 → 自定义供电开关」可编辑；也可直接改 `config.conf`
- 优先级：MCA → `preferred_switch`（`test_switch` 实测）→ **用户 `power_switch`** → 全量扫描/兜底
- 候选示例见 `config.conf` 注释

### 首选停充开关（`data/device.profile`）

插电后用 adb 运行「停充开关实测」（`bin/test_switch.sh`）。测出可逆有效节点后会写入：

| 字段                                 | 含义              |
| ------------------------------------ | ----------------- |
| `preferred_switch`                   | 首选节点路径      |
| `preferred_start` / `preferred_stop` | 恢复 / 停充写入值 |
| `preferred_tested_at`                | 实测时间          |

未实测时行为与原先一致（多节点兜底）。MCA 机型仍优先 `handle_state`。

## 温控停充（`config.conf`）

| 配置项                     | 含义                |
| -------------------------- | ------------------- |
| `temperature_switch`       | `1` 开启 / `0` 关闭 |
| `temperature_switch_stop`  | 达到该温度停充      |
| `temperature_switch_start` | 降到该温度恢复      |

电量和温控可能在同一轮同时触发。模块会分别记录停充原因，只有电量不高于 `power_start` 且温度不高于 `temperature_switch_start` 后才恢复充电，避免高电量下反复启停。

## 电流控制（`current.json`，可选）

安装时选择「电流控制」后才会写入脚本与配置。未安装时 WebUI 不显示相关入口。

| 配置项                                                | 含义                                                                                        |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `current_control`                                     | 总开关：`0` 关 / `1` 开（**默认 0**）                                                       |
| `bypass_enable`                                       | 旁路总开关：`0` 关 / `1` 开（**默认 0**）；关则不触发旁路与回补；旧配置无此字段时脚本视为开 |
| `battery_stop`                                        | 旁路·电量：电量 ≥ 该值时进入旁路；`110` = 关                                                |
| `bypass_temp`                                         | 旁路·温度：温度 ≥ 该值时进入旁路；`110` = 关                                                |
| `bypass_schedule`                                     | 旁路·时段：`["22:00-08:00"]` 等（支持跨天）；空数组 = 关；与上两项为「或」                  |
| `bypass_mode`                                         | `sim` 仅写电流（默认）；`auto` 本机有旁路节点才尝试，否则回退 `sim`                         |
| `safety_temp_max`                                     | 旁路安全温度上限 (°C，默认 48)；过热改用二限小电流                                          |
| `slow_charge`                                         | 慢充：电量 ≥ 该值时用二限小电流；`110` = 关                                                 |
| `default_current_max`                                 | 默认充电电流上限（微安）                                                                    |
| `temperature_current`                                 | 电流温控：`0` / `1`                                                                         |
| `default_current_limit` / `default_current_max_limit` | 一限温度 (°C) / 一限电流（微安）                                                            |
| `temperature_current_limit` / `constant_current_max`  | 二限温度 / 二限电流（建议 ≥ 50000）                                                         |
| `app_limit` / `app_current_max` / `app_list`          | 游戏限流开关、电流、包名（**JSON 字符串数组**；WebUI 可勾选）                               |
| `battery_current`                                     | 用户补充电流节点路径数组；主写不含 usb 输入口                                               |
| `current_step_ua`                                     | 可选；台阶写入（微安）。`0` 或不写 = 直接写目标；旧机可设 `500000`                          |
| `current_reaffirm_sec`                                | 可选；偏高时周期重申间隔（秒，默认 24）。电流已压住则跳过。`0` = 关周期重申                 |
| `current_drift_ua`                                    | 可选；偏高裕量（微安，默认 300000）。仅实测偏高才强制；偏低不重申                           |
| `restricted`                                          | 可选；`"路径 value=值"` 字符串数组。限流前写入；空数组则跳过                                |

::: warning
电流控制**不修改** `/data/vendor/thermal`，也**不做**内核 / MCA 补丁。默认旁路为写电流的「模拟旁路」；`auto` 仅在探测到只读值为 `0/1` 的已知节点时才写入，失败立即回退。效果因机而异，可能与其它快充 / 限流模块冲突。仅需停充时可不装此组件，或保持总开关关闭；若仍冲突，在 `config.conf` 开启 `Compatibility_mode=1`。

**安全说明**：限流主写电池/`main` 的 `constant_charge_current_max`（微安），不写 usb 输入口电流节点；实测已压住时整轮不碰限流节点，偏低不强制；仅偏高时漂移/周期轻量重申。仍不写 `charge_control_limit`、`thermal_input_current` 等。WebUI 与脚本侧会对电量/温度/电流做范围钳位（电流约 100mA–10A，二限/游戏上限 3A，延时 1–120 秒），非法或天文数字会回落到安全默认。部分机型内核会忽略用户态限流；若插电重启请关闭电流控制或开兼容模式。诊断报告会列出探测节点与读回结果。
:::

WebUI 游戏列表：可「加载应用列表」后搜索应用名 / 包名并勾选（优先使用管理器自带的应用枚举接口，否则 `pm list packages -3`）。也可继续手动编辑包名。

## WebUI 使用提示

- 停充配置修改后一般 **即时生效**（主循环约 3 秒一轮）
- 电流控制在 WebUI 中单独保存到 `current.json`
- 「最近日志」可查看停充 / 恢复 / 限流记录；悬浮底栏开启时默认展示更多行
- 「更多 → 显示」可切换主题包（默认 / MD3 / MIUIX）、深浅色、颜色主题或 MD3 色值；MIUIX 支持莫奈、悬浮底栏与液态玻璃
- 显示相关选项保存在本机 WebUI 本地存储，**不会**写入配置文件
- 顶栏 / 底栏按 WebUI-X insets 做沉浸，与状态栏、虚拟按键栏底色衔接

策略页示意（更多交互见 [WebUI 使用说明](/guide/webui#策略)）：

![策略页](/screenshots/webui-config.png)
