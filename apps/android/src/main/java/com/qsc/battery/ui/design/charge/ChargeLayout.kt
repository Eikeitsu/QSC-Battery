package com.qsc.battery.ui.design.charge

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex

@Composable
fun ChargeThemeProvider(
    colors: ChargeColors,
    content: @Composable () -> Unit,
) {
    CompositionLocalProvider(
        LocalChargeColors provides colors,
        LocalChargeTypography provides chargeTypography(),
        LocalChargeDimens provides ChargeDimens(),
        content = content,
    )
}

@Composable
fun StatusScrim(modifier: Modifier = Modifier) {
    val bg = ChargeTheme.colors.scrimTop
    Box(
        modifier = modifier
            .fillMaxWidth()
            .windowInsetsTopHeight(WindowInsets.statusBars)
            .background(
                Brush.verticalGradient(
                    listOf(bg.copy(alpha = 0.96f), bg.copy(alpha = 0.55f), bg.copy(alpha = 0f)),
                ),
            )
            .zIndex(8f),
    )
}

@Composable
fun ImmersiveBottomBar(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    val shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(ChargeTheme.colors.surface),
    ) {
        // 顶部分割线：干净收口，不叠半透明蒙层
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(ChargeTheme.colors.stroke),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = 10.dp)
                .padding(top = 10.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

/**
 * 策略/进阶页底部操作条：参与布局占位（勿叠在列表上）。
 * @param clearSystemNav 无底部 Tab 时（进阶页）需避开系统手势条
 */
@Composable
fun ChargeStickyActionBar(
    modifier: Modifier = Modifier,
    clearSystemNav: Boolean = false,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(ChargeTheme.colors.background)
            .then(
                if (clearSystemNav) Modifier.windowInsetsPadding(WindowInsets.navigationBars)
                else Modifier,
            )
            .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
            .padding(top = 10.dp, bottom = 12.dp),
    ) {
        content()
    }
}

@Composable
fun ChargeScaffold(
    modifier: Modifier = Modifier,
    snackbarHostState: SnackbarHostState? = null,
    bottomBar: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(ChargeTheme.colors.background),
    ) {
        // Soft atmosphere
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(280.dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            ChargeTheme.colors.accent.copy(alpha = 0.10f),
                            Color.Transparent,
                        ),
                        center = Offset(0.5f, 0.15f),
                        radius = 900f,
                    ),
                ),
        )
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                content()
                snackbarHostState?.let {
                    SnackbarHost(
                        hostState = it,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(16.dp)
                            .windowInsetsPadding(WindowInsets.navigationBars),
                    )
                }
            }
            bottomBar()
        }
        StatusScrim(modifier = Modifier.align(Alignment.TopCenter))
    }
}

@Composable
fun ChargePage(
    modifier: Modifier = Modifier,
    includeStatusSpacer: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = ChargeTheme.dimens.pageHorizontal)
            .padding(bottom = ChargeTheme.dimens.sectionGap),
        verticalArrangement = Arrangement.spacedBy(ChargeTheme.dimens.sectionGap),
    ) {
        if (includeStatusSpacer) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        }
        content()
    }
}
