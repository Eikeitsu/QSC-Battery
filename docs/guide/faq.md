# 常见问题

按场景查阅。改阈值请用 WebUI「策略」或伴侣 APP；键名细节见 [配置说明](/guide/config)。

## 安装与更新

### 刷完没反应？

1. **重启**一次
2. WebUI / APP 里确认软开关是开的（不要有 `module_off`）
3. 打开运行日志，看有没有「未找到有效充电控制节点」
4. **插着充电器**做一次测开关：WebUI「策略 → 测开关与缓存」，或：

```bash
/data/adb/qsc/bin/qsc diagnose
/data/adb/qsc/bin/qsc test-switch
```

报告多在 `/sdcard/qsc_diagnose.txt`。部分红米等 MCA 机：停止与恢复电量最好差 **≥ 10**。

### 更新后设置变了？

同模块更新时：

- **音量上 / 超时**：停充等**核心设置会保留**；省电间隔等会用**新版默认**（方便吃到待机优化）
- **音量下**：全部恢复包内默认

若省电变慢/变勤，多半是预期；到「省电策略」里再调。从很老的「定量停充」模块升级**不会**带过旧配置。

### WebUI 打不开？

安装时要勾选 WebUI，且管理器要支持模块网页（KernelSU / SukiSU / APatch 系 / MMRL / WebUI-X 等）。普通浏览器不行。可重刷同版本并选择安装 WebUI。

### 没有「电流控制」？

安装时没选该组件。重刷并勾选；装上后总开关默认仍是**关**的，需自己打开。

---

## 停充与机型

### 未插电却显示「充电中」？

个别机型内核会误报。当前版本以**端口是否真有电**为准，不只看 status 字样。请升到较新版本。

### 小米 / 澎湃一直充了又停？

常见是节点和系统充电服务抢控制。试：清掉 `list_switch`、`device.profile` 后重启；自定义开关里不要塞策略类节点；插电再测开关。日志「会话」能对上停充→恢复的一轮。

### 和别的充电/限流模块一起用？

开 **兼容模式**，或安装时不安电流组件，只用电量/温度停充。

### 机型节点社区分享？

WebUI「我的 → 机型节点社区分享」可导入或分享预设。注意别带上隐私信息。

---

## 待机与省电

### 待机掉得很快？模块在干嘛？ {#standby}

**DeepPark v2**（当前默认）：未插电 + 息屏/夜间时，主循环只做 **插拔/conf 边沿** 才醒；深睡超时约 **1h（均衡）/ 2h（强力）**；**不再**有每几分钟必醒的心跳子进程。

**未插电时模块主要在干什么：**

1. **主服务 + qscd**：`watch` 阻塞等插拔（或超长超时兜底）；心跳仅在醒来时**节流写盘**
2. **动态简介（可保持开启）**：息屏/深睡写静态；亮屏无人看几乎不写盘；打开管理器仍即时刷。有 XP 时无第二进程；无 XP 才低频 dumpsys 探测
3. **息屏探测**：深睡粘滞时多数轮次不读亮度 sysfs
4. **XP**：仅前台/亮灭屏写小文件

**如何确认 DeepPark 在干活：**

1. `ps -A | grep -E 'heartbeat|qsc'`：不应再有独立 heartbeat 循环 shell
2. `touch /data/adb/modules/QSC_Battery/data/diagnostic_on`，过一阵看 `data/service_power_stats`：
   - `last_park_sec` 应为小时级（如 3600）
   - `park_wakes_total` 一夜应是个位数～十余次（主要是超时），不是上百
   - `heartbeat_writes` 远少于旧版「每 180s 一次」
3. 测完删掉 `diagnostic_on`

**qscd 费不费电？** 基本不费：对 netlink `poll` 睡眠，不持 `wake_lock`。关掉反而更费。

**如何再压耗电：**

1. 过夜用 **强力** 档，或确认 **夜间省电** 已开（新默认开）
2. 不需要列表电量：**关动态简介**
3. `stop_hold_wakelock` 保持 **auto**；未插电会强制放锁
4. 关常显功耗通知 / diagnostic / debug

**不能绝对零耗电**：常驻 shell + 睡眠中的 qscd 仍有基线。目标是**接近系统待机**。

请先确认：省电总开关开着、`qscd` 可用、没开常显功耗通知。

**插电停充过夜**：默认只在部分机型、且息屏/夜间才短暂持锁，亮屏会放开，避免白天一直挡休眠。

**管理器里电量数字比真机慢**：正常。没人打开 Magisk/KSU 等列表时几乎不刷简介电量；打开后应对齐。若已启用 LSPosed（作用域 `system`）并重启过，进出管理器应接近即时；否则最多约数十秒（dumpsys 降级）。

### 想自己确认「省电有没有在干活」？

可选（测完请关掉，别长期开）：

```bash
/data/adb/qsc/bin/qsc diagnostic on
# 用一会儿 / 过夜后再看：
/data/adb/qsc/bin/qsc stats
/data/adb/qsc/bin/qsc diagnostic off
```

日志里也可看到「进入/退出息屏·夜间·深睡」和退出时的唤醒总结。看 `data/service_power_stats` 时重点对照 `park_wakes_total`、`last_park_sec`、`heartbeat_writes`。更细说明见 [CLI](/guide/cli) 与 [配置 · 省电](/guide/config#powerconf省电)。

**注意**：DeepPark v2 的 2h 超时需要带新上限的 **Rust qscd**（`WAIT_MAX_CAP=14400`）。若仍是旧二进制，超时会被钳在 3600s，壳侧逻辑仍正确，只是强力档兜底达不到 2h。

---

## 界面与配置

### APP 和 WebUI 设置对不上？

两边改的是同一套文件，后保存的生效。刷新一下页面即可。

注意文件分工：停充阈值在 `config.conf`，省电在 `power.conf`，通知在 `notify.conf`。在 WebUI 改「省电策略」即可，不必翻配置文件。

### 命令行怎么用？

```bash
/data/adb/qsc/bin/qsc help
```

常用：`status`、`on`/`off`、`stats`、`diagnose`。完整说明见 [命令行 CLI](/guide/cli)。

### 伴侣 APP 还要勾 LSPosed 吗？

**可选，但推荐。** 勾 **系统框架**（包名 `system`）并重启后：打开 Magisk/KSU 等管理器时简介能更快刷到实时电量；事件守护不可用时还可在插拔边沿助唤醒。不勾、或 XP 异常时自动 dumpsys 回退（稍慢）。停充始终由模块负责。详情见 [伴侣 APP](/guide/app)。
