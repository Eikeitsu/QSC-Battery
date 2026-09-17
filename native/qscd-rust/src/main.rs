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
//!   qscd selftest [--sysfs-root DIR]
//!       检查 netlink、事件过滤和电源节点读取能力，只读不写。
//!
//! 设计约束：本程序不写任何充电节点，也不做停充/恢复决策，只负责「等」与
//! 「该不该叫醒 shell」。阈值判定的唯一真理仍在 shell 里——sh 版主包没有本
//! 二进制也必须行为一致。因此它异常退出时最坏结果是退化成定时轮询。

mod common;
mod diagnose;
mod plugged;
mod watch;

use std::env;
use std::process::ExitCode;
use std::time::Duration;

use common::{
    BatterySnapshot, EXIT_NO_HIT, EXIT_OK, EXIT_UNUSABLE, PowerState, SnapshotFailure,
    SnapshotSource, UeventSocket, WAIT_FLOOR_DEFAULT, WAIT_MAX_CAP, WAIT_MAX_DEFAULT, parse_secs,
    wait_event,
};
use diagnose::diagnose;
use plugged::plugged;
use watch::{parse_watch_args, watch};

/// 支持的扩展子命令；features 子命令原样打印
const FEATURES: &str = "watch pkgs selftest plugged diagnose";

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
        if wanted.contains(&cmd) {
            return EXIT_OK;
        }
    }
    EXIT_NO_HIT
}

fn selftest(root: &str) -> u8 {
    let netlink = UeventSocket::open().is_some();
    let base = format!("{root}/sys/class/power_supply");
    let sysfs = [
        "battery/capacity",
        "battery/soc",
        "battery/status",
        "battery/temp",
        "battery/batt_temp",
        "bms/capacity",
        "bms/status",
        "bms/temp",
    ]
    .iter()
    .any(|path| std::path::Path::new(&format!("{base}/{path}")).is_file());
    let state = PowerState::read(root);
    let snapshot = BatterySnapshot::read(root);
    let snapshot_source = match &snapshot.source {
        SnapshotSource::Battery => "battery",
        SnapshotSource::Bms => "bms",
        SnapshotSource::Soc => "soc",
        SnapshotSource::Missing => "missing",
    };

    println!("netlink={}", if netlink { 1 } else { 0 });
    println!("event_filter=1");
    println!("sysfs={}", if sysfs { 1 } else { 0 });
    println!("plugged={}", if state.plugged { 1 } else { 0 });
    println!("snapshot_source={snapshot_source}");
    println!(
        "snapshot_level={}",
        snapshot
            .level
            .map_or_else(|| "missing".to_string(), |v| v.to_string())
    );
    println!(
        "snapshot_temp={}",
        snapshot
            .temp
            .map_or_else(|| "missing".to_string(), |v| v.to_string())
    );
    println!(
        "snapshot_status={}",
        snapshot.status.as_deref().unwrap_or("missing")
    );
    let snapshot_failure = match snapshot.failure {
        SnapshotFailure::None => "none",
        SnapshotFailure::LevelMissing => "level_missing",
        SnapshotFailure::TemperatureMissing => "temperature_missing",
        SnapshotFailure::StatusMissing => "status_missing",
    };
    println!("snapshot_failure={snapshot_failure}");
    println!("watch=1");
    println!("pkgs=1");
    println!("plugged=1");
    println!("diagnose=1");
    if netlink {
        EXIT_OK
    } else {
        EXIT_UNUSABLE
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("wait-event") => {
            let max = parse_secs(
                args.get(2).map(String::as_str),
                WAIT_MAX_DEFAULT,
                WAIT_MAX_CAP,
            );
            let floor = parse_secs(
                args.get(3).map(String::as_str),
                WAIT_FLOOR_DEFAULT,
                max.max(1),
            );
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
            // 保留 socket 超时能力诊断；实际 wait/watch 截止时间由 poll 控制
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
        Some("selftest") => {
            let mut root = "";
            if let Some(i) = args.iter().position(|a| a == "--sysfs-root") {
                root = args.get(i + 1).map(String::as_str).unwrap_or("");
            }
            ExitCode::from(selftest(root))
        }
        Some("plugged") => {
            let mut root = "";
            if let Some(i) = args.iter().position(|a| a == "--sysfs-root") {
                root = args.get(i + 1).map(String::as_str).unwrap_or("");
            }
            ExitCode::from(plugged(root))
        }
        Some("diagnose") => {
            let mut root = "";
            if let Some(i) = args.iter().position(|a| a == "--sysfs-root") {
                root = args.get(i + 1).map(String::as_str).unwrap_or("");
            }
            ExitCode::from(diagnose(root))
        }
        _ => {
            eprintln!(
                "usage: qscd wait-event <max_secs> [floor_secs]\n       \
                 qscd watch --max N [--floor N] [--stop N] [--near N] [--temp-stop N]\n       \
                 qscd pkgs <list_file> [--proc-root DIR]\n       \
                 qscd plugged | qscd diagnose | qscd probe | qscd features\n       \
                 qscd selftest [--sysfs-root DIR]"
            );
            ExitCode::from(EXIT_UNUSABLE)
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::common::{
        BatterySnapshot, EXIT_NO_HIT, EXIT_OK, EXIT_UNUSABLE, PowerState, SnapshotFailure,
        SnapshotSource, contains, is_power_supply_event, normalize_temp, parse_secs, wait_event,
    };
    use crate::watch::{Thresholds, parse_watch_args};
    use crate::pkgs_running;

    const TEST_MATCH: &[u8] = b"SUBSYSTEM=power_supply";

    #[test]
    fn contains_finds_power_supply_subsystem() {
        let payload = b"change@/devices/battery\0ACTION=change\0SUBSYSTEM=power_supply\0";
        assert!(contains(payload, TEST_MATCH));
    }

    #[test]
    fn contains_rejects_other_subsystems() {
        let payload = b"change@/devices/net\0ACTION=change\0SUBSYSTEM=net\0";
        assert!(!contains(payload, TEST_MATCH));
        assert!(!contains(b"", TEST_MATCH));
        assert!(!contains(b"short", TEST_MATCH));
    }

    #[test]
    fn power_supply_event_requires_power_supply_identity() {
        let payload =
            b"change@/devices/battery\0ACTION=change\0SUBSYSTEM=power_supply\0DEVPATH=/devices/battery\0";
        assert!(!is_power_supply_event(payload));
    }

    #[test]
    fn power_supply_event_accepts_path_or_supply_name() {
        let path =
            b"change@/devices/battery\0SUBSYSTEM=power_supply\0DEVPATH=/devices/power_supply/battery\0";
        assert!(is_power_supply_event(path));

        let name = b"change@/devices/battery\0SUBSYSTEM=power_supply\0POWER_SUPPLY_NAME=battery\0";
        assert!(is_power_supply_event(name));
    }

    #[test]
    fn power_supply_event_rejects_substring_matches() {
        let payload =
            b"change@/devices/battery\0SUBSYSTEM=power_supply_extra\0DEVPATH=/devices/power_supply/battery\0";
        assert!(!is_power_supply_event(payload));
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
    fn snapshot_prefers_battery_nodes_and_normalizes_temperature() {
        let root = fake_sysfs(&[
            ("battery/capacity", "82"),
            ("battery/status", "Charging"),
            ("battery/temp", "320"),
            ("bms/capacity", "1"),
            ("bms/temp", "1"),
            ("usb/online", "1"),
        ]);
        let snapshot = BatterySnapshot::read(root.to_str().unwrap());
        assert_eq!(snapshot.level, Some(82));
        assert_eq!(snapshot.temp, Some(32));
        assert_eq!(snapshot.status.as_deref(), Some("Charging"));
        assert_eq!(snapshot.source, SnapshotSource::Battery);
        assert_eq!(snapshot.failure, SnapshotFailure::None);
        assert!(snapshot.plugged);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn snapshot_falls_back_to_bms_and_soc() {
        let bms = fake_sysfs(&[
            ("bms/capacity", "77"),
            ("bms/status", "Not charging"),
            ("bms/temp", "3000"),
        ]);
        let snapshot = BatterySnapshot::read(bms.to_str().unwrap());
        assert_eq!(snapshot.level, Some(77));
        assert_eq!(snapshot.temp, Some(30));
        assert_eq!(snapshot.source, SnapshotSource::Bms);
        assert_eq!(snapshot.failure, SnapshotFailure::None);
        std::fs::remove_dir_all(&bms).ok();

        let soc = fake_sysfs(&[
            ("battery/soc", "66"),
            ("battery/temp", "30"),
            ("battery/status", "Charging"),
        ]);
        let snapshot = BatterySnapshot::read(soc.to_str().unwrap());
        assert_eq!(snapshot.level, Some(66));
        assert_eq!(snapshot.source, SnapshotSource::Soc);
        assert_eq!(snapshot.failure, SnapshotFailure::None);
        std::fs::remove_dir_all(&soc).ok();
    }

    #[test]
    fn snapshot_reports_missing_level_as_failure() {
        let root = fake_sysfs(&[("battery/temp", "300"), ("battery/status", "Unknown")]);
        let snapshot = BatterySnapshot::read(root.to_str().unwrap());
        assert_eq!(snapshot.source, SnapshotSource::Missing);
        assert_eq!(snapshot.failure, SnapshotFailure::LevelMissing);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn parse_watch_args_reads_flags_and_clamps() {
        let args: Vec<String> = [
            "--max", "600", "--floor", "5", "--stop", "80", "--near", "99",
        ]
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
        assert!(th.wake_reason(true).is_none());
        // 起始状态记为未插电，现在读到插电 → 必须叫醒
        assert_eq!(th.wake_reason(false), Some("plug_changed"));
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn power_state_rejects_isolated_not_charging() {
        let root = fake_sysfs(&[("battery/status", "Not charging")]);
        assert!(!PowerState::read(root.to_str().unwrap()).plugged);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn power_state_accepts_present_with_vbus() {
        let root = fake_sysfs(&[
            ("battery/status", "Not charging"),
            ("usb/present", "1"),
            ("usb/voltage_now", "5000000"),
        ]);
        assert!(PowerState::read(root.to_str().unwrap()).plugged);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn power_state_rejects_isolated_present() {
        let present = fake_sysfs(&[("usb/present", "1"), ("usb/voltage_now", "0")]);
        assert!(!PowerState::read(present.to_str().unwrap()).plugged);
        std::fs::remove_dir_all(&present).ok();
    }

    #[test]
    fn power_state_accepts_type_and_vbus_signals() {
        let type_root = fake_sysfs(&[("usb/type", "USB_PD")]);
        assert!(PowerState::read(type_root.to_str().unwrap()).plugged);
        std::fs::remove_dir_all(&type_root).ok();
    }

    #[test]
    fn power_state_accepts_microvolt_and_millivolt_vbus() {
        let microvolt = fake_sysfs(&[("usb/voltage_now", "5000000")]);
        assert!(PowerState::read(microvolt.to_str().unwrap()).plugged);
        std::fs::remove_dir_all(&microvolt).ok();

        let millivolt = fake_sysfs(&[("usb/voltage_now", "5000")]);
        assert!(PowerState::read(millivolt.to_str().unwrap()).plugged);
        std::fs::remove_dir_all(&millivolt).ok();
    }

    #[test]
    fn power_state_rejects_unknown_signals() {
        let root = fake_sysfs(&[
            ("battery/status", "Unknown"),
            ("usb/type", "Unknown"),
            ("usb/voltage_now", "0"),
        ]);
        assert!(!PowerState::read(root.to_str().unwrap()).plugged);
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
        assert_eq!(
            th_for(&root, Some(80), None).wake_reason(true),
            Some("near_level")
        );
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
        assert_eq!(
            th_for(&root, None, Some(60)).wake_reason(true),
            Some("near_temp")
        );
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
        assert_eq!(pkgs_running(&list, "/definitely/not/here"), EXIT_UNUSABLE);
        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn empty_thresholds_degrade_to_wait_event() {
        let root = fake_sysfs(&[("battery/capacity", "10")]);
        let th = th_for(&root, None, None);
        assert!(th.is_empty());
        assert_eq!(th.wake_reason(true), Some("event"));
        std::fs::remove_dir_all(&root).ok();
    }
}
