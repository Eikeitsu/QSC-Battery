package com.qsc.battery.tile

import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.qsc.battery.R
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * 快捷设置磁贴：切换「充满再停」（charge_full），经模块自带 CLI，不新增 shell 脚本。
 * 开启时顺带保证 power_stop=100（与 App 策略页门禁一致），并 bump conf_reload_req。
 */
class ChargeFullTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val root = RootBridge()

    override fun onStartListening() {
        scope.launch { refresh() }
    }

    override fun onClick() {
        scope.launch {
            if (!ready()) {
                qsTile?.apply {
                    state = Tile.STATE_UNAVAILABLE
                    subtitle = "需要模块与 Root"
                    updateTile()
                }
                return@launch
            }
            val on = isChargeFullOn()
            if (on) {
                cliCfgSet("charge_full", "0")
            } else {
                // 与策略页一致：充满再停要求停止电量为 100%
                cliCfgSet("power_stop", "100")
                cliCfgSet("charge_full", "1")
            }
            root.touch(ModulePaths.CONF_RELOAD_REQ)
            refresh()
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun ready(): Boolean = root.isRootAvailable() && root.exists(ModulePaths.MODULE_PROP) && root.exists(ModulePaths.QSC_SH)

    private suspend fun cliCfgGet(key: String): String {
        val r = root.exec("sh '${ModulePaths.QSC_SH}' cfg get '$key' 2>/dev/null")
        return r.out.trim().lineSequence().lastOrNull().orEmpty()
            .removePrefix("(未设置)")
            .trim()
    }

    private suspend fun cliCfgSet(key: String, value: String): Boolean = root.exec("sh '${ModulePaths.QSC_SH}' cfg set '$key' '$value'").ok

    private suspend fun isChargeFullOn(): Boolean {
        val full = cliCfgGet("charge_full")
        val stop = cliCfgGet("power_stop")
        return full == "1" && stop == "100"
    }

    private suspend fun refresh() {
        val tile = qsTile ?: return
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_charge_full)
        if (!root.isRootAvailable()) {
            tile.state = Tile.STATE_UNAVAILABLE
            tile.subtitle = "无 Root"
            tile.updateTile()
            return
        }
        if (!root.exists(ModulePaths.MODULE_PROP)) {
            tile.state = Tile.STATE_UNAVAILABLE
            tile.subtitle = "未装模块"
            tile.updateTile()
            return
        }
        if (!root.exists(ModulePaths.QSC_SH)) {
            tile.state = Tile.STATE_UNAVAILABLE
            tile.subtitle = "CLI 缺失"
            tile.updateTile()
            return
        }
        val on = isChargeFullOn()
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.subtitle = if (on) "已开启" else "已关闭"
        tile.updateTile()
    }
}
