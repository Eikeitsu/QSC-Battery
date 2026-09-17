use std::time::{Duration, Instant};

use crate::common::{
    parse_secs, BatterySnapshot, UeventSocket, EXIT_OK, EXIT_UNUSABLE, RECV_BUF, RECV_MIN_TIMEOUT,
    WAIT_FLOOR_DEFAULT, WAIT_MAX_CAP, WAIT_MAX_DEFAULT,
};

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
}

impl Thresholds {
    /// 没有任何阈值时退化成 wait-event：任何 power_supply 事件都叫醒 shell
    pub(crate) fn is_empty(&self) -> bool {
        self.stop.is_none() && self.temp_stop.is_none()
    }

    /// 命中 power_supply 事件且应叫醒 shell 时的原因；否则 None 表示继续等
    pub(crate) fn wake_reason(&self, plugged_at_start: bool) -> Option<&'static str> {
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
        return EXIT_OK;
    }
    let Some(sock) = UeventSocket::open() else {
        eprintln!("qscd: reason=netlink_open");
        return EXIT_UNUSABLE;
    };
    let plugged_at_start = BatterySnapshot::read(&th.root).plugged;
    let deadline = Instant::now() + Duration::from_secs(remaining);
    let mut buf = [0u8; RECV_BUF];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left < RECV_MIN_TIMEOUT {
            return EXIT_OK;
        }
        match sock.poll_once(&mut buf, left) {
            // 命中电池事件：只有确实需要 shell 干活时才返回
            Ok(Some(true)) => {
                if th.wake_reason(plugged_at_start).is_some() {
                    if sock.drain_event_burst(&mut buf).is_err() {
                        eprintln!("qscd: reason=event_drain");
                        return EXIT_UNUSABLE;
                    }
                    // 精简：正常叫醒路径不再额外写 wake=* 的高频 stderr 日志，
                    // 只保留 exit code；异常原因继续输出，便于运维定位。
                    return EXIT_OK;
                }
            }
            Ok(Some(false)) | Ok(None) => {}
            Err(_) => {
                eprintln!("qscd: reason=netlink_recv");
                return EXIT_UNUSABLE;
            }
        }
    }
}
