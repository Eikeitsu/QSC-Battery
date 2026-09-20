# 功能介绍

**充电控制**（仓库 QSC-Battery，模块 id `QSC_Battery`）运行在 Magisk / KernelSU / APatch 等方案上：真正干活的是模块服务；WebUI / 伴侣 APP / CLI 只是配置与观察入口。

## 产品组成

| 组件             | 说明                                                      |
| ---------------- | --------------------------------------------------------- |
| Magisk 模块      | `service.sh` 主循环：停充决策、写开关/电流、日志与简介    |
| WebUI（可选）    | 管理器内四页：概览 / 策略 / 日志 / 我的                   |
| 伴侣 APP（可选） | Compose 客户端；可内嵌模块包；不挂后台保活                |
| qscd（可选）     | 只读监听 `power_supply` uevent；不写充电节点              |
| CLI              | `/data/adb/qsc/bin/qsc`（`help` / `status` / `stats` 等） |

## 停充

- **电量停充**：`power_stop` / `power_start`；填 `110` 可关闭电量停充
- **延时停充** `power_stop_time`；**充满再停** `charge_full`（仅停止电量=100 且当前 100% 时生效）
- **涓流模式** `charge_full_mode`：`auto` / `current` / `time`（时间默认约 10 分钟）
- **温度停充**：过高停充、回落后恢复；不受电量时段限制
- **电量停充时段** `power_stop_schedule`（可多行 `HH:MM-HH:MM`）
- **按 App 停充**：前台/进程命中包名则停充
- **无线策略** `wireless_policy`：`same` 与有线相同；`ignore` 仅无线时不触发电量/温控/App 停充（已停充仍维持）
- **自动拔插** `power_reset`：利于激活快充
- **兼容模式**：跳过本模块电流控制，只保留电量/温度停充
- **拔线还原** `unplug_restore`（默认开）：关则保留停充节点，再插上仍停到恢复电量
- **停充持锁** `stop_hold_wakelock`：`0` / `1` / `auto`（魅族/MCA：息屏·夜间才持锁，亮屏释放）
- **全量盲写** `switch_batch_blind`（默认开）

写入优先级大致为：用户 `power_switch` → MCA → preferred → 自动扫描 → 末位兜底。详见 [配置说明](/guide/config)。

## 电流控制（安装时可选）

独立文件 `config/current.json`，总开关默认关闭。能力包括：

- 模拟旁路（写电流接近 0）/ 本机硬件旁路节点（`bypass_mode=auto`）
- 按电量、温度、时段触发旁路；过热改写小电流
- 慢充、默认电流上限、温度一限/二限、游戏/前台限流

不改温控文件、不做内核补丁。

## 省电与主循环

默认 `power_saver=1`，配置在 `config/power.conf`（WebUI **策略 → 省电策略** / APP **进阶 → 省电策略**）。

### 未插电怎么睡

1. 未插电且距上次满轮未超时 → **跳过**整轮 `qsc_switch.sh`（只做轻量检查）
2. 有 **qscd** 时阻塞在充电 uevent：插拔即时醒；超时兜底默认约 **600s**
3. 无 qscd 时未插电默认约 **90s** 一轮轻量检查
4. 插电离阈值较远用更长间隔；接近阈值回到短间隔

### 息屏 · 深睡 · 夜间（层级，不是三套互斥）

| 阶段     | 默认门槛                                         | 作用                                       |
| -------- | ------------------------------------------------ | ------------------------------------------ |
| 息屏加强 | 连续息屏约 **90s**（`screen_off_enter_sec`）     | 放大 idle、暂停动态简介刷新                |
| 深睡     | 再连续息屏约 **10 分钟**（`deep_after_sec=600`） | 更长兜底间隔（约 15 分钟）                 |
| 夜间     | 默认关；开启后命中 `night_schedule`              | **直接**按深睡参数，不要求先息屏满 10 分钟 |

档位：`balanced`（默认）/ `aggressive`（更狠，强制静态简介）/ `custom`（手调秒数）。

不是「杀进程零耗电」：service 与 qscd 仍驻留，目标是少唤醒、接近系统待机。自查见 [常见问题 · 待机耗电](/guide/faq#standby) 与 [CLI `stats`](/guide/cli)。

充电历史默认**仅插电采样**。键名与间隔见 [配置说明 · power.conf](/guide/config#powerconf省电)。

## 日志 · 事件 · 曲线

| 路径                      | 内容                                                |
| ------------------------- | --------------------------------------------------- |
| `data/log.log`            | 运行日志（含省电边沿 / 驻停总结，可选「省电统计」） |
| `data/charge_events.log`  | 插拔 / 停充 / 温控等事件                            |
| `data/charge_history.csv` | 插电采样（曲线）                                    |
| `data/health_history.csv` | 日采样健康趋势                                      |

WebUI「日志」/ APP「动态」可看运行日志与充电事件。

## 机型适配

- 安装时探测写入 `data/device.profile`（MCA 路径、preferred 等）
- WebUI：测开关、清缓存、自定义 `power_switch`、设备档案库、社区机型预设
- Action / `diagnose` / `test-switch` / `qsc detect`

## 动态简介

模块管理器列表简介随状态变化。插电判定以端口交叉证据为准（避免部分机型假 `Charging`）。

- **按需刷新**：无人打开 Magisk/KSU/APatch/MMRL 等管理器时几乎不刷电量数字；打开管理器会立刻对齐。停充/插拔等状态变化仍会写。
- `description_enable=0`：固定产品文案并停 worker，略省待机。

## 界面入口

- [WebUI 使用说明](/guide/webui)
- [伴侣 APP](/guide/app)
- [命令行 CLI](/guide/cli)

## 适用场景

| 场景               | 建议                                              |
| ------------------ | ------------------------------------------------- |
| 过夜充电           | 停止 80–90%；可开夜间省电或强力档                 |
| 游戏 / 导航        | 开温控；可选游戏限流或旁路                        |
| 满电出门           | `power_stop=100` 或 `110` 关电量停充              |
| 与其它限流模块同装 | 开兼容模式，或不安电流组件                        |
| 在意待机掉电       | 确认 qscd 可用；见 [FAQ 待机](/guide/faq#standby) |

## 路径速查

```text
/data/adb/modules/QSC_Battery/config/config.conf
/data/adb/modules/QSC_Battery/config/power.conf
/data/adb/modules/QSC_Battery/config/notify.conf
/data/adb/modules/QSC_Battery/config/current.json   # 可选
/data/adb/modules/QSC_Battery/data/log.log
/data/adb/qsc/bin/qsc
```
