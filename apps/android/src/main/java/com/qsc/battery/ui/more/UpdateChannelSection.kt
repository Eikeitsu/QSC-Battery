package com.qsc.battery.ui.more

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.model.UpdateChannel
import com.qsc.battery.ui.design.charge.ChargeDivider
import com.qsc.battery.ui.design.charge.ChargeSection
import com.qsc.battery.ui.design.charge.ChargeSegmented
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeToggleRow
import com.qsc.battery.update.UpdatesSession

@Composable
internal fun UpdateChannelSection(
    channel: UpdateChannel,
    channelOptions: List<String>,
    preferCdn: Boolean,
    busy: Boolean,
    showTech: Boolean,
    onShowTechChange: (Boolean) -> Unit,
    onPendingCi: () -> Unit,
    session: UpdatesSession,
) {
    ChargeSection(title = "更新通道") {
        Column(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ChargeSegmented(
                    options = channelOptions,
                    selectedIndex = channel.ordinal,
                    onSelect = { index ->
                        if (busy) return@ChargeSegmented
                        val next = UpdateChannel.entries.getOrElse(index) { UpdateChannel.Stable }
                        if (next == UpdateChannel.Ci && channel != UpdateChannel.Ci) {
                            onPendingCi()
                        } else {
                            session.setChannel(next)
                        }
                    },
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = when (channel) {
                            UpdateChannel.Stable -> "推荐大多数用户"
                            UpdateChannel.Prerelease -> "尝鲜功能，可能不稳定"
                            UpdateChannel.Ci -> "开发构建，风险较高"
                        },
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = if (showTech) "收起" else "了解通道",
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.accent,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .clickable { onShowTechChange(!showTech) }
                            .padding(start = 8.dp, top = 2.dp, bottom = 2.dp),
                    )
                }
                if (showTech) {
                    Text(
                        text = when (channel) {
                            UpdateChannel.Stable ->
                                "正式：updates/stable；包地址通常指向 Pages。"
                            UpdateChannel.Prerelease ->
                                "预发布：updates/prerelease → GitHub Release。"
                            UpdateChannel.Ci ->
                                "CI：updates/ci → ci-dist（jsDelivr）产物。"
                        },
                        style = ChargeTheme.typography.caption,
                        color = ChargeTheme.colors.muted,
                    )
                }
            }
            if (channel == UpdateChannel.Ci) {
                ChargeDivider()
                ChargeToggleRow(
                    title = "使用 CDN",
                    checked = preferCdn,
                    summary = "开启后 CI 走 jsDelivr（有缓存，刚发版检不到可关或稍后再试）；关闭则走 GitHub raw",
                    enabled = !busy,
                    onCheckedChange = { session.setPreferCdn(it) },
                )
            }
        }
    }
}
