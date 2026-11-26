# 适配机型说明

停充依赖内核暴露的充电开关节点，**不是按机型名白名单生效**。安装后会探测本机节点并写入 `data/device.profile`；列表里没有的机型，只要节点可用，同样可能正常工作。

## 请先读这一段

下面的机型表来自维护者与社区的**实测反馈**，只说明「有人在该机上验证过停充可用」，**仅供参考，不构成保证**。

同一型号也可能因系统版本、内核、运维包不同而结果不同。是否在你这台机器上生效，请以**刷入后实测**为准：把停止电量临时调低、插电观察是否停充、日志是否写入成功。无效时可跑诊断或测开关，见文末。

## 机型停充节点 ABI（有这些就能用）

诊断或 `ls` 能看到下列接口时，模块一般能走对应停充路径：

| ABI / 节点特征                                                                     | 常见机型族                              | 停充写法（概念）                                             |
| :--------------------------------------------------------------------------------- | :-------------------------------------- | :----------------------------------------------------------- |
| `…/mca_*/handle_state` 或 `stop_handle_charge`                                     | 小米 / 红米 HyperOS（K90U、小米 17 等） | 写 `1` 停 / `0` 开；直接 echo，勿 chmod                      |
| `/sys/class/xm_power/charger/charge_interface/charge_enable` + `input_suspend`     | 部分小米（含 17 Pro）                   | 三 token 投票：`qsc all 0/1`、`micharge all 1/0`             |
| `/sys/class/oplus_chg/…/mmi_charging_enable` 或 `/sys/devices/virtual/oplus_chg/…` | 一加 / OPPO / realme（ColorOS）         | `0` 停 / `1` 开；class 与 virtual 常是同一节点，只写一处即可 |
| `qcom-battery` / `battery` 下 `input_suspend`、`charging_suspend*`                 | 多数骁龙机                              | `1` 停 / `0` 开（以测开关为准）                              |
| `charge_behaviour`（`auto` / `inhibit-charge`）                                    | 标准内核接口                            | 末位兜底                                                     |
| OPlus `class` + `virtual` 双路径                                                   | ColorOS                                 | 模块会去重，避免同一 inode 写两遍                            |

**不要**把 `charge_control_limit`、`handle_stop_charging` 当常规开关（易误伤或与系统互抢）。

## 参考机型（实测有效）

| 机型               | 备注（常见路径 / 说明）                                                                                                 |
| :----------------- | :---------------------------------------------------------------------------------------------------------------------- |
| 红米 K40           | 骁龙 · `qcom-battery` / `input_suspend` 一类节点                                                                        |
| 红米 K50U          | 同上                                                                                                                    |
| 红米 K60           | 骁龙 · 注意停充后假放电与插拔判定                                                                                       |
| 红米 Note 12 Turbo | 骁龙 · 通用停充节点                                                                                                     |
| 红米 K90 Ultra     | MCA（`handle_state` 等）· 插电时 `status` 可能长期 Not charging                                                         |
| 小米 13（fuxi）    | 骁龙 · 勿把 `charge_control_limit` 当开关                                                                               |
| 小米 14            | 骁龙 · 避免反复写内核处理类节点                                                                                         |
| 小米 17 Pro        | MCA / `xm_power` 投票接口（视内核暴露情况）                                                                             |
| 一加 Ace 2 Pro     | ColorOS · `mmi_charging_enable`（`class` / `virtual`）                                                                  |
| 一加 15            | ColorOS · 同上 OPlus 充电使能节点                                                                                       |
| 一加 15T           | ColorOS · `mmi_charging_enable`；未插电也可能报 `Charging`，插电判定须有端口/电流旁证；停充后系统易改回节点，宜单点维持 |

表会随反馈增补；未列出 ≠ 不支持。

## 本机怎么确认

1. 刷入并重启，打开模块 WebUI 或改 `config.conf`，把 **停止电量** 临时调到当前电量以下（例如当前 70% 则设 65），**恢复电量**再低几档。
2. 插电：应停充；拔线或电量落到恢复值：应恢复充电。
3. 仍不行：Action 音量下→音量上写诊断，或执行 `bin/diagnose.sh` / `qsc diagnose`；插电后 Action 音量下→音量下测开关。报告见 `/sdcard/qsc_diagnose.txt`。
4. 也可在 WebUI「我的」使用机型节点社区预设（导入前注意勿带隐私信息）。

更多排障见 [常见问题 · 停充与机型](/guide/faq#停充与机型)。
