package com.qsc.battery.ui.util

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** 每次 ON_RESUME 执行一次协程任务（More / XP / Onboarding 等）。 */
@Composable
fun LifecycleResumeEffect(
    key: Any? = Unit,
    onResume: suspend () -> Unit,
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    DisposableEffect(lifecycleOwner, key) {
        val obs = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                scope.launch { onResume() }
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }
}

/**
 * ON_RESUME 启动轮询，ON_PAUSE 取消。
 * [onTick] 的 `first` 为本次 resume 后的首次刷新。
 */
@Composable
fun LifecycleResumePollEffect(
    intervalMs: Long,
    key: Any? = Unit,
    onTick: suspend (first: Boolean) -> Unit,
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    DisposableEffect(lifecycleOwner, key, intervalMs) {
        var job: Job? = null
        val obs = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    job?.cancel()
                    job = scope.launch {
                        var first = true
                        while (isActive) {
                            onTick(first)
                            first = false
                            delay(intervalMs)
                        }
                    }
                }

                Lifecycle.Event.ON_PAUSE -> job?.cancel()

                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose {
            job?.cancel()
            lifecycleOwner.lifecycle.removeObserver(obs)
        }
    }
}
