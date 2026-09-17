package com.qsc.battery.ui.config

internal data class ConfigEditField(
    val title: String,
    val unit: String,
    val numeric: Boolean,
    val step: Int?,
    val get: () -> String,
    val set: (String) -> Unit,
)
