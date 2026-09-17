package com.qsc.battery.ui.more

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.qsc.battery.data.model.UpdateCheckResult
import com.qsc.battery.ui.design.charge.ChargeChipTone
import com.qsc.battery.ui.design.charge.ChargeStatusChip
import com.qsc.battery.ui.design.charge.ChargeTheme
import com.qsc.battery.ui.design.charge.ChargeTonalButton
import com.qsc.battery.update.UpdateTarget
import com.qsc.battery.update.UpdateWork

internal data class UpdateChipSpec(val text: String, val tone: ChargeChipTone)

internal fun openUpdateChangelog(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}

internal fun updateModuleChip(r: UpdateCheckResult): UpdateChipSpec = when {
    r.moduleRemote == null -> UpdateChipSpec("无数据", ChargeChipTone.Warn)
    r.moduleLocal == null -> UpdateChipSpec("未安装", ChargeChipTone.Update)
    r.moduleHasUpdate -> UpdateChipSpec("可更新", ChargeChipTone.Update)
    r.moduleCanSwitch -> UpdateChipSpec("可切换", ChargeChipTone.Update)
    else -> UpdateChipSpec("最新", ChargeChipTone.Ok)
}

internal fun updateAppChip(r: UpdateCheckResult): UpdateChipSpec = when {
    r.appRemote == null -> UpdateChipSpec("无数据", ChargeChipTone.Warn)
    r.appHasUpdate -> UpdateChipSpec("可更新", ChargeChipTone.Update)
    r.appCanSwitch -> UpdateChipSpec("可切换", ChargeChipTone.Update)
    else -> UpdateChipSpec("最新", ChargeChipTone.Ok)
}

internal fun updateDaemonChip(r: UpdateCheckResult): UpdateChipSpec = when {
    r.daemonRemote == null -> UpdateChipSpec("无数据", ChargeChipTone.Warn)
    r.daemonHasUpdate -> UpdateChipSpec("可更新", ChargeChipTone.Update)
    r.daemonCanSwitch -> UpdateChipSpec("可切换", ChargeChipTone.Update)
    else -> UpdateChipSpec("最新", ChargeChipTone.Ok)
}

internal fun updateVersionLine(local: String, remote: String): String {
    val l = local.ifBlank { "--" }
    val rem = remote.ifBlank { "--" }
    return if (l == rem) l else "$l → $rem"
}

@Composable
internal fun UpdateProductRow(
    title: String,
    localText: String,
    remoteText: String,
    chip: UpdateChipSpec,
    changelog: String?,
    actionLabel: String?,
    work: UpdateWork,
    target: UpdateTarget,
    actionsEnabled: Boolean,
    onAction: () -> Unit,
    onOpenChangelog: (String) -> Unit,
    rowError: String? = null,
) {
    val active = when (work) {
        is UpdateWork.Downloading -> work.target == target
        is UpdateWork.Installing -> work.target == target
        else -> false
    }
    val progressLabel = when {
        work is UpdateWork.Downloading && work.target == target -> work.label
        work is UpdateWork.Installing && work.target == target -> work.label
        else -> null
    }
    val fraction = (work as? UpdateWork.Downloading)?.takeIf { it.target == target }?.fraction

    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 12.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = title,
                style = ChargeTheme.typography.body,
                color = ChargeTheme.colors.ink,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            ChargeStatusChip(text = chip.text, tone = chip.tone)
            if (!actionLabel.isNullOrBlank() && progressLabel == null) {
                ChargeTonalButton(
                    text = actionLabel,
                    enabled = actionsEnabled && !active,
                    onClick = onAction,
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = if (progressLabel == null && rowError.isNullOrBlank()) 12.dp else 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = updateVersionLine(localText, remoteText),
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.muted,
                modifier = Modifier.weight(1f),
            )
            if (!changelog.isNullOrBlank()) {
                Text(
                    text = "说明",
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable { onOpenChangelog(changelog) },
                )
            }
        }
        if (progressLabel != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = progressLabel,
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.accent,
                    fontWeight = FontWeight.Medium,
                )
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { fraction },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(3.dp),
                        color = ChargeTheme.colors.accent,
                        trackColor = ChargeTheme.colors.stroke,
                    )
                } else {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(3.dp),
                        color = ChargeTheme.colors.accent,
                        trackColor = ChargeTheme.colors.stroke,
                    )
                }
            }
        }
        if (!rowError.isNullOrBlank()) {
            Text(
                text = rowError,
                style = ChargeTheme.typography.caption,
                color = ChargeTheme.colors.danger,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 12.dp),
            )
        }
    }
}
