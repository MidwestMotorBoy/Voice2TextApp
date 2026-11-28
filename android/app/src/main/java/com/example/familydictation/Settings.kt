package com.example.familydictation

import android.content.Context

/**
 * What the person entered in setup, kept in the app's private storage.
 * The token is capped and can be revoked on the Worker, so private SharedPreferences is enough.
 */
object Settings {
    private const val FILE = "settings"
    private const val KEY_ADDRESS = "workerAddress"
    private const val KEY_TOKEN = "familyToken"

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun address(context: Context): String = prefs(context).getString(KEY_ADDRESS, "") ?: ""

    fun token(context: Context): String = prefs(context).getString(KEY_TOKEN, "") ?: ""

    fun save(context: Context, address: String, token: String) {
        prefs(context).edit()
            .putString(KEY_ADDRESS, address.trim())
            .putString(KEY_TOKEN, token.trim())
            .apply()
    }

    fun isValid(address: String, token: String): Boolean =
        DictationClient.endpoint(address) != null && token.isNotBlank()

    fun isConfigured(context: Context): Boolean = isValid(address(context), token(context))
}
