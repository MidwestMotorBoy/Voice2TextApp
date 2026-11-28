package com.example.familydictation

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.Toast

/** Setup: Worker address, family token, microphone permission, and turning the keyboard on. */
class SetupActivity : Activity() {
    private lateinit var address: EditText
    private lateinit var token: EditText
    private lateinit var allowMic: Button
    private lateinit var enableKeyboard: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_setup)

        address = findViewById(R.id.address)
        token = findViewById(R.id.token)
        allowMic = findViewById(R.id.allow_mic)
        enableKeyboard = findViewById(R.id.enable_keyboard)

        address.setText(Settings.address(this))
        token.setText(Settings.token(this))

        findViewById<Button>(R.id.save).setOnClickListener { save() }
        allowMic.setOnClickListener {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MIC)
        }
        enableKeyboard.setOnClickListener {
            startActivity(Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS))
        }
        findViewById<Button>(R.id.choose_keyboard).setOnClickListener {
            inputMethodManager().showInputMethodPicker()
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refresh()
    }

    private fun save() {
        val newAddress = address.text.toString()
        val newToken = token.text.toString()
        if (!Settings.isValid(newAddress, newToken)) {
            Toast.makeText(this, R.string.setup_incomplete, Toast.LENGTH_LONG).show()
            return
        }
        Settings.save(this, newAddress, newToken)
        Toast.makeText(this, R.string.setup_saved, Toast.LENGTH_SHORT).show()
    }

    private fun refresh() {
        val micAllowed = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        allowMic.setText(if (micAllowed) R.string.setup_mic_allowed else R.string.setup_mic_allow)
        allowMic.isEnabled = !micAllowed

        val keyboardOn = inputMethodManager().enabledInputMethodList.any { it.packageName == packageName }
        enableKeyboard.setText(if (keyboardOn) R.string.setup_enabled else R.string.setup_enable)
    }

    private fun inputMethodManager() = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager

    private companion object {
        const val REQUEST_MIC = 1
    }
}
