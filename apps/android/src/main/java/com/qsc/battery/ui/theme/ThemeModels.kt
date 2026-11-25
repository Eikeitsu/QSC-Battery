package com.qsc.battery.ui.theme

/** 颜色模式（含动态取色 / 纯黑）。 */
enum class ColorMode(val value: Int) {
    SYSTEM(0),
    LIGHT(1),
    DARK(2),
    MONET_SYSTEM(3),
    MONET_LIGHT(4),
    MONET_DARK(5),
    DARK_AMOLED(6),
    ;

    companion object {
        fun fromValue(value: Int) = entries.find { it.value == value } ?: SYSTEM
    }

    val isSystem: Boolean get() = value == 0 || value == 3
    val isDark: Boolean get() = value == 2 || value == 5 || value == 6
    val isAmoled: Boolean get() = value == 6
    val isMonet: Boolean get() = value >= 3
}

enum class PaletteStyleName(val wire: String) {
    TonalSpot("TonalSpot"),
    Neutral("Neutral"),
    Vibrant("Vibrant"),
    Expressive("Expressive"),
    Rainbow("Rainbow"),
    FruitSalad("FruitSalad"),
    Monochrome("Monochrome"),
    Fidelity("Fidelity"),
    Content("Content"),
    ;

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, true) } ?: TonalSpot
    }
}

/** 首页充电 Hero 动效样式（主题外观可切换）。 */
enum class ChargeHeroStyle(val wire: String) {
    /** 默认：柔光外扩脉冲 + 上升粒子 */
    Pulse("pulse"),

    /** 备用：进度环上弧光流转 */
    Orbit("orbit"),

    /** 竖电池 + 右侧状态信息 */
    Battery("battery"),
    ;

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, ignoreCase = true) } ?: Pulse
    }
}

data class ThemeSettings(
    val colorMode: ColorMode = ColorMode.SYSTEM,
    val keyColor: Int = 0xFF0B6E4F.toInt(),
    val paletteStyle: PaletteStyleName = PaletteStyleName.TonalSpot,
    val colorSpec: String = "SPEC_2021",
    val alternativeIcon: Boolean = false,
    val dynamicBatteryIcon: Boolean = false,
    /** 首页是否展示配置档快捷切换（默认关） */
    val homeProfileSwitcher: Boolean = false,
    /** 最近一次应用的配置档名称（仅 UI 展示） */
    val activeConfigProfile: String = "",
    /** 首页充电动画样式，默认柔光脉冲 */
    val chargeHeroStyle: ChargeHeroStyle = ChargeHeroStyle.Pulse,
)
