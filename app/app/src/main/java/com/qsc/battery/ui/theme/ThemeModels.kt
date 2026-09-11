package com.qsc.battery.ui.theme

/** 界面皮肤：Pulse（表现型）/ Ledger（工具型）。 */
enum class UiMode(val value: String) {
    Pulse("pulse"),
    Ledger("ledger");

    companion object {
        fun fromValue(v: String?): UiMode = when (v) {
            "pulse", "miuix", null -> Pulse
            "ledger", "material" -> Ledger
            else -> entries.find { it.value == v } ?: Pulse
        }
    }
}

/** 颜色模式（含动态取色 / 纯黑）。 */
enum class ColorMode(val value: Int) {
    SYSTEM(0),
    LIGHT(1),
    DARK(2),
    MONET_SYSTEM(3),
    MONET_LIGHT(4),
    MONET_DARK(5),
    DARK_AMOLED(6);

    companion object {
        fun fromValue(value: Int) = entries.find { it.value == value } ?: SYSTEM
    }

    val isSystem: Boolean get() = value == 0 || value == 3
    val isDark: Boolean get() = value == 2 || value == 5 || value == 6
    val isAmoled: Boolean get() = value == 6
    val isMonet: Boolean get() = value >= 3

    fun toNonMonetMode(): ColorMode = when (this) {
        MONET_SYSTEM -> SYSTEM
        MONET_LIGHT -> LIGHT
        MONET_DARK, DARK_AMOLED -> DARK
        else -> this
    }

    fun toMonetMode(): ColorMode = when (this) {
        SYSTEM -> MONET_SYSTEM
        LIGHT -> MONET_LIGHT
        DARK -> MONET_DARK
        else -> this
    }
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
    Content("Content");

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, true) } ?: TonalSpot
    }
}

data class ThemeSettings(
    val uiMode: UiMode = UiMode.Pulse,
    val colorMode: ColorMode = ColorMode.SYSTEM,
    val keyColor: Int = 0xFF0B6E4F.toInt(),
    val paletteStyle: PaletteStyleName = PaletteStyleName.TonalSpot,
    val colorSpec: String = "SPEC_2021",
    val alternativeIcon: Boolean = false,
) {
    fun effectiveColorMode(): ColorMode = colorMode
}
