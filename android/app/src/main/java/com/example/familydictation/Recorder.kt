package com.example.familydictation

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import java.io.File

/** Records the microphone to a temporary .m4a (AAC in MPEG-4, 16 kHz, mono, ~32 kbps). */
class Recorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L

    val isRecording: Boolean get() = recorder != null

    fun start() {
        val output = File.createTempFile("dictation-", ".m4a", context.cacheDir)
        val newRecorder =
            if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context)
            else @Suppress("DEPRECATION") MediaRecorder()
        try {
            newRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            newRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            newRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            newRecorder.setAudioSamplingRate(16_000)
            newRecorder.setAudioChannels(1)
            newRecorder.setAudioEncodingBitRate(32_000)
            newRecorder.setOutputFile(output.absolutePath)
            newRecorder.prepare()
            newRecorder.start()
        } catch (e: Exception) {
            newRecorder.release()
            output.delete()
            throw e
        }
        recorder = newRecorder
        file = output
        startedAt = SystemClock.elapsedRealtime()
    }

    /** Stops recording. Returns the file and its length in seconds, or null if nothing usable was recorded. */
    fun stop(): Pair<File, Double>? {
        val current = recorder ?: return null
        val output = file
        val seconds = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
        recorder = null
        file = null
        val ok = try {
            current.stop()
            true
        } catch (e: RuntimeException) {
            // MediaRecorder throws if it was stopped before any audio was captured.
            false
        } finally {
            current.release()
        }
        if (!ok || output == null) {
            output?.delete()
            return null
        }
        return output to seconds
    }

    /** Stops and throws the recording away. */
    fun cancel() {
        stop()?.first?.delete()
    }
}
