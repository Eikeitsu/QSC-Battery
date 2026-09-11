package com.qsc.battery.ui.design

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.moriafly.salt.ui.SaltTheme
import com.moriafly.salt.ui.Text

/** Salt 2.8 无 TitleBar，自研简易顶栏。 */
@Composable
fun AppTitleBar(
    title: String,
    onBack: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        androidx.compose.foundation.Image(
            painter = rememberVectorPainter(Icons.AutoMirrored.Outlined.ArrowBack),
            contentDescription = "返回",
            modifier = Modifier
                .size(40.dp)
                .clickable(onClick = onBack)
                .padding(8.dp),
            colorFilter = androidx.compose.ui.graphics.ColorFilter.tint(SaltTheme.colors.text),
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = title,
            style = SaltTheme.textStyles.main,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
