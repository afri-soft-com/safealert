package com.safealert.safealert

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.safealert.safealert/volume_sos"
        private const val PRESS_WINDOW_MS = 2500L
        private const val THRESHOLD = 3
    }

    private var volumeDownCount = 0
    private val mainHandler = Handler(Looper.getMainLooper())
    private val resetCount = Runnable { volumeDownCount = 0 }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    private fun onVolumeDown() {
        volumeDownCount++
        mainHandler.removeCallbacks(resetCount)
        mainHandler.postDelayed(resetCount, PRESS_WINDOW_MS)

        if (volumeDownCount >= THRESHOLD) {
            volumeDownCount = 0
            mainHandler.removeCallbacks(resetCount)
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("triggerSOS", null)
            }
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
