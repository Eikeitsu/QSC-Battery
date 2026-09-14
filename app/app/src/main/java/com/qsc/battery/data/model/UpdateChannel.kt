package com.qsc.battery.data.model

enum class UpdateChannel(val wire: String, val label: String) {
    Stable("stable", "正式"),
    Prerelease("prerelease", "预发布"),
    Ci("ci", "CI"),
    ;

    companion object {
        fun fromWire(raw: String?): UpdateChannel =
            entries.firstOrNull { it.wire == raw } ?: Stable
    }
}
