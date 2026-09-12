package com.qsc.battery.ui

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.qsc.battery.data.AppContainer
import com.qsc.battery.ui.config.ConfigScreen
import com.qsc.battery.ui.design.charge.ChargeNavItem
import com.qsc.battery.ui.design.charge.ChargeScaffold
import com.qsc.battery.ui.design.charge.ImmersiveBottomBar
import com.qsc.battery.ui.home.HomeScreen
import com.qsc.battery.ui.log.LogScreen
import com.qsc.battery.ui.more.AppearanceScreen
import com.qsc.battery.ui.more.ColorPaletteScreen
import com.qsc.battery.ui.more.MoreScreen
import com.qsc.battery.ui.more.ProfilesScreen
import com.qsc.battery.ui.more.UpdatesScreen
import com.qsc.battery.ui.more.XpPanelScreen
import com.qsc.battery.ui.nav.QscTab
import com.qsc.battery.ui.onboarding.OnboardingScreen

private val enter = fadeIn() + slideInVertically { it / 28 }
private val exit = fadeOut() + slideOutVertically { -it / 28 }

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
    val snackbar = remember { SnackbarHostState() }

    ChargeScaffold(
        snackbarHostState = snackbar,
        bottomBar = {
            if (!showBar) return@ChargeScaffold
            ImmersiveBottomBar {
                QscTab.entries.forEach { tab ->
                    val icon = when (tab) {
                        QscTab.Home -> Icons.Outlined.Home
                        QscTab.Config -> Icons.Outlined.Tune
                        QscTab.Log -> Icons.Outlined.Bolt
                        QscTab.More -> Icons.Outlined.Person
                    }
                    ChargeNavItem(
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
            enterTransition = { enter },
            exitTransition = { exit },
            popEnterTransition = { enter },
            popExitTransition = { exit },
        ) {
            composable(QscTab.Home.route) {
                HomeScreen(
                    container = container,
                    onOpenStrategy = {
                        nav.navigate(QscTab.Config.route) {
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
            composable(QscTab.Config.route) {
                ConfigScreen(
                    container = container,
                    snackbar = snackbar,
                    onOpenAdvanced = { nav.navigate("config/advanced") },
                )
            }
            composable(QscTab.Log.route) { LogScreen(container) }
            composable(QscTab.More.route) {
                MoreScreen(
                    container = container,
                    onOpenAppearance = { nav.navigate("appearance") },
                    onOpenUpdates = { nav.navigate("updates") },
                    onOpenProfiles = { nav.navigate("profiles") },
                    onOpenXp = { nav.navigate("xp") },
                    snackbar = snackbar,
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
                ColorPaletteScreen(container = container, onBack = { nav.popBackStack() })
            }
            composable("xp") {
                XpPanelScreen(
                    container = container,
                    onBack = { nav.popBackStack() },
                    onOpenLspLog = {
                        nav.navigate(QscTab.Log.route) {
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    snackbar = snackbar,
                )
            }
            composable("updates") {
                UpdatesScreen(
                    container = container,
                    onBack = { nav.popBackStack() },
                    snackbar = snackbar,
                )
            }
            composable("profiles") {
                ProfilesScreen(
                    container = container,
                    onBack = { nav.popBackStack() },
                    snackbar = snackbar,
                )
            }
            composable("config/advanced") {
                ConfigScreen(
                    container = container,
                    snackbar = snackbar,
                    advancedOnly = true,
                    onBack = { nav.popBackStack() },
                )
            }
        }
    }
}
