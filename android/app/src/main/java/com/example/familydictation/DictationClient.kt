package com.example.familydictation

import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Plain-language messages shown on the keyboard. */
enum class DictationError(val message: String) {
    UNAUTHORIZED("Token not accepted, check setup"),
    LIMIT_REACHED("Monthly limit reached"),
    TOO_LONG("Recording too long"),
    OFFLINE("No internet"),
    BAD_ADDRESS("Worker address looks wrong, check setup"),
    FAILED("Didn't work, try again"),
}

sealed class DictationResult {
    data class Success(val text: String, val raw: String) : DictationResult()
    data class Failure(val error: DictationError) : DictationResult()
}

/**
 * Sends one recording to the Worker and returns the cleaned-up text.
 * Blocking: call it off the main thread. Never logs audio or transcript text.
 */
object DictationClient {

    /**
     * Turns what the person typed in setup into the `/dictate` URL.
     * Accepts the address with or without `https://` and with or without a trailing slash.
     */
    fun endpoint(address: String): URL? {
        var trimmed = address.trim()
        if (trimmed.isEmpty() || trimmed.any { it.isWhitespace() }) return null
        val lower = trimmed.lowercase()
        if (!lower.startsWith("https://") && !lower.startsWith("http://")) trimmed = "https://$trimmed"
        trimmed = trimmed.trimEnd('/')
        if (trimmed.lowercase().endsWith("/dictate")) trimmed = trimmed.dropLast("/dictate".length)
        return try {
            val url = URL("$trimmed/dictate")
            if (url.host.isNullOrEmpty()) null else url
        } catch (e: Exception) {
            null
        }
    }

    fun dictate(audio: File, seconds: Int, address: String, token: String): DictationResult {
        val url = endpoint(address) ?: return DictationResult.Failure(DictationError.BAD_ADDRESS)
        var connection: HttpURLConnection? = null
        return try {
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 60_000
                doOutput = true
                setFixedLengthStreamingMode(audio.length())
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "audio/mp4")
                setRequestProperty("X-Duration-Seconds", seconds.coerceAtLeast(1).toString())
            }
            connection.outputStream.use { out -> audio.inputStream().use { it.copyTo(out) } }

            when (connection.responseCode) {
                200 -> parse(connection.inputStream.bufferedReader().use { it.readText() })
                401 -> DictationResult.Failure(DictationError.UNAUTHORIZED)
                413 -> DictationResult.Failure(DictationError.TOO_LONG)
                429 -> DictationResult.Failure(DictationError.LIMIT_REACHED)
                else -> DictationResult.Failure(DictationError.FAILED)
            }
        } catch (e: IOException) {
            DictationResult.Failure(DictationError.FAILED)
        } finally {
            connection?.disconnect()
        }
    }

    private fun parse(body: String): DictationResult = try {
        val json = JSONObject(body)
        DictationResult.Success(text = json.getString("text"), raw = json.optString("raw"))
    } catch (e: Exception) {
        DictationResult.Failure(DictationError.FAILED)
    }
}
