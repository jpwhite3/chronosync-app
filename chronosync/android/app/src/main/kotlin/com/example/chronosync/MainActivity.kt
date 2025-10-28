package com.example.chronosync

import android.content.Context
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.chronosync/device_audio_android"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableSounds" -> getAvailableSounds(result)
                "previewSound" -> {
                    val soundUri = call.argument<String>("soundUri")
                    if (soundUri != null) {
                        previewSound(soundUri, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing soundUri", null)
                    }
                }
                "stopPreview" -> stopPreview(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun getAvailableSounds(result: MethodChannel.Result) {
        try {
            val ringtoneManager = RingtoneManager(this)
            ringtoneManager.setType(RingtoneManager.TYPE_NOTIFICATION)
            val cursor = ringtoneManager.cursor

            val sounds = mutableListOf<Map<String, Any>>()

            // Add system default first
            sounds.add(
                mapOf(
                    "id" to "system_default",
                    "displayName" to "System Default",
                    "filePath" to RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION).toString(),
                    "isSystemSound" to true
                )
            )

            // Add available notification sounds
            var count = 0
            while (cursor.moveToNext() && count < 20) { // Limit to 20 sounds
                try {
                    val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                    val uri = ringtoneManager.getRingtoneUri(cursor.position).toString()
                    val id = cursor.getString(RingtoneManager.ID_COLUMN_INDEX)

                    sounds.add(
                        mapOf(
                            "id" to id,
                            "displayName" to title,
                            "filePath" to uri,
                            "isSystemSound" to true
                        )
                    )
                    count++
                } catch (e: Exception) {
                    // Skip sounds that can't be accessed
                    continue
                }
            }

            result.success(sounds)
        } catch (e: Exception) {
            result.error("FETCH_FAILED", "Failed to fetch sounds: ${e.message}", null)
        }
    }

    private fun previewSound(soundUri: String, result: MethodChannel.Result) {
        try {
            // Stop any currently playing sound
            mediaPlayer?.release()
            mediaPlayer = null

            val uri = Uri.parse(soundUri)
            mediaPlayer = MediaPlayer.create(this, uri)
            
            if (mediaPlayer != null) {
                mediaPlayer?.setOnCompletionListener {
                    it.release()
                    mediaPlayer = null
                }
                mediaPlayer?.start()
                result.success(null)
            } else {
                result.error("PLAYBACK_FAILED", "Failed to create MediaPlayer", null)
            }
        } catch (e: Exception) {
            result.error("PLAYBACK_FAILED", "Failed to preview sound: ${e.message}", null)
        }
    }

    private fun stopPreview(result: MethodChannel.Result) {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
            result.success(null)
        } catch (e: Exception) {
            result.error("STOP_FAILED", "Failed to stop preview: ${e.message}", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
