package com.qsc.battery.ui.design.charge

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
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChargeEditSheet(
    title: String,
    value: String,
    unit: String = "",
    numeric: Boolean = true,
    step: Int? = null,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var draft by remember(value) { mutableStateOf(value) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(text = title, style = ChargeTheme.typography.title, color = ChargeTheme.colors.ink)
            if (numeric && step != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ChargeSecondaryButton(
                        text = "−$step",
                        equalHeight = true,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            val n = draft.toIntOrNull() ?: 0
                            draft = (n - step).toString()
                        },
                    )
                    Text(
                        text = "$draft${if (unit.isNotBlank()) " $unit" else ""}",
                        style = ChargeTheme.typography.headline,
                        color = ChargeTheme.colors.ink,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                    ChargeSecondaryButton(
                        text = "+$step",
                        equalHeight = true,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            val n = draft.toIntOrNull() ?: 0
                            draft = (n + step).toString()
                        },
                    )
                }
            }
            ChargeTextField(
                value = draft,
                onValueChange = { draft = it },
                suffix = unit.ifBlank { null },
                numeric = numeric,
            )
            Spacer(modifier = Modifier.height(4.dp))
            ChargePrimaryButton(
                text = "确定",
                onClick = { onConfirm(draft.trim()) },
            )
        }
    }
}
