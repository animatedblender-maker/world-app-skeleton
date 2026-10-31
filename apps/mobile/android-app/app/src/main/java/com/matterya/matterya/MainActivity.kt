package com.matterya.matterya

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.matterya.matterya.theme.MatteryaTheme
import com.matterya.matterya.ui.RootView
import com.matterya.matterya.viewmodel.AppViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("Matterya", "MainActivity.onCreate")
        try {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            enableEdgeToEdge()
        } catch (t: Throwable) {
            Log.w("Matterya", "edge-to-edge setup failed", t)
        }
        setContent {
            MatteryaTheme {
                MatteryaRoot()
            }
        }
    }
}

@Composable
private fun MatteryaRoot(vm: AppViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        Log.i("Matterya", "bootstrap start")
        runCatching { vm.bootstrap() }
            .onFailure { Log.e("Matterya", "bootstrap failed", it) }
    }

    RootView(state = state, vm = vm)
}
