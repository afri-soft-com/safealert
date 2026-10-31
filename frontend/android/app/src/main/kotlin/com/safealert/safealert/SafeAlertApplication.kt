package com.safealert.safealert

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

/**
 * Creates FCM SOS channels at process start so a killed app still plays the
 * custom siren. Android locks channel sound on first creation — never reuse
 * an id that was created without RawResource sound.
 */
class SafeAlertApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannels()
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        val alarmAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        fun soundUri(rawName: String): Uri =
            Uri.parse("android.resource://$packageName/raw/$rawName")

        fun upsert(
            id: String,
            name: String,
            description: String,
            rawSound: String,
            importance: Int = NotificationManager.IMPORTANCE_HIGH,
        ) {
            // If a broken channel already exists with this id, we cannot change
            // its sound — callers must bump the id (see *_v2). Creating again
            // is a no-op when the channel exists.
            if (nm.getNotificationChannel(id) != null) return
            val channel = NotificationChannel(id, name, importance).apply {
                this.description = description
                setSound(soundUri(rawSound), alarmAttrs)
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }

        // Must match backend SOS_CHANNEL_ID / DEFAULT_CHANNEL_ID (firebase.js).
        upsert(
            "safealert_sos_siren_v2",
            "Alertes SOS SafeAlert (sirène)",
            "Canal FCM SOS — son sirène SafeAlert",
            "safealert_siren",
            NotificationManager.IMPORTANCE_MAX,
        )
        upsert(
            "safealert_general_v2",
            "Notifications SafeAlert",
            "Notifications générales avec son SafeAlert",
            "safealert_beacon",
            NotificationManager.IMPORTANCE_HIGH,
        )
        // User-preference SOS channels (Flutter AlertSoundService).
        upsert(
            "safealert_sos_pulse_v2",
            "Alertes SafeAlert — Impulsion",
            "Son SafeAlert distinct (impulsion)",
            "safealert_pulse",
            NotificationManager.IMPORTANCE_MAX,
        )
        upsert(
            "safealert_sos_beacon_v2",
            "Alertes SafeAlert — Balise",
            "Son SafeAlert distinct (balise)",
            "safealert_beacon",
            NotificationManager.IMPORTANCE_MAX,
        )
        // Legacy ids — only create if missing so we don't leave a silent default.
        upsert(
            "sos_alerts",
            "Alertes SOS SafeAlert",
            "Canal historique — son sirène SafeAlert",
            "safealert_siren",
            NotificationManager.IMPORTANCE_MAX,
        )
    }
}
