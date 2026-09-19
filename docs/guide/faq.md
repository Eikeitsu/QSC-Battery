# 常见问题

## 刷入后没有效果？

1. 确认已**重启**
2. WebUI / APP 中确认模块软开关已打开（无 `data/module_off`）
3. 看 `data/log.log` 是否有「未找到有效充电控制节点」
4. MCA 机型（如部分红米）：确认 `data/device.profile` 含 `mca=1` 与路径；停充与恢复建议间隔 ≥ 10
5. 插电后测开关，或自定义 `power_switch`：

```bash
/data/adb/qsc/bin/qsc status
/data/adb/qsc/bin/qsc diagnose
# 插电：
/data/adb/qsc/bin/qsc test-switch
```

报告常在 `/sdcard/qsc_diagnose.txt`。也可用 WebUI「策略 → 测开关与缓存」。

## 未插电却显示「充电中」？

部分机型（如一加）内核/status 会误报 `Charging`。当前版本简介与插电判定以 **端口 online/present 等证据** 为准，不再单信 status。若仍是 **2026.09.01 及更早**，请升级到含此修复的版本。

## 小米 / 澎湃反复充断电？

多为节点与系统充电服务互抢。建议：清除 `data/list_switch` 与 `data/device.profile` 后重启；勿把策略类节点填进 `power_switch`；插电跑测开关。日志「会话」视图可对照一轮停充→恢复。

## WebUI 打不开？

确认安装时选了 WebUI、`webroot/index.html` 存在，且管理器支持 WebUI 桥接。可重刷同版本并选择安装 WebUI。

## 没有「电流控制」？

安装时未选该组件。重刷并选择安装；装入后还需打开电流总开关（默认关）。

## 更新后配置丢了？

更新同 id 时：

- **音量上**：保留停充阈值、开关、时段、通知等**核心项**；省电间隔等运行参数用**新版默认**（让待机优化生效）
- **音量下**：全部用新版默认
- **超时**：按保留核心项处理

从旧 `QuantitativeStopCharging*` 升级会卸载旧模块且**不迁移**配置。

若更新后发现省电间隔变了，属预期；可在 WebUI 进阶里改回。

## 待机很耗电？模块在后台干嘛？

默认 `power_saver=1` + 可选 qscd：未插电会**跳过**整轮停充脚本，有守护时靠 uevent 睡到**插拔**（不是每一次电量/电流抖动）。请确认：

- 未关 `power_saver` / `native_daemon`（现位于 `config/power.conf`）
- WebUI「省电策略」可用 **强力** 档或开启 **夜间/深睡**
- 守护自检通过（WebUI 守护卡片）
- 未开常显功耗通知（`notify.conf` 的 `notify_power_status`）

**不是绝对零耗电**：模块 service 与 qscd 仍驻留，只是尽量不唤醒。对外目标是「接近系统待机」。

**充满拔线后过夜仍掉电很快**（例如 100%→约 90%）：旧版未插电 watch 不带阈值，等价于「任意电池 uevent 都叫醒 shell」。现未插电 / 停充维持只响应插拔或超时兜底。

**过夜插电且已停充**：`stop_hold_wakelock=auto` 仅在魅族或 MCA 机、且**息屏/夜间**时持内核 wakelock（防深睡改回节点）；**亮屏会释放**，避免日用一直挡 Doze。强制设为 `1` 才会持续持锁。非 MCA 息屏/夜间/深睡维持间隔可拉到约 180–300 秒；MCA 仍按约 30 秒重申。K60 等通用节点机在 `auto` 下通常不持锁。

可查：`cat /data/adb/modules/QSC_Battery/data/wakelock_held` 与 `cat /sys/power/wake_lock`（含 `qsc_stop_chg` 即在持锁）。

仍有余量可关「动态简介」或开「强力」档。详见 [配置说明 · power.conf](/guide/config)。

**简介电量落后真机**：正常。无人打开 Magisk/KSU 等管理器时几乎不刷简介电量（省电）；打开管理器会立刻对齐。停充状态变化仍会更新文案。Magisk 隐藏/随机包名会尽量从 `magisk.db` 的 `requester` 自动识别；其它冷门管理器可在 `power.conf` 用 `desc_viewer_pkgs=` 追加。

## 机型节点社区分享怎么用？

「我的 → 机型节点社区分享」：可导入预设或分享本机 `power_switch` / 档案（勿泄露隐私信息）。

## 与其它充电/限流模块冲突？

开 **兼容模式**，或不安电流组件，只用电量/温度停充。仍冲突时试不同 `preferred_switch` / 自定义开关。

## APP 与 WebUI 配置不一致？

二者读写同一 `config.conf`；后保存的覆盖前者。刷新页面/下拉即可。

## LSPosed 要勾什么？

作用域勾选 **系统框架**（包名 **`system`**，对应 `system_server`）。现代 libxposed 里「Android系统」包名 `android` **不能单独代替**。`qscd` 正常时 XP 几乎不干活；守护不可用时才在插拔边沿写 `/data/system/qsc_xp_wake` 协助唤醒。

APP「我的 → LSPosed / XP」用官方 **XposedService**（不必重启即可看作用域；可一键请求 `system`）。**注入**到 `system_server` 仍需重启后看存活标记。

SELinux enforcing：选用 `/data/system/` 是常见可写路径，**多数机型可用**，但不能保证 100% OEM；失败会停写以免耗电。软关闭：APP 开关或 `touch /data/system/qsc_xp_off`。

## 命令行在哪？

见 [命令行 CLI](/guide/cli)。
