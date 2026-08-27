//! 事件等待器：阻塞在内核 power_supply uevent 上，让 shell 主循环不再需要定时唤醒。
//!
//! 用法
//!   qscd wait-event <最长秒数> [最短秒数]
//!       先睡「最短秒数」压掉事件风暴，再等 power_supply 事件直到「最长秒数」。
//!       退出 0 = 有事件或已到时（调用方跑完整一轮）
//!       退出 2 = 本机不可用（调用方应永久退回 sleep）
//!   qscd probe
//!       安装时自检：能建起 netlink 套接字则退出 0。
//!
//! 设计约束：本程序不写任何充电节点，也不做阈值判定，只负责「等」。
//! 因此它异常退出时最坏结果是退化成定时轮询，而不是停充失效。

use std::env;
use std::process::ExitCode;
use std::time::{Duration, Instant};

const NETLINK_KOBJECT_UEVENT: libc::c_int = 15;
/// 内核 uevent 载荷里的匹配串；命中即认为电池状态可能变了
const MATCH: &[u8] = b"SUBSYSTEM=power_supply";
const RECV_BUF: usize = 8192;
/// 单次 recv 超时，用于周期性回到循环检查总截止时间
const RECV_SLICE: Duration = Duration::from_secs(2);

const EXIT_OK: u8 = 0;
const EXIT_UNUSABLE: u8 = 2;

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

        sock.set_recv_timeout(RECV_SLICE)?;
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
    while Instant::now() < deadline {
        match sock.poll_once(&mut buf) {
            Ok(true) => return EXIT_OK,
            Ok(false) => {}
            Err(_) => return EXIT_UNUSABLE,
        }
    }
    EXIT_OK
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
            let max = parse_secs(args.get(2).map(String::as_str), 30, 3600);
            let floor = parse_secs(args.get(3).map(String::as_str), 3, max.max(1));
            ExitCode::from(wait_event(max, floor))
        }
        Some("probe") => {
            if UeventSocket::open().is_some() {
                println!("ok");
                ExitCode::from(EXIT_OK)
            } else {
                eprintln!("qscd: netlink uevent socket unavailable");
                ExitCode::from(EXIT_UNUSABLE)
            }
        }
        _ => {
            eprintln!("usage: qscd wait-event <max_secs> [floor_secs] | qscd probe");
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
}
