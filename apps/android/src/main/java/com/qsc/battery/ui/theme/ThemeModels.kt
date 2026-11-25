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

enum class ChargeAnimShape(val wire: String) {
    Battery("battery"),
    Ring("ring"),
    ;

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, ignoreCase = true) } ?: Battery
    }
}

enum class BatteryOrientation(val wire: String) {
    Vertical("vertical"),
    Horizontal("horizontal"),
    ;

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, ignoreCase = true) } ?: Vertical
    }
}

enum class BatteryFillStyle(val wire: String) {
    Liquid("liquid"),
    Blocks("blocks"),
    Solid("solid"),
    ;

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, ignoreCase = true) } ?: Liquid
    }
}

enum class RingEffect(val wire: String) {
    SoftPulse("soft_pulse"),
    ArcOrbit("arc_orbit"),
    NeonMinimal("neon_minimal"),
    LiquidRise("liquid_rise"),
    Concentric("concentric"),
    PlasmaWave("plasma_wave"),
    ;

    companion object {
        fun fromWire(s: String?) = entries.find { it.wire.equals(s, ignoreCase = true) } ?: SoftPulse
    }
}

/**
 * 首页充电动画配置。
 * 横屏不支持液体：归一化时 Liquid → Solid。
 */
data class ChargeAnimConfig(
    val shape: ChargeAnimShape = ChargeAnimShape.Battery,
    val batteryOrientation: BatteryOrientation = BatteryOrientation.Vertical,
    val batteryFill: BatteryFillStyle = BatteryFillStyle.Liquid,
    val ringEffect: RingEffect = RingEffect.SoftPulse,
) {
    fun normalized(): ChargeAnimConfig {
        if (shape != ChargeAnimShape.Battery) return this
        if (batteryOrientation == BatteryOrientation.Horizontal &&
            batteryFill == BatteryFillStyle.Liquid
        ) {
            return copy(batteryFill = BatteryFillStyle.Solid)
        }
        return this
    }

    fun summaryLabel(): String = when (shape) {
        ChargeAnimShape.Battery -> {
            val orient = when (batteryOrientation) {
                BatteryOrientation.Vertical -> "竖"
                BatteryOrientation.Horizontal -> "横"
            }
            val fill = when (normalized().batteryFill) {
                BatteryFillStyle.Liquid -> "液体"
                BatteryFillStyle.Blocks -> "电量块"
                BatteryFillStyle.Solid -> "普通填充"
            }
            "电池 · $orient · $fill"
        }

        ChargeAnimShape.Ring -> {
            val fx = when (ringEffect) {
                RingEffect.SoftPulse -> "柔光脉冲"
                RingEffect.ArcOrbit -> "弧光流转"
                RingEffect.NeonMinimal -> "极简霓虹"
                RingEffect.LiquidRise -> "液体上涌"
                RingEffect.Concentric -> "同心科技"
                RingEffect.PlasmaWave -> "等离子波"
            }
            "圆环 · $fx"
        }
    }

    companion object {
        val Default = ChargeAnimConfig()
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
    /** 首页充电动画配置 */
    val chargeAnim: ChargeAnimConfig = ChargeAnimConfig.Default,
)
