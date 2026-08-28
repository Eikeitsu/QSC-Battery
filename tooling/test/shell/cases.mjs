/**
 * 停充决策层的行为用例。
 *
 * 每条用例把假的 sysfs 电池节点、假的停充开关节点和一份 config.conf 摆好，
 * 跑一次真正的 bin/qsc_switch.sh，然后断言「有没有停充、写了什么值、状态标记
 * 与简介对不对」。这里只覆盖判定，不碰机型探测与电流控制。
 *
 * 尚未覆盖：按 App 停充的「命中」判定本身。用例里靠列表写 sh 让 ps 必然命中，
 * 但这依赖宿主机进程表，不适合用来测更细的匹配规则。
 *
 * 字段说明
 *   sysfs   假 /sys/class/power_supply 下的文件，键是相对路径
 *   config  追加到 config.conf 末尾的覆盖项（后出现的键生效）
 *   data    预置的 data/ 标记文件，值为文件内容
 *   node    注入的停充开关节点：initial=初值，stop/start=写入值，
 *           missing=不创建该文件（用来构造写入失败）
 *   expect  断言；node 省略时不检查节点值
 */

// 电池温度 sysfs 是 0.1°C 单位；300 = 30.0°C
const COOL = "300";

// 时段停充的用例要相对「现在」造窗口，否则换个时间跑就飘了
const NOW = new Date();
const hhmm = (offsetMin) => {
  const d = new Date(NOW.getTime() + offsetMin * 60_000);
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getHours())}:${p(d.getMinutes())}`;
};
// 跨零点的窗口由 qsc_time_in_range 处理，这里不用特殊照顾
const SCHEDULE_NOW_INSIDE = `${hhmm(-30)}-${hhmm(30)}`;
const SCHEDULE_NOW_OUTSIDE = `${hhmm(120)}-${hhmm(180)}`;

// 通用：不发通知、不等停充校验、缩短首次停充延时，让用例跑得快些
const FAST = {
  notify_charge_event: "0",
  switch_verify_sec: "0",
  power_stop_time: "1",
  history_enable: "0",
  app_stop: "0",
};

export const cases = [
  {
    name: "插电充电中且电量到阈值 → 停充",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "0", stop: "1", start: "0" },
    expect: {
      node: "1",
      files: { power_switch: true, battery_switch: true },
      descIncludes: "已停充",
    },
  },

  {
    // 2026.08.25 的回归：当时要求 status 必须是 2/5 才评估停充，
    // 而 MCA 机型插电充电时 battery/status 也报 Not charging，停充分支一次都进不去
    name: "MCA 机型插电但 status=Not charging → 仍应停充",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "0", stop: "1", start: "0" },
    expect: {
      node: "1",
      files: { power_switch: true },
      descIncludes: "已停充",
    },
  },

  {
    // K90U 的 online 节点可能在 MCA 接管后为 0；仅修 charge_eval 不够，
    // 省电快路径也必须先把 Not charging 识别为仍插线，不能跳过整轮。
    name: "MCA status=Not charging 且无 online → 仍应执行停充",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "0", stop: "1", start: "0" },
    expect: {
      node: "1",
      files: { power_switch: true },
      descIncludes: "已停充",
    },
  },

  {
    name: "电量低于阈值 → 不停充",
    sysfs: {
      "battery/capacity": "70",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "1500000",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "0", stop: "1", start: "0" },
    expect: {
      node: "0",
      files: { power_switch: false },
      descIncludes: "充电中",
    },
  },

  {
    name: "温度到停充阈值 → 停充并标记温控",
    sysfs: {
      "battery/capacity": "50",
      "battery/status": "Charging",
      "battery/temp": "620",
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: {
      ...FAST,
      power_stop: "110",
      power_start: "105",
      temperature_switch: "1",
      temperature_switch_stop: "60",
      temperature_switch_start: "50",
    },
    node: { initial: "0", stop: "1", start: "0" },
    expect: {
      node: "1",
      files: { power_switch: true, temp_switch: true },
      descIncludes: "已停充",
    },
  },

  {
    // 本次修的回归：拔线时电量仍高于恢复阈值，原先 power_switch 会一直留着，
    // 简介卡在「已停充」、主循环按维持间隔空转、再插上还可能停不了充
    name: "停充后拔掉充电器 → 还原节点并清除停充状态",
    sysfs: {
      "battery/capacity": "80",
      "battery/status": "Discharging",
      "battery/temp": COOL,
      "battery/current_now": "-400000",
      "usb/online": "0",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    // unplug_streak=1：拔线判定要连续两轮成立才动手，这里补上前一轮
    data: { power_switch: "", battery_switch: "", unplug_streak: "1" },
    // 停充成功后模块会记下生效的条目，恢复时优先照它回写
    activeSwitch: true,
    expect: {
      node: "0",
      files: { power_switch: false, battery_switch: false, unplug_streak: false },
      descIncludes: "未充电",
      logIncludes: "已拔出充电器",
    },
  },

  {
    // 曾经的严重回归：停充手段里的端口 suspend / 电流墙会把 online 打成 0、
    // status 也变成非充电，和拔线一模一样，于是刚停充就被误判拔线还原，
    // 到 100% 反复启停。这里断言首轮只累计防抖计数、绝不动节点
    name: "停充后疑似拔线的第一轮 → 只计数不还原",
    sysfs: {
      "battery/capacity": "100",
      "battery/status": "Discharging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "0",
    },
    config: { ...FAST, power_stop: "100", power_start: "95", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", battery_switch: "" },
    activeSwitch: true,
    expect: {
      node: "1",
      files: { power_switch: true, unplug_streak: true },
    },
  },

  {
    // status=Not charging 的字面含义是「有充电器但没在充」，正是停充后的样子，
    // 不能据此还原，否则停充永远维持不住
    name: "停充后 status=Not charging 且 online=0 → 不判定拔线",
    sysfs: {
      "battery/capacity": "100",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "0",
    },
    config: { ...FAST, power_stop: "100", power_start: "95", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", battery_switch: "", unplug_streak: "1" },
    activeSwitch: true,
    expect: {
      node: "1",
      files: { power_switch: true, unplug_streak: false },
    },
  },

  {
    // 线还插着时 present 通常仍为 1，即使输入被 suspend
    name: "停充后 usb/present=1 → 不判定拔线",
    sysfs: {
      "battery/capacity": "100",
      "battery/status": "Discharging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "0",
      "usb/present": "1",
    },
    config: { ...FAST, power_stop: "100", power_start: "95", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", battery_switch: "", unplug_streak: "1" },
    activeSwitch: true,
    expect: {
      node: "1",
      files: { power_switch: true, unplug_streak: false },
    },
  },

  {
    name: "电量降到恢复阈值以下 → 恢复充电",
    sysfs: {
      "battery/capacity": "70",
      // 停充中的机型 status 常报 Not charging，恢复判定不能依赖它
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", battery_switch: "" },
    activeSwitch: true,
    expect: {
      node: "0",
      files: { power_switch: false, battery_switch: false },
      descIncludes: "充电中",
    },
  },

  {
    name: "时段停充：当前在时段内 → 停充",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: {
      ...FAST,
      power_stop: "80",
      power_start: "75",
      temperature_switch: "0",
      power_stop_schedule: SCHEDULE_NOW_INSIDE,
    },
    node: { initial: "0", stop: "1", start: "0" },
    expect: { node: "1", files: { power_switch: true }, descIncludes: "已停充" },
  },

  {
    name: "时段停充：当前在时段外 → 不停充",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: {
      ...FAST,
      power_stop: "80",
      power_start: "75",
      temperature_switch: "0",
      power_stop_schedule: SCHEDULE_NOW_OUTSIDE,
    },
    node: { initial: "0", stop: "1", start: "0" },
    expect: { node: "0", files: { power_switch: false }, descIncludes: "充电中" },
  },

  {
    name: "wireless_policy=ignore 且无线供电 → 不触发停充",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "0",
      "wireless/online": "1",
    },
    config: {
      ...FAST,
      power_stop: "80",
      power_start: "75",
      temperature_switch: "0",
      wireless_policy: "ignore",
    },
    node: { initial: "0", stop: "1", start: "0" },
    expect: { node: "0", files: { power_switch: false } },
  },

  {
    // 写入成功但没真停下来的节点要自动回滚，不能留在停充值上
    name: "节点写入成功但仍在充电 → 回滚该节点并标记停充可能未生效",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Charging",
      "battery/temp": COOL,
      // 电流仍很大 → qsc_charge_looks_stopped 为假
      "battery/current_now": "1500000",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "0", stop: "1", start: "0" },
    expect: {
      node: "0",
      files: { power_switch: false, stop_fail_hint: true, no_node_logged: true },
      // 简介里 no_node_logged 的分支在 stop_fail_hint 之前返回
      descIncludes: "停充节点无效",
    },
  },

  {
    name: "总开关关闭 → 不停充",
    sysfs: {
      "battery/capacity": "95",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "0", stop: "1", start: "0" },
    data: { off_qsc: "" },
    expect: {
      node: "0",
      files: { power_switch: false },
      descIncludes: "已关闭",
    },
  },

  {
    // 曾经的严重 bug：停充生效时去关模块，恢复流程被 off_qsc 门禁跳过，
    // 节点永远停在停充值上，手机再也充不进电
    name: "停充中关掉总开关 → 先还原节点再罢工",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    data: { off_qsc: "", power_switch: "", battery_switch: "" },
    activeSwitch: true,
    expect: {
      node: "0",
      files: { power_switch: false, battery_switch: false, resume_fail_hint: false },
      descIncludes: "已关闭",
      logIncludes: "模块已关闭，还原充电节点",
    },
  },

  {
    name: "关掉总开关但还原失败 → 保留标记并在简介里报警",
    sysfs: {
      "battery/capacity": "85",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    // 节点文件不存在 → 写入被 [ -f ] 跳过 → start_ok 恒为 0
    node: { initial: "1", stop: "1", start: "0", missing: true },
    data: { off_qsc: "", power_switch: "" },
    expect: {
      files: { power_switch: true, resume_fail_hint: true },
      // 这条必须盖过「已关闭」，否则用户永远看不到真正的原因
      descIncludes: "恢复充电失败",
    },
  },

  {
    name: "电量低于安全线 → 忽略温控停充强制恢复",
    sysfs: {
      "battery/capacity": "15",
      "battery/status": "Not charging",
      // 45°C，仍高于温控恢复线 40°C，正常逻辑不会恢复
      "battery/temp": "450",
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: {
      ...FAST,
      power_stop: "80",
      power_start: "75",
      temperature_switch: "1",
      temperature_switch_stop: "45",
      temperature_switch_start: "40",
    },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", temp_switch: "" },
    activeSwitch: true,
    expect: {
      node: "0",
      files: { power_switch: false, temp_switch: false },
      logIncludes: "已低于安全线",
    },
  },

  {
    name: "电量低于安全线 → 忽略按 App 停充强制恢复",
    sysfs: {
      "battery/capacity": "15",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: {
      ...FAST,
      power_stop: "80",
      power_start: "75",
      temperature_switch: "0",
      app_stop: "1",
      // 宿主机上必然有 sh 进程，等于让 App 命中判定恒为真
      app_stop_list: "sh",
    },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", app_stop_flag: "" },
    activeSwitch: true,
    expect: {
      node: "0",
      files: { power_switch: false, app_stop_flag: false },
      logIncludes: "已低于安全线",
    },
  },

  {
    // 安全线只放行温控与 App 两个 latch，不能推翻用户自己设的电量阈值
    name: "安全线不越权：电量停充阈值由用户设定时仍维持停充",
    sysfs: {
      "battery/capacity": "15",
      "battery/status": "Not charging",
      "battery/temp": COOL,
      "battery/current_now": "0",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "20", power_start: "10", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    data: { power_switch: "", battery_switch: "" },
    activeSwitch: true,
    expect: {
      node: "1",
      files: { power_switch: true },
      descIncludes: "已停充",
    },
  },

  {
    // 节点停在停充值但标记已丢失：没有任何常规流程会管它
    name: "残留停充节点（无标记）→ 开机首轮回收",
    sysfs: {
      "battery/capacity": "50",
      "battery/status": "Charging",
      "battery/temp": COOL,
      "battery/current_now": "500000",
      "usb/online": "1",
    },
    config: { ...FAST, power_stop: "80", power_start: "75", temperature_switch: "0" },
    node: { initial: "1", stop: "1", start: "0" },
    expect: {
      node: "0",
      files: { power_switch: false, ".orphan_checked": true },
      logIncludes: "发现残留停充节点",
    },
  },
];
