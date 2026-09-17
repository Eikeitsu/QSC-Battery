package com.qsc.battery.tile

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.qsc.battery.core.ModulePaths
import com.qsc.battery.core.RootBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * 快捷设置磁贴：需要 Root + 已安装模块时，切换 module_off 软开关。
 * 不常驻后台循环；仅在磁贴可见/点击时执行。
 */
class ChargeControlTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val root = RootBridge()

    override fun onStartListening() {
        scope.launch { refresh() }
    }

    override fun onClick() {
        scope.launch {
            if (!root.isRootAvailable() || !root.exists(ModulePaths.MODULE_PROP)) {
                qsTile?.apply {
                    state = Tile.STATE_UNAVAILABLE
                    subtitle = "需要模块与 Root"
                    updateTile()
                }
                return@launch
            }
            val off = root.exists(ModulePaths.MODULE_OFF_FLAG)
            if (off) root.rm(ModulePaths.MODULE_OFF_FLAG) else root.touch(ModulePaths.MODULE_OFF_FLAG)
            refresh()
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun refresh() {
        val tile = qsTile ?: return
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
        val off = root.exists(ModulePaths.MODULE_OFF_FLAG)
        tile.state = if (off) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        tile.subtitle = if (off) "已关闭" else "运行中"
        tile.updateTile()
    }
}
