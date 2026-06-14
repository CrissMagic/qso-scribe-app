package com.example.qso_scribe_app

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private var pendingPlayResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qso_scribe/audio_playback",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_audio_path", "Audio path is required", null)
                    } else {
                        playAudio(path, result)
                    }
                }
                "stop" -> {
                    stopAudio()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }

    private fun playAudio(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("audio_file_missing", "Audio file does not exist", null)
            return
        }

        stopAudio()
        val mediaPlayer = MediaPlayer()
        player = mediaPlayer
        pendingPlayResult = result
        try {
            mediaPlayer.setDataSource(file.absolutePath)
            mediaPlayer.setOnCompletionListener { finishPlayback(null, null) }
            mediaPlayer.setOnErrorListener { _, what, extra ->
                finishPlayback(
                    "audio_playback_failed",
                    "MediaPlayer error $what/$extra",
                )
                true
            }
            mediaPlayer.prepare()
            mediaPlayer.start()
        } catch (error: Exception) {
            finishPlayback(
                "audio_playback_failed",
                error.localizedMessage ?: "Unable to play audio",
            )
        }
    }

    private fun stopAudio() {
        val current = player
        player = null
        if (current != null) {
            try {
                if (current.isPlaying) {
                    current.stop()
                }
            } catch (_: IllegalStateException) {
                // Release below still resets the native player.
            }
            current.release()
        }
        pendingPlayResult?.success(null)
        pendingPlayResult = null
    }

    private fun finishPlayback(errorCode: String?, errorMessage: String?) {
        val current = player
        player = null
        current?.release()

        val result = pendingPlayResult
        pendingPlayResult = null
        if (errorCode == null) {
            result?.success(null)
        } else {
            result?.error(errorCode, errorMessage, null)
        }
    }
}
