use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crate::common::{
    parse_secs, read_int, read_text, BatterySnapshot, UeventSocket, EXIT_OK, EXIT_UNUSABLE,
    RECV_BUF, RECV_MIN_TIMEOUT, WAIT_FLOOR_DEFAULT, WAIT_MAX_CAP, WAIT_MAX_DEFAULT,
};
use crate::wake::{poll_uevent_or_wake, WakeSource, WakeWatch};

/// watch 的阈值参数。None = 该项不参与判断
#[derive(Default, Debug, PartialEq)]
pub(crate) struct Thresholds {
    /// 停充电量（%）
    pub(crate) stop: Option<i64>,
    /// 「接近阈值」窗口（%）：电量 >= stop - near 就该叫醒 shell
    pub(crate) near: i64,
    /// 停充温度（°C）
    pub(crate) temp_stop: Option<i64>,
    /// 假 sysfs 根，仅测试用；线上为空
    pub(crate) root: String,
    /// 旁路唤醒文件（如 qsc_xp_viewer）；内容变化即叫醒
    pub(crate) wake_files: Vec<String>,
    /// 插电停充维持：稳态噪声不叫醒；超时若仍稳则写 .qscd_maintain_stable=1
    pub(crate) maintain: bool,
    /// power_switch 标记路径（maintain 用）
    pub(crate) marker: String,
    /// active_switch 文件路径（path,start=X,stop=Y）
    pub(crate) active_switch: String,
    /// 写 .qscd_maintain_stable 的目录
    pub(crate) datadir: String,
}

impl Thresholds {
    /// 没有任何阈值时退化成 wait-event：任何 power_supply 事件都叫醒 shell
    pub(crate) fn is_empty(&self) -> bool {
        !self.maintain && self.stop.is_none() && self.temp_stop.is_none()
    }

    fn sys_path(&self, abs: &str) -> PathBuf {
        if self.root.is_empty() {
            PathBuf::from(abs)
        } else if let Some(rest) = abs.strip_prefix('/') {
            Path::new(&self.root).join(rest)
        } else {
            Path::new(&self.root).join(abs)
        }
    }

    /// 与 shell `qsc_charge_looks_stopped` 对齐的粗判。
    /// `current_now` 可能是 mA（|I|<10000）或 µA；小米充电多为负。
    /// MCA/K90U 充电中也常报 Not charging，负向大电流视为未停住。
    pub(crate) fn charge_looks_stopped(root: &str, status: Option<&str>) -> bool {
        let base = format!("{root}/sys/class/power_supply");
        let raw = ["battery", "bms", "soc"]
            .into_iter()
            .find_map(|n| read_int(&format!("{base}/{n}/current_now")));
        let (signed_ua, abs_ua) = match raw {
            Some(c) => {
                let abs = c.unsigned_abs();
                let abs_ua = if abs > 0 && abs < 10_000 {
                    abs.saturating_mul(1000)
                } else {
                    abs
                };
                let signed = if c < 0 {
                    -(abs_ua as i64)
                } else {
                    abs_ua as i64
                };
                (signed, abs_ua)
            }
            None => (0_i64, 0_u64),
        };
        match status.unwrap_or("") {
            "Discharging" | "discharging" => true,
            "Not charging" | "Notcharging" | "not_charging" | "Full" | "full" => {
                if abs_ua < 80_000 {
                    true
                } else if signed_ua <= -150_000 {
                    // 负向大电流：仍在从适配器取电
                    false
                } else {
                    // 正向大电流：多为停充后负载放电
                    true
                }
            }
            "Charging" | "charging" => abs_ua < 80_000,
            _ => abs_ua < 80_000,
        }
    }

    /// active_switch 节点是否仍停在 stop 值
    pub(crate) fn active_stop_node_holds(&self) -> bool {
        if self.active_switch.is_empty() {
            return false;
        }
        let Some(entry) = read_text(&self.active_switch) else {
            return false;
        };
        // path,start=X,stop=Y
        let Some((route, rest)) = entry.split_once(",start=") else {
            return false;
        };
        let Some((_start, stop)) = rest.split_once(",stop=") else {
            return false;
        };
        let stop = stop.replace('_', " ");
        if route.is_empty() || stop.is_empty() {
            return false;
        }
        let path = self.sys_path(route);
        let Some(cur) = read_text(&path.to_string_lossy()) else {
            return false;
        };
        cur == stop
    }

    /// 维持态是否仍稳：有标记、仍插电、节点 hold、看起来已停充
    pub(crate) fn is_maintain_stable(&self) -> bool {
        if !self.maintain || self.marker.is_empty() {
            return false;
        }
        if !Path::new(&self.marker).is_file() {
            return false;
        }
        let snap = BatterySnapshot::read(&self.root);
        if !snap.plugged {
            return false;
        }
        if !self.active_stop_node_holds() {
            return false;
        }
        Self::charge_looks_stopped(&self.root, snap.status.as_deref())
    }

    pub(crate) fn write_maintain_stable(&self, stable: bool) {
        if self.datadir.is_empty() {
            return;
        }
        let path = Path::new(&self.datadir).join(".qscd_maintain_stable");
        let _ = std::fs::create_dir_all(&self.datadir);
        let _ = std::fs::write(path, if stable { "1\n" } else { "0\n" });
    }

    /// 命中 power_supply 事件且应叫醒 shell 时的原因；否则 None 表示继续等
    pub(crate) fn wake_reason(&self, plugged_at_start: bool) -> Option<&'static str> {
        if self.maintain {
            if self.marker.is_empty() || !Path::new(&self.marker).is_file() {
                return Some("no_marker");
            }
            let snapshot = BatterySnapshot::read(&self.root);
            if snapshot.plugged != plugged_at_start {
                return Some("plug_changed");
            }
            if !self.is_maintain_stable() {
                return Some("unstable");
            }
            // 稳态：吞掉电流/温度噪声事件
            return None;
        }
        if self.is_empty() {
            return Some("event");
        }
        let snapshot = BatterySnapshot::read(&self.root);
        if snapshot.plugged != plugged_at_start {
            return Some("plug_changed");
        }
        if let (Some(stop), Some(level)) = (self.stop, snapshot.level) {
            if level >= stop - self.near {
                return Some("near_level");
            }
        }
        if let (Some(ts), Some(temp)) = (self.temp_stop, snapshot.temp) {
            if temp >= ts - 3 {
                return Some("near_temp");
            }
        }
        None
    }
}

/// 解析 watch 的命名参数。无法识别的参数一律忽略，便于旧二进制配新脚本
pub(crate) fn parse_watch_args(args: &[String]) -> (u64, u64, Thresholds) {
    let mut max = WAIT_MAX_DEFAULT;
    let mut floor = WAIT_FLOOR_DEFAULT;
    let mut th = Thresholds {
        near: 3,
        ..Default::default()
    };
    let mut i = 0;
    while i < args.len() {
        let key = args[i].as_str();
        let val = args.get(i + 1).map(String::as_str);
        match key {
            "--max" => max = parse_secs(val, WAIT_MAX_DEFAULT, WAIT_MAX_CAP),
            "--floor" => floor = parse_secs(val, WAIT_FLOOR_DEFAULT, WAIT_MAX_CAP),
            "--stop" => th.stop = val.and_then(|v| v.trim().parse::<i64>().ok()),
            "--near" => th.near = val.and_then(|v| v.trim().parse::<i64>().ok()).unwrap_or(3),
            "--temp-stop" => th.temp_stop = val.and_then(|v| v.trim().parse::<i64>().ok()),
            "--sysfs-root" => th.root = val.unwrap_or("").trim_end_matches('/').to_string(),
            "--wake-file" => {
                if let Some(v) = val {
                    let p = v.trim();
                    if !p.is_empty() {
                        th.wake_files.push(p.to_string());
                    }
                }
            }
            "--maintain" => {
                th.maintain = true;
                // 允许裸 flag 或 --maintain 1
                if val.is_some_and(|v| matches!(v.trim(), "0" | "1" | "true" | "false")) {
                    th.maintain = !matches!(val.unwrap().trim(), "0" | "false");
                    i += 2;
                    continue;
                }
                i += 1;
                continue;
            }
            "--marker" => th.marker = val.unwrap_or("").trim().to_string(),
            "--active-switch" => th.active_switch = val.unwrap_or("").trim().to_string(),
            "--datadir" => th.datadir = val.unwrap_or("").trim().to_string(),
            _ => {
                i += 1;
                continue;
            }
        }
        i += 2;
    }
    // 阈值 >100 是 shell 侧表示「关闭电量停充」的约定，别参与判断
    if th.stop.is_some_and(|s| s > 100) {
        th.stop = None;
    }
    th.near = th.near.clamp(0, 20);
    (max, floor.min(max), th)
}

pub(crate) fn watch(max_secs: u64, floor_secs: u64, th: &Thresholds) -> u8 {
    if floor_secs > 0 {
        std::thread::sleep(Duration::from_secs(floor_secs));
    }
    let remaining = max_secs.saturating_sub(floor_secs);
    if remaining == 0 {
        if th.maintain {
            let stable = th.is_maintain_stable();
            th.write_maintain_stable(stable);
            eprintln!(
                "qscd: wake={}",
                if stable {
                    "maintain_stable"
                } else {
                    "maintain_need"
                }
            );
        }
        return EXIT_OK;
    }
    let Some(sock) = UeventSocket::open() else {
        eprintln!("qscd: reason=netlink_open");
        return EXIT_UNUSABLE;
    };
    let wake = WakeWatch::open(&th.wake_files);
    let plugged_at_start = BatterySnapshot::read(&th.root).plugged;
    let deadline = Instant::now() + Duration::from_secs(remaining);
    let mut buf = [0u8; RECV_BUF];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left < RECV_MIN_TIMEOUT {
            if th.maintain {
                let stable = th.is_maintain_stable();
                th.write_maintain_stable(stable);
                eprintln!(
                    "qscd: wake={}",
                    if stable {
                        "maintain_stable"
                    } else {
                        "maintain_need"
                    }
                );
            }
            return EXIT_OK;
        }
        match poll_uevent_or_wake(&sock, wake.as_ref(), &mut buf, left) {
            Ok(WakeSource::File) => {
                if th.maintain {
                    th.write_maintain_stable(false);
                }
                eprintln!("qscd: wake=file");
                return EXIT_OK;
            }
            Ok(WakeSource::Power) => {
                if let Some(reason) = th.wake_reason(plugged_at_start) {
                    if sock.drain_event_burst(&mut buf).is_err() {
                        eprintln!("qscd: reason=event_drain");
                        return EXIT_UNUSABLE;
                    }
                    if th.maintain {
                        th.write_maintain_stable(false);
                    }
                    eprintln!("qscd: wake={reason}");
                    return EXIT_OK;
                }
                // maintain 稳态：吞事件继续睡
            }
            Ok(WakeSource::Timeout) => {}
            Err(_) => {
                eprintln!("qscd: reason=netlink_recv");
                return EXIT_UNUSABLE;
            }
        }
    }
}
