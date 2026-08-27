/**
 * 停充决策层的行为用例。
 *
 * 每条用例把假的 sysfs 电池节点、假的停充开关节点和一份 config.conf 摆好，
 * 跑一次真正的 bin/qsc_switch.sh，然后断言「有没有停充、写了什么值、状态标记
 * 与简介对不对」。这里只覆盖判定，不碰机型探测与电流控制。
 *
 * 尚未覆盖：按 App 停充。它要造出能被 ps 匹配到的前台进程，得先给
 * qsc_pkg_list_hit 留一个可注入的进程列表来源。
 *
 * 字段说明
 *   sysfs   假 /sys/class/power_supply 下的文件，键是相对路径
 *   config  追加到 config.conf 末尾的覆盖项（后出现的键生效）
 *   data    预置的 data/ 标记文件，值为文件内容
 *   node    注入的停充开关节点：initial=初值，stop/start=写入值
 *   expect  断言
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
    data: { power_switch: "", battery_switch: "" },
    // 停充成功后模块会记下生效的条目，恢复时优先照它回写
    activeSwitch: true,
    expect: {
      node: "0",
      files: { power_switch: false, battery_switch: false },
      descIncludes: "未充电",
      logIncludes: "已拔出充电器",
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
];
