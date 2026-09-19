package com.qsc.battery.ui.config

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.qsc.battery.ui.design.charge.ChargePrimaryButton
import com.qsc.battery.ui.design.charge.ChargeSecondaryButton
import com.qsc.battery.ui.design.charge.ChargeTextField
import com.qsc.battery.ui.design.charge.ChargeTheme

private val RANGE_RE = Regex("""^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$""")

internal fun normalizeScheduleRange(raw: String): String? {
    val m = RANGE_RE.matchEntire(raw.trim()) ?: return null
    val sh = m.groupValues[1].toIntOrNull() ?: return null
    val sm = m.groupValues[2].toIntOrNull() ?: return null
    val eh = m.groupValues[3].toIntOrNull() ?: return null
    val em = m.groupValues[4].toIntOrNull() ?: return null
    if (sh !in 0..23 || eh !in 0..23 || sm !in 0..59 || em !in 0..59) return null
    return "%02d:%02d-%02d:%02d".format(sh, sm, eh, em)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ChargeScheduleSheet(
    title: String,
    ranges: List<String>,
    hint: String = "格式 HH:MM-HH:MM，支持跨天（如 23:00-07:00）",
    defaultRange: String = "23:00-07:00",
    onDismiss: () -> Unit,
    onSave: (List<String>) -> Unit,
) {
    var draft by remember(ranges) { mutableStateOf(ranges) }
    var editing by remember { mutableStateOf<Int?>(null) }
    var startText by remember { mutableStateOf("23:00") }
    var endText by remember { mutableStateOf("07:00") }
    var error by remember { mutableStateOf<String?>(null) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    fun openAdd() {
        editing = -1
        val parts = defaultRange.split("-", limit = 2)
        startText = parts.getOrNull(0) ?: "23:00"
        endText = parts.getOrNull(1) ?: "07:00"
        error = null
    }

    fun openEdit(i: Int) {
        editing = i
        val parsed = normalizeScheduleRange(draft[i]) ?: defaultRange
        val parts = parsed.split("-", limit = 2)
        startText = parts.getOrNull(0) ?: "23:00"
        endText = parts.getOrNull(1) ?: "07:00"
        error = null
    }

    fun confirmRange() {
        val normalized = normalizeScheduleRange("$startText-$endText")
        if (normalized == null) {
            error = "时间格式无效"
            return
        }
        val idx = editing ?: return
        draft = draft.toMutableList().also { list ->
            if (idx < 0) list.add(normalized) else list[idx] = normalized
        }
        editing = null
        error = null
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = ChargeTheme.colors.surface,
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(text = title, style = ChargeTheme.typography.title, color = ChargeTheme.colors.ink)
            Text(text = hint, style = ChargeTheme.typography.caption, color = ChargeTheme.colors.muted)

            if (draft.isEmpty()) {
                Text(
                    text = "暂无时段，点击下方添加",
                    style = ChargeTheme.typography.caption,
                    color = ChargeTheme.colors.muted,
                )
            }
            draft.forEachIndexed { i, item ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ChargeSecondaryButton(
                        text = item,
                        equalHeight = true,
                        modifier = Modifier.weight(1f),
                        onClick = { openEdit(i) },
                    )
                    TextButton(onClick = { draft = draft.filterIndexed { idx, _ -> idx != i } }) {
                        Text("删除", color = ChargeTheme.colors.danger)
                    }
                }
            }

            if (editing != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    ChargeTextField(
                        value = startText,
                        onValueChange = { startText = it },
                        label = "开始",
                        modifier = Modifier.weight(1f),
                    )
                    ChargeTextField(
                        value = endText,
                        onValueChange = { endText = it },
                        label = "结束",
                        modifier = Modifier.weight(1f),
                    )
                }
                if (error != null) {
                    Text(text = error!!, style = ChargeTheme.typography.caption, color = ChargeTheme.colors.danger)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ChargeSecondaryButton(
                        text = "取消",
                        equalHeight = true,
                        modifier = Modifier.weight(1f),
                        onClick = { editing = null },
                    )
                    ChargePrimaryButton(
                        text = if (editing!! < 0) "添加" else "更新",
                        modifier = Modifier.weight(1f),
                        onClick = { confirmRange() },
                    )
                }
            } else {
                ChargeSecondaryButton(
                    text = "添加时段",
                    equalHeight = true,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { openAdd() },
                )
            }

            Spacer(modifier = Modifier.height(4.dp))
            ChargePrimaryButton(
                text = "保存",
                onClick = { onSave(draft) },
            )
        }
    }
}
