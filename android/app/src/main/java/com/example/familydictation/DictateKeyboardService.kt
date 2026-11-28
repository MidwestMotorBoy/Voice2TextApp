package com.example.familydictation

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.inputmethodservice.InputMethodService
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.ImageButton
import android.widget.ProgressBar
import android.widget.TextView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Dictate keyboard: one big mic button plus switch-keyboard, space, delete and enter.
 * Tap to start, tap to stop; the cleaned-up text is typed into whatever box is open.
 * Never logs audio or transcript text, and always deletes the temporary recording.
 */
class DictateKeyboardService : InputMethodService() {
    private enum class State { IDLE, LISTENING, CLEANING_UP }

    private var state = State.IDLE
    private var errorMessage: String? = null
    private val main = Handler(Looper.getMainLooper())
    private val background: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var recorder: Recorder
    private val autoStop = Runnable { stopAndSend() }

    private var status: TextView? = null
    private var mic: ImageButton? = null
    private var spinner: ProgressBar? = null

    override fun onCreate() {
        super.onCreate()
        recorder = Recorder(this)
    }

    override fun onCreateInputView(): View {
        val view = layoutInflater.inflate(R.layout.keyboard, null)
        status = view.findViewById(R.id.status)
        mic = view.findViewById(R.id.mic)
        spinner = view.findViewById(R.id.spinner)

        mic?.setOnClickListener { onMicTapped() }
        view.findViewById<View>(R.id.key_space).setOnClickListener {
            currentInputConnection?.commitText(" ", 1)
        }
        view.findViewById<View>(R.id.key_delete).setOnClickListener {
            sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
        }
        view.findViewById<View>(R.id.key_enter).setOnClickListener { sendKeyChar('\n') }
        view.findViewById<View>(R.id.key_switch).apply {
            setOnClickListener { switchKeyboard() }
            setOnLongClickListener { showKeyboardPicker(); true }
        }
        render()
        return view
    }

    override fun onWindowHidden() {
        super.onWindowHidden()
        // The keyboard went away mid-recording: there is no stop button any more, so discard it.
        if (state == State.LISTENING) {
            main.removeCallbacks(autoStop)
            recorder.cancel()
            state = State.IDLE
            render()
        }
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        recorder.cancel()
        background.shutdown()
        super.onDestroy()
    }

    // --- Dictation ---

    private fun onMicTapped() {
        when (state) {
            State.IDLE -> start()
            State.LISTENING -> stopAndSend()
            State.CLEANING_UP -> Unit
        }
    }

    private fun start() {
        errorMessage = null
        when {
            !Settings.isConfigured(this) -> fail(getString(R.string.error_setup))
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ->
                fail(getString(R.string.error_mic))
            else -> try {
                recorder.start()
                state = State.LISTENING
                main.postDelayed(autoStop, MAX_MILLIS)
                render()
            } catch (e: Exception) {
                fail(getString(R.string.error_start))
            }
        }
    }

    private fun stopAndSend() {
        if (state != State.LISTENING) return
        main.removeCallbacks(autoStop)

        val recording = recorder.stop()
        if (recording == null || recording.second < 0.5 || recording.first.length() == 0L) {
            recording?.first?.delete()
            fail(getString(R.string.error_empty))
            return
        }
        val (file, seconds) = recording
        if (!isOnline()) {
            file.delete()
            fail(DictationError.OFFLINE.message)
            return
        }

        state = State.CLEANING_UP
        render()
        val address = Settings.address(this)
        val token = Settings.token(this)
        background.execute {
            val result = try {
                DictationClient.dictate(file, Math.ceil(seconds).toInt(), address, token)
            } catch (e: Exception) {
                DictationResult.Failure(DictationError.FAILED)
            } finally {
                file.delete()
            }
            main.post { finish(result) }
        }
    }

    private fun finish(result: DictationResult) {
        when (result) {
            is DictationResult.Success -> {
                val text = result.text.trim()
                if (text.isEmpty()) {
                    fail(getString(R.string.error_empty))
                } else {
                    currentInputConnection?.commitText("$text ", 1)
                    state = State.IDLE
                    render()
                }
            }
            is DictationResult.Failure -> fail(result.error.message)
        }
    }

    private fun fail(message: String) {
        errorMessage = message
        state = State.IDLE
        render()
    }

    private fun isOnline(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    // --- Keys ---

    private fun switchKeyboard() {
        if (!switchToPreviousInputMethod() && !switchToNextInputMethod(false)) showKeyboardPicker()
    }

    private fun showKeyboardPicker() {
        (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
    }

    // --- Display ---

    private fun render() {
        val statusView = status ?: return
        val micView = mic ?: return
        val busy = state == State.CLEANING_UP

        val error = errorMessage.takeIf { state == State.IDLE }
        statusView.text = when (state) {
            State.IDLE -> error ?: getString(R.string.status_idle)
            State.LISTENING -> getString(R.string.status_listening)
            State.CLEANING_UP -> getString(R.string.status_cleaning)
        }
        statusView.setTextColor(getColor(if (error != null) R.color.status_error else R.color.status_text))

        val color = when (state) {
            State.IDLE -> R.color.mic_idle
            State.LISTENING -> R.color.mic_listening
            State.CLEANING_UP -> R.color.mic_busy
        }
        micView.backgroundTintList = ColorStateList.valueOf(getColor(color))
        micView.isEnabled = !busy
        micView.setImageResource(
            when (state) {
                State.LISTENING -> R.drawable.ic_stop
                State.CLEANING_UP -> 0
                State.IDLE -> R.drawable.ic_mic
            }
        )
        micView.contentDescription =
            getString(if (state == State.LISTENING) R.string.mic_stop else R.string.mic_start)
        spinner?.visibility = if (busy) View.VISIBLE else View.GONE
    }

    private companion object {
        /** Longest single dictation before it stops and sends by itself. */
        const val MAX_MILLIS = 5 * 60 * 1000L
    }
}
