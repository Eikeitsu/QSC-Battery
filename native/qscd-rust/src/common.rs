use std::time::{Duration, Instant};

pub(crate) const NETLINK_KOBJECT_UEVENT: libc::c_int = 15;
pub(crate) const RECV_BUF: usize = 8192;
/// 剩余时间不足这么点就直接收工，避免极短的 poll 超时造成忙等。
pub(crate) const RECV_MIN_TIMEOUT: Duration = Duration::from_millis(1);

pub(crate) const EXIT_OK: u8 = 0;
pub(crate) const EXIT_UNUSABLE: u8 = 2;
pub(crate) const EXIT_NO_HIT: u8 = 1;

pub(crate) const WAIT_MAX_CAP: u64 = 3600;
pub(crate) const WAIT_MAX_DEFAULT: u64 = 30;
pub(crate) const WAIT_FLOOR_DEFAULT: u64 = 3;

/// 内核 uevent 组播套接字。Drop 时关闭 fd。
pub(crate) struct UeventSocket {
    fd: libc::c_int,
}

impl UeventSocket {
    pub(crate) fn open() -> Option<Self> {
        // SAFETY: 仅以常量参数调用 socket(2)，不涉及指针；失败返回 -1。
        let fd = unsafe {
            libc::socket(
                libc::AF_NETLINK,
                libc::SOCK_DGRAM | libc::SOCK_CLOEXEC,
                NETLINK_KOBJECT_UEVENT,
            )
        };
        if fd < 0 {
            return None;
        }
        // 提前建好，后续任何早退都会经 Drop 关闭 fd
        let sock = Self { fd };

        // SAFETY: sockaddr_nl 是纯 POD，全零是合法初值。
        let mut addr: libc::sockaddr_nl = unsafe { std::mem::zeroed() };
        addr.nl_family = libc::AF_NETLINK as u16;
        addr.nl_pid = 0; // 交给内核分配，避免与其它监听者冲突
        addr.nl_groups = 1; // 组 1 = kobject uevent 广播

        let addr_ptr = &addr as *const libc::sockaddr_nl as *const libc::sockaddr;
        let addr_len = std::mem::size_of::<libc::sockaddr_nl>() as libc::socklen_t;
        // SAFETY: addr 已完全初始化，长度取自其自身类型。
        let rc = unsafe { libc::bind(sock.fd, addr_ptr, addr_len) };
        if rc < 0 {
            return None;
        }

        // wait/watch 通过 poll 按剩余时间控制阻塞，这里不预设 socket 超时
        Some(sock)
    }

    pub(crate) fn raw_fd(&self) -> libc::c_int {
        self.fd
    }

    pub(crate) fn set_recv_timeout(&self, dur: Duration) -> Option<()> {
        let tv = libc::timeval {
            tv_sec: dur.as_secs() as libc::time_t,
            tv_usec: dur.subsec_micros() as libc::suseconds_t,
        };
        let tv_ptr = &tv as *const libc::timeval as *const libc::c_void;
        let tv_len = std::mem::size_of::<libc::timeval>() as libc::socklen_t;
        // SAFETY: tv 已完全初始化，长度取自其自身类型。
        let rc = unsafe {
            libc::setsockopt(self.fd, libc::SOL_SOCKET, libc::SO_RCVTIMEO, tv_ptr, tv_len)
        };
        if rc < 0 {
            None
        } else {
            Some(())
        }
    }

    /// 非阻塞收一包：Some(true)=power_supply；Some(false)=其它；None=暂无数据
    pub(crate) fn recv_nonblock(&self, buf: &mut [u8]) -> std::io::Result<Option<bool>> {
        let ptr = buf.as_mut_ptr() as *mut libc::c_void;
        // SAFETY: ptr 与长度来自同一 buf
        let n = unsafe { libc::recv(self.fd, ptr, buf.len(), libc::MSG_DONTWAIT) };
        if n > 0 {
            return Ok(Some(is_power_supply_event(&buf[..n as usize])));
        }
        if n == 0 {
            return Ok(Some(false));
        }
        let err = std::io::Error::last_os_error();
        match err.raw_os_error() {
            Some(libc::EAGAIN) | Some(libc::EINTR) => Ok(None),
            _ => Err(err),
        }
    }

    /// 先用 poll 明确控制超时，再接收一个 uevent。
    ///
    /// Android 部分内核对 netlink socket 的 SO_RCVTIMEO 行为并不稳定，
    /// 不能只依赖 recv 自身超时，否则 service 可能永远卡在第一轮。
    /// Ok(Some(true))=命中 power_supply 事件；Ok(Some(false))=其它事件；
    /// Ok(None)=接收超时或被信号打断；Err=套接字不可用
    pub(crate) fn poll_once(
        &self,
        buf: &mut [u8],
        timeout: Duration,
    ) -> std::io::Result<Option<bool>> {
        let timeout_ms = timeout.as_millis().clamp(1, i32::MAX as u128) as libc::c_int;
        let mut descriptor = libc::pollfd {
            fd: self.fd,
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: descriptor 指向一个有效的 pollfd，数量为 1。
        let ready = unsafe { libc::poll(&mut descriptor, 1, timeout_ms) };
        if ready == 0 {
            return Ok(None);
        }
        if ready < 0 {
            let err = std::io::Error::last_os_error();
            return if err.raw_os_error() == Some(libc::EINTR) {
                Ok(None)
            } else {
                Err(err)
            };
        }
        self.recv_nonblock(buf)
    }

    /// 命中一个事件后短暂排空同一波事件，避免充电器一次状态变化唤醒多轮 shell。
    pub(crate) fn drain_event_burst(&self, buf: &mut [u8]) -> std::io::Result<()> {
        let deadline = Instant::now() + Duration::from_millis(50);
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            if left < RECV_MIN_TIMEOUT {
                return Ok(());
            }
            match self.poll_once(buf, left)? {
                Some(_) => {}
                None => return Ok(()),
            }
        }
    }
}

impl Drop for UeventSocket {
    fn drop(&mut self) {
        // SAFETY: fd 由本类型独占，Drop 只会执行一次。
        unsafe { libc::close(self.fd) };
    }
}

pub(crate) fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() || haystack.len() < needle.len() {
        return false;
    }
    haystack.windows(needle.len()).any(|w| w == needle)
}

pub(crate) fn is_power_supply_event(payload: &[u8]) -> bool {
    let mut subsystem = false;
    let mut power_path = false;
    let mut supply_name = false;

    for field in payload.split(|byte| *byte == 0) {
        if field == b"SUBSYSTEM=power_supply" {
            subsystem = true;
        } else if let Some(path) = field.strip_prefix(b"DEVPATH=") {
            power_path = contains(path, b"/power_supply/");
        } else if let Some(name) = field.strip_prefix(b"POWER_SUPPLY_NAME=") {
            supply_name = !name.is_empty();
        }
    }

    subsystem && (power_path || supply_name)
}

#[cfg(test)]
pub(crate) fn wait_event(max_secs: u64, floor_secs: u64) -> u8 {
    wait_event_with_wake(max_secs, floor_secs, &[])
}

pub(crate) fn wait_event_with_wake(max_secs: u64, floor_secs: u64, wake_files: &[String]) -> u8 {
    use crate::wake::{poll_uevent_or_wake, WakeSource, WakeWatch};

    let floor = floor_secs.min(max_secs);
    if floor > 0 {
        std::thread::sleep(Duration::from_secs(floor));
    }
    let remaining = max_secs.saturating_sub(floor);
    if remaining == 0 {
        return EXIT_OK;
    }

    let Some(sock) = UeventSocket::open() else {
        eprintln!("qscd: reason=netlink_open");
        return EXIT_UNUSABLE;
    };
    let wake = WakeWatch::open(wake_files);

    let deadline = Instant::now() + Duration::from_secs(remaining);
    let mut buf = [0u8; RECV_BUF];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left < RECV_MIN_TIMEOUT {
            return EXIT_OK;
        }
        match poll_uevent_or_wake(&sock, wake.as_ref(), &mut buf, left) {
            Ok(WakeSource::File) | Ok(WakeSource::Power) => {
                if sock.drain_event_burst(&mut buf).is_err() {
                    eprintln!("qscd: reason=event_drain");
                    return EXIT_UNUSABLE;
                }
                return EXIT_OK;
            }
            Ok(WakeSource::Timeout) => {
                if std::env::var_os("QSCD_DEBUG").is_some() {
                    eprintln!("qscd: wake=timeout 等待超时，继续监听供电事件");
                }
            }
            Err(_) => {
                eprintln!("qscd: reason=netlink_recv");
                return EXIT_UNUSABLE;
            }
        }
    }
}

/// 单行 sysfs 读取；读不到返回 None，并去掉首尾空白
pub(crate) fn read_text(path: &str) -> Option<String> {
    Some(std::fs::read_to_string(path).ok()?.trim().to_string())
}

pub(crate) fn read_int(path: &str) -> Option<i64> {
    read_text(path)?.parse::<i64>().ok()
}

/// 温度归一化：与 shell 侧 qsc_normalize_temperature 同一套换算
pub(crate) fn normalize_temp(raw: i64) -> Option<i64> {
    let abs = raw.abs();
    let v = if abs >= 10_000 {
        raw / 1000
    } else if abs >= 1000 {
        raw / 100
    } else if abs >= 100 {
        raw / 10
    } else {
        raw
    };
    if (-20..=100).contains(&v) {
        Some(v)
    } else {
        None
    }
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum SnapshotSource {
    Battery,
    Bms,
    Soc,
    Missing,
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum SnapshotFailure {
    None,
    LevelMissing,
    TemperatureMissing,
    StatusMissing,
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct BatterySnapshot {
    pub(crate) level: Option<i64>,
    pub(crate) temp: Option<i64>,
    pub(crate) status: Option<String>,
    pub(crate) plugged: bool,
    pub(crate) source: SnapshotSource,
    pub(crate) failure: SnapshotFailure,
}

impl BatterySnapshot {
    pub(crate) fn read(root: &str) -> Self {
        let base = format!("{root}/sys/class/power_supply");
        let mut level = None;
        let mut source = SnapshotSource::Missing;
        for (path, candidate) in [
            (format!("{base}/battery/capacity"), SnapshotSource::Battery),
            (format!("{base}/bms/capacity"), SnapshotSource::Bms),
            (format!("{base}/battery/soc"), SnapshotSource::Soc),
        ] {
            if let Some(value) = read_int(&path) {
                level = Some(value);
                source = candidate;
                break;
            }
        }
        let temp = [
            format!("{base}/battery/temp"),
            format!("{base}/bms/temp"),
            format!("{base}/battery/batt_temp"),
        ]
        .into_iter()
        .find_map(|path| read_int(&path).and_then(normalize_temp));
        let status = read_text(&format!("{base}/battery/status"))
            .or_else(|| read_text(&format!("{base}/bms/status")));
        let failure = if level.is_none() {
            SnapshotFailure::LevelMissing
        } else if temp.is_none() {
            SnapshotFailure::TemperatureMissing
        } else if status.is_none() {
            SnapshotFailure::StatusMissing
        } else {
            SnapshotFailure::None
        };
        Self {
            level,
            temp,
            status,
            plugged: PowerState::read(root).plugged,
            source,
            failure,
        }
    }
}

/// 与 shell 侧 `qsc_ps_plugged` 对齐的最小电源状态。
///
/// MCA 停充后 `usb/online` 常为 0；`present` 需 VBUS/类型旁证。
/// 孤立 `Not charging` / 孤立 `present` 不判插电（K90U 未插电待机常见）。
#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct PowerState {
    pub(crate) plugged: bool,
}

impl PowerState {
    fn vbus_live(base: &str) -> bool {
        match read_int(&format!("{base}/usb/voltage_now")) {
            Some(v) if v > 3_000_000 => true,
            Some(v) if v > 3_000 && v < 100_000 => true,
            _ => false,
        }
    }

    fn type_live(base: &str) -> bool {
        for path in [format!("{base}/usb/real_type"), format!("{base}/usb/type")] {
            if let Some(value) = read_text(&path) {
                if !matches!(value.as_str(), "" | "Unknown" | "UNKNOWN" | "None" | "NONE") {
                    return true;
                }
            }
        }
        false
    }

    fn looks_discharging(base: &str) -> bool {
        // 与 shell qsc_ps_looks_discharging 对齐：仅 Discharging + |I|>10mA
        let st = read_text(&format!("{base}/battery/status")).unwrap_or_default();
        if !matches!(st.as_str(), "Discharging" | "discharging") {
            return false;
        }
        for name in ["battery", "bms", "soc"] {
            if let Some(cur) = read_int(&format!("{base}/{name}/current_now")) {
                return cur.unsigned_abs() > 10_000;
            }
        }
        false
    }

    fn charging_current_live(base: &str) -> bool {
        for name in ["battery", "bms", "soc"] {
            if let Some(cur) = read_int(&format!("{base}/{name}/current_now")) {
                return cur.unsigned_abs() >= 150_000;
            }
        }
        false
    }

    pub(crate) fn read(root: &str) -> Self {
        let base = format!("{root}/sys/class/power_supply");

        for name in ["usb", "qc_usb", "ac", "dc", "wireless", "charger"] {
            if read_int(&format!("{base}/{name}/online")) == Some(1) {
                return Self { plugged: true };
            }
        }
        if read_int(&format!("{base}/battery/charger_online")) == Some(1) {
            return Self { plugged: true };
        }

        for name in ["usb", "qc_usb", "wireless", "ac"] {
            if read_int(&format!("{base}/{name}/present")) == Some(1) {
                // VBUS/类型优先：停充后会放电，不能先因放电否决真插电
                if Self::vbus_live(&base) || Self::type_live(&base) {
                    return Self { plugged: true };
                }
                if Self::looks_discharging(&base) {
                    continue;
                }
            }
        }

        // 类型 / VBUS 是强证据（与 shell 一致，不因放电否决）
        if Self::type_live(&base) {
            return Self { plugged: true };
        }
        if Self::vbus_live(&base) {
            return Self { plugged: true };
        }

        if matches!(
            read_text(&format!("{base}/battery/status")).as_deref(),
            Some("Charging" | "Full")
        ) {
            if read_int(&format!("{base}/battery/online")) == Some(1) {
                return Self { plugged: true };
            }
            if Self::charging_current_live(&base) {
                return Self { plugged: true };
            }
        }

        if matches!(
            read_text(&format!("{base}/battery/status")).as_deref(),
            Some("Not charging" | "Notcharging" | "not_charging")
        ) && Self::charging_current_live(&base)
        {
            return Self { plugged: true };
        }

        Self::default()
    }
}

pub(crate) fn parse_secs(arg: Option<&str>, default: u64, max: u64) -> u64 {
    arg.and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(default)
        .min(max)
}
