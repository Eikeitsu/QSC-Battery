package com.qsc.battery.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BatteryChargingFull
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.config.ConfigScreen
import com.qsc.battery.ui.design.AppChrome
import com.qsc.battery.ui.design.AppNavItem
import com.qsc.battery.ui.design.ImmersiveBottomBar
import com.qsc.battery.ui.home.HomeScreen
import com.qsc.battery.ui.log.LogScreen
import com.qsc.battery.ui.more.AppearanceScreen
import com.qsc.battery.ui.more.ColorPaletteScreen
import com.qsc.battery.ui.more.MoreScreen
import com.qsc.battery.ui.more.UpdatesScreen
import com.qsc.battery.ui.nav.QscTab
import com.qsc.battery.ui.onboarding.OnboardingScreen

@Composable
fun QscAppRoot(container: AppContainer) {
    val onboardingDone by container.settingsRepository.onboardingDone.collectAsStateWithLifecycle(initialValue = false)
    if (!onboardingDone) {
        OnboardingScreen(container = container, onFinished = {})
        return
    }

    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route ?: QscTab.Home.route
    val showBar = QscTab.entries.any { it.route == route }

    AppChrome(
        bottomBar = {
            if (!showBar) return@AppChrome
            ImmersiveBottomBar {
                QscTab.entries.forEach { tab ->
                    val icon = when (tab) {
                        QscTab.Home -> Icons.Outlined.Home
                        QscTab.Config -> Icons.Outlined.Tune
                        QscTab.Log -> Icons.Outlined.BatteryChargingFull
                        QscTab.More -> Icons.Outlined.Person
                    }
                    AppNavItem(
                        selected = route == tab.route,
                        icon = icon,
                        label = tab.label,
                        onClick = {
                            nav.navigate(tab.route) {
                                popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                    )
                }
            }
        },
    ) {
        NavHost(
            navController = nav,
            startDestination = QscTab.Home.route,
        ) {
            composable(QscTab.Home.route) { HomeScreen(container) }
            composable(QscTab.Config.route) { ConfigScreen(container) }
            composable(QscTab.Log.route) { LogScreen(container) }
            composable(QscTab.More.route) {
                MoreScreen(
                    container = container,
                    onOpenAppearance = { nav.navigate("appearance") },
                    onOpenUpdates = { nav.navigate("updates") },
                )
            }
            composable("appearance") {
                AppearanceScreen(
                    container = container,
                    onBack = { nav.popBackStack() },
                    onOpenPalette = { nav.navigate("palette") },
                )
            }
            composable("palette") {
                ColorPaletteScreen(
                    container = container,
                    onBack = { nav.popBackStack() },
                )
            }
            composable("updates") {
                UpdatesScreen(
                    container = container,
                    onBack = { nav.popBackStack() },
                )
            }
        }
    }
}
