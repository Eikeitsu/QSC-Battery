use crate::common::{EXIT_NO_HIT, EXIT_OK, PowerState};

/// `qscd plugged [--sysfs-root DIR]`：exit 0=插电，1=未插，2=不可读
pub(crate) fn plugged(root: &str) -> u8 {
    // 复用 PowerState：读 online / status / 电源 online 节点三向投票
    let state = PowerState::read(root);
    if state.plugged {
        EXIT_OK
    } else {
        EXIT_NO_HIT
    }
}
