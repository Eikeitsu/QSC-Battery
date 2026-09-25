//! 旁路唤醒：与 netlink 一起 poll inotify，让 shell 不必再挂 inotifywait 竞速。
//! 典型用途：`--wake-file /data/system/qsc_xp_viewer`（管理器 enter/leave）。

use std::ffi::CString;
use std::path::Path;
use std::time::Duration;

use crate::common::{UeventSocket, RECV_MIN_TIMEOUT};

pub(crate) struct WakeWatch {
    fd: libc::c_int,
}

impl WakeWatch {
    pub(crate) fn open(paths: &[String]) -> Option<Self> {
        if paths.is_empty() {
            return None;
        }
        // SAFETY: inotify_init1 无指针参数
        let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC | libc::IN_NONBLOCK) };
        if fd < 0 {
            return None;
        }
        let watch = Self { fd };
        let mut any = false;
        for path in paths {
            if watch.add_path(path) {
                any = true;
            }
        }
        if !any {
            return None;
        }
        Some(watch)
    }

    fn add_path(&self, path: &str) -> bool {
        let p = Path::new(path);
        // 文件可能尚不存在：监视父目录的 create/moved_to，或先 touch 失败则放弃该路径
        if let Some(parent) = p.parent() {
            if !parent.as_os_str().is_empty() && !p.exists() {
                let _ = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(p);
            }
        }
        let Ok(c) = CString::new(path.as_bytes()) else {
            return false;
        };
        let mask = libc::IN_MODIFY
            | libc::IN_ATTRIB
            | libc::IN_CLOSE_WRITE
            | libc::IN_CREATE
            | libc::IN_MOVED_TO
            | libc::IN_DELETE_SELF
            | libc::IN_MOVE_SELF;
        // SAFETY: c 在调用期间有效
        let wd = unsafe { libc::inotify_add_watch(self.fd, c.as_ptr(), mask) };
        wd >= 0
    }

    fn drain(&self) {
        let mut buf = [0u8; 4096];
        loop {
            // SAFETY: buf 有效
            let n =
                unsafe { libc::read(self.fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len()) };
            if n <= 0 {
                break;
            }
        }
    }
}

impl Drop for WakeWatch {
    fn drop(&mut self) {
        // SAFETY: fd 由本类型独占
        unsafe { libc::close(self.fd) };
    }
}

/// 同时等 netlink 与可选 inotify。返回：
/// - Ok(WakeSource::Power) 命中供电事件（调用方再做阈值过滤）
/// - Ok(WakeSource::File) 命中旁路文件
/// - Ok(WakeSource::Timeout) 本轮超时
/// - Err 套接字不可用
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum WakeSource {
    Power,
    File,
    Timeout,
}

pub(crate) fn poll_uevent_or_wake(
    sock: &UeventSocket,
    wake: Option<&WakeWatch>,
    buf: &mut [u8],
    timeout: Duration,
) -> std::io::Result<WakeSource> {
    if timeout < RECV_MIN_TIMEOUT {
        return Ok(WakeSource::Timeout);
    }
    let timeout_ms = timeout.as_millis().clamp(1, i32::MAX as u128) as libc::c_int;
    let mut fds = [
        libc::pollfd {
            fd: sock.raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        },
        libc::pollfd {
            fd: wake.map(|w| w.fd).unwrap_or(-1),
            events: libc::POLLIN,
            revents: 0,
        },
    ];
    let nfds: libc::nfds_t = if wake.is_some() { 2 } else { 1 };
    // SAFETY: fds 前 nfds 个有效
    let ready = unsafe { libc::poll(fds.as_mut_ptr(), nfds, timeout_ms) };
    if ready == 0 {
        return Ok(WakeSource::Timeout);
    }
    if ready < 0 {
        let err = std::io::Error::last_os_error();
        return if err.raw_os_error() == Some(libc::EINTR) {
            Ok(WakeSource::Timeout)
        } else {
            Err(err)
        };
    }
    if wake.is_some() && fds[1].revents != 0 {
        if let Some(w) = wake {
            w.drain();
        }
        return Ok(WakeSource::File);
    }
    if fds[0].revents != 0 {
        match sock.recv_nonblock(buf)? {
            Some(true) => return Ok(WakeSource::Power),
            Some(false) | None => return Ok(WakeSource::Timeout),
        }
    }
    Ok(WakeSource::Timeout)
}
