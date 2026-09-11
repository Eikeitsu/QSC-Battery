package com.qsc.battery

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.qsc.battery.ui.QscAppRoot
import com.qsc.battery.ui.theme.QscTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as QscApp).container
        setContent {
            val settings by container.settingsRepository.settings.collectAsStateWithLifecycle()
            QscTheme(settings = settings) {
                QscAppRoot(container = container)
            }
        }
    }
}
