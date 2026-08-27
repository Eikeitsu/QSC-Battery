//! 事件等待器：阻塞在内核 power_supply uevent 上，让 shell 主循环不再需要定时唤醒。
//!
//! 用法
//!   qscd wait-event <最长秒数> [最短秒数]
//!       先睡「最短秒数」压掉事件风暴，再等 power_supply 事件直到「最长秒数」。
//!       退出 0 = 有事件或已到时（调用方跑完整一轮）
//!       退出 2 = 本机不可用（调用方应永久退回 sleep）
//!   qscd watch --max N [--floor N] [--stop N] [--near N] [--temp-stop N] [--sysfs-root DIR]
//!       同样等 power_supply 事件，但拿到事件后先自己读一遍电量/温度/插电：
//!       只有「插电状态变了」或「已接近停充阈值」才退出 0 叫醒调用方，
//!       其余事件就地吞掉继续等。目的是把充电中「离阈值还远」那段的
//!       shell 轮次整段省掉，而不牺牲跨阈值的及时性。
//!       不给任何阈值时行为等同 wait-event。
//!       退出 0 = 该跑一轮；退出 2 = 不可用（调用方应退回 sleep）
//!   qscd pkgs <包名列表文件> [--proc-root DIR]
//!       遍历 /proc/<pid>/cmdline 判断列表里的包有没有在跑主进程。
//!       替代 shell 侧的 `ps -ef` 全量快照 + 逐包 grep（按 App 停充开启后
//!       最贵的周期性动作）。只读 /proc，不涉及任何充电节点。
//!       退出 0 = 有包在跑；1 = 都没在跑；2 = 不可用（调用方应退回 ps）
//!   qscd probe
//!       安装时自检：能建起 netlink 套接字则退出 0。
//!   qscd features
//!       打印本二进制支持的扩展子命令，供 shell 一次性问清能力。
//!       C 版不认这个子命令（退出 2），即视为无扩展能力。
//!
//! 设计约束：本程序不写任何充电节点，也不做停充/恢复决策，只负责「等」与
//! 「该不该叫醒 shell」。阈值判定的唯一真理仍在 shell 里——sh 版主包没有本
//! 二进制也必须行为一致。因此它异常退出时最坏结果是退化成定时轮询。

use std::env;
use std::process::ExitCode;
use std::time::{Duration, Instant};

/// 支持的扩展子命令；features 子命令原样打印
const FEATURES: &str = "watch pkgs";

const NETLINK_KOBJECT_UEVENT: libc::c_int = 15;
/// 内核 uevent 载荷里的匹配串；命中即认为电池状态可能变了
const MATCH: &[u8] = b"SUBSYSTEM=power_supply";
const RECV_BUF: usize = 8192;
/// 剩余时间不足这么点就直接收工：SO_RCVTIMEO 传 0 表示「永不超时」，
/// 把不足 1ms 的余量四舍五入成 0 会让本进程永久挂死在 recv 上
const RECV_MIN_TIMEOUT: Duration = Duration::from_millis(1);

const EXIT_OK: u8 = 0;
const EXIT_UNUSABLE: u8 = 2;

const WAIT_MAX_CAP: u64 = 3600;
const WAIT_MAX_DEFAULT: u64 = 30;
const WAIT_FLOOR_DEFAULT: u64 = 3;

/// 内核 uevent 组播套接字。Drop 时关闭 fd。
struct UeventSocket {
    fd: libc::c_int,
}

impl UeventSocket {
    fn open() -> Option<Self> {
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

        // 超时由 wait_event 按剩余时间逐次设定，这里不预设
        Some(sock)
    }

    fn set_recv_timeout(&self, dur: Duration) -> Option<()> {
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

    /// Ok(true)=命中 power_supply 事件；Ok(false)=本次超时或事件无关；Err=套接字不可用
    fn poll_once(&self, buf: &mut [u8]) -> std::io::Result<bool> {
        let ptr = buf.as_mut_ptr() as *mut libc::c_void;
        // SAFETY: ptr 与长度来自同一 buf，recv 最多写入 buf.len() 字节。
        let n = unsafe { libc::recv(self.fd, ptr, buf.len(), 0) };
        if n > 0 {
            return Ok(contains(&buf[..n as usize], MATCH));
        }
        if n == 0 {
            return Ok(false);
        }
        // EAGAIN=收满超时；EINTR=被信号打断。两者都只是本次没拿到事件。
        let err = std::io::Error::last_os_error();
        match err.raw_os_error() {
            Some(libc::EAGAIN) | Some(libc::EINTR) => Ok(false),
            _ => Err(err),
        }
    }
}

impl Drop for UeventSocket {
    fn drop(&mut self) {
        // SAFETY: fd 由本类型独占，Drop 只会执行一次。
        unsafe { libc::close(self.fd) };
    }
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() || haystack.len() < needle.len() {
        return false;
    }
    haystack.windows(needle.len()).any(|w| w == needle)
}

fn wait_event(max_secs: u64, floor_secs: u64) -> u8 {
    let floor = floor_secs.min(max_secs);
    if floor > 0 {
        std::thread::sleep(Duration::from_secs(floor));
    }
    let remaining = max_secs.saturating_sub(floor);
    if remaining == 0 {
        return EXIT_OK;
    }

    let Some(sock) = UeventSocket::open() else {
        return EXIT_UNUSABLE;
    };

    let deadline = Instant::now() + Duration::from_secs(remaining);
    let mut buf = [0u8; RECV_BUF];
    loop {
        // 接收超时一次设满剩余时间：整段等待只在截止时刻醒一次。
        // 早先按固定 2 秒切片轮流复查截止时间，30 秒窗口要醒 15 次，
        // 白让 CPU 进不了深层 idle，而事件到达本来就是立即返回、与超时无关。
        let left = deadline.saturating_duration_since(Instant::now());
        if left < RECV_MIN_TIMEOUT {
            return EXIT_OK;
        }
        if sock.set_recv_timeout(left).is_none() {
            return EXIT_UNUSABLE;
        }
        match sock.poll_once(&mut buf) {
            Ok(true) => return EXIT_OK,
            // 超时或与电池无关的事件：回到循环按新的剩余时间重设超时
            Ok(false) => {}
            Err(_) => return EXIT_UNUSABLE,
        }
    }
}

/// watch 的阈值参数。None = 该项不参与判断
#[derive(Default, Debug, PartialEq)]
struct Thresholds {
    /// 停充电量（%）
    stop: Option<i64>,
    /// 「接近阈值」窗口（%）：电量 >= stop - near 就该叫醒 shell
    near: i64,
    /// 停充温度（°C）
    temp_stop: Option<i64>,
    /// 假 sysfs 根，仅测试用；线上为空
    root: String,
}

/// 单行 sysfs 读取；读不到或不是整数返回 None
fn read_int(path: &str) -> Option<i64> {
    let raw = std::fs::read_to_string(path).ok()?;
    raw.trim().parse::<i64>().ok()
}

/// 温度归一化：与 shell 侧 qsc_normalize_temperature 同一套换算
fn normalize_temp(raw: i64) -> Option<i64> {
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

impl Thresholds {
    fn ps_dir(&self) -> String {
        format!("{}/sys/class/power_supply", self.root)
    }

    fn plugged(&self) -> bool {
        let base = self.ps_dir();
        for name in ["usb", "qc_usb", "ac", "dc", "wireless"] {
            if read_int(&format!("{base}/{name}/online")) == Some(1) {
                return true;
            }
        }
        false
    }

    fn level(&self) -> Option<i64> {
        let base = self.ps_dir();
        read_int(&format!("{base}/battery/capacity"))
            .or_else(|| read_int(&format!("{base}/bms/capacity")))
            .or_else(|| read_int(&format!("{base}/battery/soc")))
    }

    fn temp(&self) -> Option<i64> {
        let base = self.ps_dir();
        let raw = read_int(&format!("{base}/battery/temp"))
            .or_else(|| read_int(&format!("{base}/bms/temp")))
            .or_else(|| read_int(&format!("{base}/battery/batt_temp")))?;
        normalize_temp(raw)
    }

    /// 没有任何阈值时退化成 wait-event：任何 power_supply 事件都叫醒 shell
    fn is_empty(&self) -> bool {
        self.stop.is_none() && self.temp_stop.is_none()
    }

    /// 拿到事件后判断值不值得叫醒 shell
    fn should_wake(&self, plugged_at_start: bool) -> bool {
        if self.is_empty() {
            return true;
        }
        // 插拔必须立刻交给 shell：停充/恢复的整套判定都在那边
        if self.plugged() != plugged_at_start {
            return true;
        }
        if let (Some(stop), Some(level)) = (self.stop, self.level()) {
            if level >= stop - self.near {
                return true;
            }
        }
        if let (Some(ts), Some(temp)) = (self.temp_stop, self.temp()) {
            // 温度涨得比电量快，留 3°C 余量，与 shell 侧收紧间隔的阈值一致
            if temp >= ts - 3 {
                return true;
            }
        }
        false
    }
}

/// 解析 watch 的命名参数。无法识别的参数一律忽略，便于旧二进制配新脚本
fn parse_watch_args(args: &[String]) -> (u64, u64, Thresholds) {
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

fn watch(max_secs: u64, floor_secs: u64, th: &Thresholds) -> u8 {
    if floor_secs > 0 {
        std::thread::sleep(Duration::from_secs(floor_secs));
    }
    let remaining = max_secs.saturating_sub(floor_secs);
    if remaining == 0 {
        return EXIT_OK;
    }
    let Some(sock) = UeventSocket::open() else {
        return EXIT_UNUSABLE;
    };
    let plugged_at_start = th.plugged();
    let deadline = Instant::now() + Duration::from_secs(remaining);
    let mut buf = [0u8; RECV_BUF];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left < RECV_MIN_TIMEOUT {
            return EXIT_OK;
        }
        if sock.set_recv_timeout(left).is_none() {
            return EXIT_UNUSABLE;
        }
        match sock.poll_once(&mut buf) {
            // 命中电池事件：只有确实需要 shell 干活时才返回
            Ok(true) => {
                if th.should_wake(plugged_at_start) {
                    return EXIT_OK;
                }
            }
            Ok(false) => {}
            Err(_) => return EXIT_UNUSABLE,
        }
    }
}

const EXIT_NO_HIT: u8 = 1;

/// 判断包名列表里有没有包在跑主进程。
/// 匹配规则是「cmdline 首字段与包名完全相等」：Android 应用主进程的 cmdline
/// 就是包名本身，子进程是 `包名:xxx`。shell 版用的是 grep 子串匹配，
/// 列表里写 `com.foo` 会连带命中 `com.foo.bar`，这里顺手收紧。
fn pkgs_running(list_path: &str, proc_root: &str) -> u8 {
    let Ok(list) = std::fs::read_to_string(list_path) else {
        // 列表读不到不算「不可用」——调用方保证它存在，读不到就是没有目标
        return EXIT_NO_HIT;
    };
    let wanted: Vec<&str> = list
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .collect();
    if wanted.is_empty() {
        return EXIT_NO_HIT;
    }
    let root = if proc_root.is_empty() {
        "/proc"
    } else {
        proc_root
    };
    let Ok(entries) = std::fs::read_dir(root) else {
        return EXIT_UNUSABLE;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        if !name.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        // 进程随时会消失，读失败是常态，跳过即可
        let Ok(raw) = std::fs::read(entry.path().join("cmdline")) else {
            continue;
        };
        let first = raw.split(|&b| b == 0).next().unwrap_or(&[]);
        let Ok(cmd) = std::str::from_utf8(first) else {
            continue;
        };
        let cmd = cmd.trim();
        if cmd.is_empty() {
            continue;
        }
        if wanted.iter().any(|w| *w == cmd) {
            return EXIT_OK;
        }
    }
    EXIT_NO_HIT
}

fn parse_secs(arg: Option<&str>, default: u64, max: u64) -> u64 {
    arg.and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(default)
        .min(max)
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("wait-event") => {
            let max = parse_secs(args.get(2).map(String::as_str), WAIT_MAX_DEFAULT, WAIT_MAX_CAP);
            let floor = parse_secs(args.get(3).map(String::as_str), WAIT_FLOOR_DEFAULT, max.max(1));
            ExitCode::from(wait_event(max, floor))
        }
        Some("watch") => {
            let (max, floor, th) = parse_watch_args(&args[2..]);
            ExitCode::from(watch(max, floor, &th))
        }
        Some("pkgs") => {
            let list = args.get(2).map(String::as_str).unwrap_or("");
            if list.is_empty() {
                eprintln!("usage: qscd pkgs <list_file> [--proc-root DIR]");
                return ExitCode::from(EXIT_UNUSABLE);
            }
            let mut root = "";
            if let Some(i) = args.iter().position(|a| a == "--proc-root") {
                root = args.get(i + 1).map(String::as_str).unwrap_or("");
            }
            ExitCode::from(pkgs_running(list, root))
        }
        Some("features") => {
            println!("{FEATURES}");
            ExitCode::from(EXIT_OK)
        }
        Some("probe") => {
            // 顺带验一次 SO_RCVTIMEO：wait_event 的截止时间全靠它
            let ok = UeventSocket::open()
                .map(|s| s.set_recv_timeout(Duration::from_secs(1)).is_some())
                .unwrap_or(false);
            if ok {
                println!("ok");
                ExitCode::from(EXIT_OK)
            } else {
                eprintln!("qscd: netlink uevent socket unavailable");
                ExitCode::from(EXIT_UNUSABLE)
            }
        }
        _ => {
            eprintln!(
                "usage: qscd wait-event <max_secs> [floor_secs]\n       \
                 qscd watch --max N [--floor N] [--stop N] [--near N] [--temp-stop N]\n       \
                 qscd pkgs <list_file> [--proc-root DIR]\n       \
                 qscd probe | qscd features"
            );
            ExitCode::from(EXIT_UNUSABLE)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contains_finds_power_supply_subsystem() {
        let payload = b"change@/devices/battery\0ACTION=change\0SUBSYSTEM=power_supply\0";
        assert!(contains(payload, MATCH));
    }

    #[test]
    fn contains_rejects_other_subsystems() {
        let payload = b"change@/devices/net\0ACTION=change\0SUBSYSTEM=net\0";
        assert!(!contains(payload, MATCH));
        assert!(!contains(b"", MATCH));
        assert!(!contains(b"short", MATCH));
    }

    #[test]
    fn parse_secs_clamps_and_defaults() {
        assert_eq!(parse_secs(None, 30, 3600), 30);
        assert_eq!(parse_secs(Some("5"), 30, 3600), 5);
        assert_eq!(parse_secs(Some(" 7 "), 30, 3600), 7);
        assert_eq!(parse_secs(Some("99999"), 30, 3600), 3600);
        assert_eq!(parse_secs(Some("abc"), 30, 3600), 30);
    }

    #[test]
    fn floor_never_exceeds_max() {
        let max = parse_secs(Some("2"), 30, 3600);
        let floor = parse_secs(Some("10"), 3, max.max(1));
        assert_eq!(max, 2);
        assert_eq!(floor, 2);
    }

    #[test]
    fn wait_event_returns_ok_when_floor_covers_max() {
        // floor >= max：只睡不建套接字，必须成功返回（不依赖 netlink 可用性）
        assert_eq!(wait_event(0, 0), EXIT_OK);
    }

    #[test]
    fn normalize_temp_matches_shell_rules() {
        assert_eq!(normalize_temp(300), Some(30));
        assert_eq!(normalize_temp(3000), Some(30));
        assert_eq!(normalize_temp(30000), Some(30));
        assert_eq!(normalize_temp(30), Some(30));
        assert_eq!(normalize_temp(9999999), None);
    }

    #[test]
    fn parse_watch_args_reads_flags_and_clamps() {
        let args: Vec<String> = ["--max", "600", "--floor", "5", "--stop", "80", "--near", "99"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let (max, floor, th) = parse_watch_args(&args);
        assert_eq!(max, 600);
        assert_eq!(floor, 5);
        assert_eq!(th.stop, Some(80));
        assert_eq!(th.near, 20);
        assert_eq!(th.temp_stop, None);
    }

    #[test]
    fn parse_watch_args_treats_stop_over_100_as_disabled() {
        // shell 侧用 >100 表示关闭电量停充
        let args: Vec<String> = ["--stop", "110"].iter().map(|s| s.to_string()).collect();
        let (_, _, th) = parse_watch_args(&args);
        assert_eq!(th.stop, None);
    }

    #[test]
    fn floor_is_capped_by_max_in_watch_args() {
        let args: Vec<String> = ["--max", "2", "--floor", "10"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let (max, floor, _) = parse_watch_args(&args);
        assert_eq!((max, floor), (2, 2));
    }

    /// 造一棵假 sysfs：返回临时根目录，由调用方负责清理。
    /// 目录名带自增序号，测试并行跑也不会互相踩
    fn fake_sysfs(files: &[(&str, &str)]) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU32, Ordering};
        static SEQ: AtomicU32 = AtomicU32::new(0);
        let n = SEQ.fetch_add(1, Ordering::Relaxed);
        let mut dir = std::env::temp_dir();
        dir.push(format!("qscd-test-{}-{n}", std::process::id()));
        let base = dir.join("sys/class/power_supply");
        for (rel, val) in files {
            let p = base.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, format!("{val}\n")).unwrap();
        }
        dir
    }

    fn th_for(root: &std::path::Path, stop: Option<i64>, temp_stop: Option<i64>) -> Thresholds {
        Thresholds {
            stop,
            near: 3,
            temp_stop,
            root: root.to_string_lossy().to_string(),
        }
    }

    #[test]
    fn should_wake_only_when_near_threshold_or_plug_changed() {
        let root = fake_sysfs(&[
            ("battery/capacity", "60"),
            ("battery/temp", "300"),
            ("usb/online", "1"),
        ]);
        let th = th_for(&root, Some(80), Some(60));
        // 插电、离阈值还远、温度也低 → 吞掉事件继续等
        assert!(!th.should_wake(true));
        // 起始状态记为未插电，现在读到插电 → 必须叫醒
        assert!(th.should_wake(false));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn should_wake_when_level_enters_near_window() {
        let root = fake_sysfs(&[
            ("battery/capacity", "78"),
            ("battery/temp", "300"),
            ("usb/online", "1"),
            ("bms/capacity", "1"),
        ]);
        // near=3，stop=80 → 78 已进入窗口
        assert!(th_for(&root, Some(80), None).should_wake(true));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn should_wake_when_temp_approaches_stop() {
        let root = fake_sysfs(&[
            ("battery/capacity", "40"),
            ("battery/temp", "580"),
            ("usb/online", "1"),
            ("bms/temp", "1"),
        ]);
        // 58°C，停充 60°C，留 3°C 余量 → 该叫醒
        assert!(th_for(&root, None, Some(60)).should_wake(true));
        std::fs::remove_dir_all(&root).ok();
    }

    /// 造一棵假 /proc：pid → cmdline 首字段
    fn fake_proc(procs: &[(&str, &str)]) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU32, Ordering};
        static SEQ: AtomicU32 = AtomicU32::new(0);
        let n = SEQ.fetch_add(1, Ordering::Relaxed);
        let mut dir = std::env::temp_dir();
        dir.push(format!("qscd-proc-{}-{n}", std::process::id()));
        for (pid, cmd) in procs {
            let p = dir.join(pid);
            std::fs::create_dir_all(&p).unwrap();
            // 真 cmdline 以 NUL 分隔并以 NUL 结尾
            std::fs::write(p.join("cmdline"), format!("{cmd}\0")).unwrap();
        }
        // 非数字目录必须被跳过
        std::fs::create_dir_all(dir.join("self")).unwrap();
        dir
    }

    fn write_list(dir: &std::path::Path, lines: &str) -> String {
        let p = dir.join("list");
        std::fs::write(&p, lines).unwrap();
        p.to_string_lossy().to_string()
    }

    #[test]
    fn pkgs_hits_only_main_process() {
        let root = fake_proc(&[
            ("1", "/system/bin/init"),
            ("222", "com.example.app:push"),
            ("333", "com.example.app"),
        ]);
        let list = write_list(&root, "com.example.app\n");
        assert_eq!(pkgs_running(&list, root.to_str().unwrap()), EXIT_OK);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn pkgs_ignores_subprocess_only() {
        let root = fake_proc(&[("1", "/system/bin/init"), ("222", "com.example.app:push")]);
        let list = write_list(&root, "com.example.app\n");
        assert_eq!(pkgs_running(&list, root.to_str().unwrap()), EXIT_NO_HIT);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn pkgs_requires_exact_package_name() {
        // shell 版的 grep 子串匹配会误命中 com.example.app.helper
        let root = fake_proc(&[("222", "com.example.app.helper")]);
        let list = write_list(&root, "com.example.app\n");
        assert_eq!(pkgs_running(&list, root.to_str().unwrap()), EXIT_NO_HIT);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn pkgs_handles_blank_lines_and_crlf() {
        let root = fake_proc(&[("222", "com.example.app")]);
        let list = write_list(&root, "\r\n  \r\ncom.example.app\r\n");
        assert_eq!(pkgs_running(&list, root.to_str().unwrap()), EXIT_OK);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn pkgs_reports_unusable_when_proc_root_missing() {
        assert_eq!(
            pkgs_running("/nonexistent/list", "/nonexistent/proc"),
            EXIT_NO_HIT
        );
        let root = fake_proc(&[("1", "/system/bin/init")]);
        let list = write_list(&root, "com.example.app\n");
        assert_eq!(
            pkgs_running(&list, "/definitely/not/here"),
            EXIT_UNUSABLE
        );
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn empty_thresholds_degrade_to_wait_event() {
        let root = fake_sysfs(&[("battery/capacity", "10")]);
        let th = th_for(&root, None, None);
        assert!(th.is_empty());
        assert!(th.should_wake(true));
        std::fs::remove_dir_all(&root).ok();
    }
}
