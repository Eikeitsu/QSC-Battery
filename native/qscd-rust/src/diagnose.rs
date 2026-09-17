use crate::common::{
    BatterySnapshot, EXIT_OK, EXIT_UNUSABLE, PowerState, SnapshotFailure, SnapshotSource,
    read_text,
};

/// `qscd diagnose [--sysfs-root DIR]`：枚举关键电源节点是否可读/是否有缺值，
/// 打印 k=v（含归一化后的 level/temp/status/plugged）。shell 侧可直接 grep 定位异常。
pub(crate) fn diagnose(root: &str) -> u8 {
    let base = format!("{root}/sys/class/power_supply");
    let snapshot = BatterySnapshot::read(root);
    let state = PowerState::read(root);
    let snapshot_source = match &snapshot.source {
        SnapshotSource::Battery => "battery",
        SnapshotSource::Bms => "bms",
        SnapshotSource::Soc => "soc",
        SnapshotSource::Missing => "missing",
    };
    println!("snapshot_source={snapshot_source}");
    println!("plugged={}", if state.plugged { 1 } else { 0 });
    println!(
        "level={}",
        snapshot
            .level
            .map_or_else(|| "missing".to_string(), |v| v.to_string()),
    );
    println!(
        "temp={}",
        snapshot
            .temp
            .map_or_else(|| "missing".to_string(), |v| v.to_string()),
    );
    println!("status={}", snapshot.status.as_deref().unwrap_or("missing"));
    // 逐节点输出关键信号原值值（缺失=missing），便于 shell 端定位某台机型
    for name in [
        "online",
        "present",
        "type",
        "real_type",
        "voltage_now",
        "status",
        "current_now",
        "capacity",
        "temp",
    ] {
        // 先 battery；失败再 bms/soc 回退
        let mut val: Option<String> = None;
        for sub in ["battery", "bms", "soc"] {
            let p = format!("{base}/{sub}/{name}");
            if let Some(v) = read_text(&p) {
                val = Some(v);
                break;
            }
        }
        let v = val.as_deref().unwrap_or("missing");
        println!("node.{name}={v}");
    }
    let failure = match snapshot.failure {
        SnapshotFailure::None => "none",
        SnapshotFailure::LevelMissing => "level_missing",
        SnapshotFailure::TemperatureMissing => "temperature_missing",
        SnapshotFailure::StatusMissing => "status_missing",
    };
    println!("snapshot_failure={failure}");
    // 任何关键缺项返回 2，完全 OK=0
    match snapshot.failure {
        SnapshotFailure::None => EXIT_OK,
        _ => EXIT_UNUSABLE,
    }
}
