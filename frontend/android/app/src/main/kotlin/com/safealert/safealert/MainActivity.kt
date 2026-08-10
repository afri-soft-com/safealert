package com.safealert.safealert

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_SILENT_SOS = "com.safealert.safealert.ACTION_SILENT_SOS"
        private const val CHANNEL = "com.safealert.safealert/volume_sos"
        private const val PRESS_WINDOW_MS = 2500L
        private const val THRESHOLD = 3
    }

    private var volumeDownCount = 0
    private var pendingSilentSos = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val resetCount = Runnable { volumeDownCount = 0 }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        if (pendingSilentSos || intent?.action == ACTION_SILENT_SOS) {
            pendingSilentSos = false
            mainHandler.postDelayed({ invokeSilentSos() }, 400)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == ACTION_SILENT_SOS) {
            if (flutterEngine != null) {
                invokeSilentSos()
            } else {
                pendingSilentSos = true
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        if (intent?.action == ACTION_SILENT_SOS) {
            pendingSilentSos = true
        }
        super.onCreate(savedInstanceState)
    }

    private fun invokeSilentSos() {
        flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, CHANNEL).invokeMethod("triggerSOS", null)
        }
    }

    private fun onVolumeDown() {
        volumeDownCount++
        mainHandler.removeCallbacks(resetCount)
        mainHandler.postDelayed(resetCount, PRESS_WINDOW_MS)

        if (volumeDownCount >= THRESHOLD) {
            volumeDownCount = 0
            mainHandler.removeCallbacks(resetCount)
            invokeSilentSos()
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            onVolumeDown()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            onVolumeDown()
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
