package com.example.familydictation

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

/** Runs the client against a tiny local web server, so no real network or keys are needed. */
class DictationClientTest {
    private lateinit var server: ServerSocket
    private lateinit var audio: File
    private var status = 200
    private var body = ""
    private var seenPath: String? = null
    private var seenMethod: String? = null
    private var seenHeaders: Map<String, String> = emptyMap()
    private var seenBody: ByteArray = ByteArray(0)

    @Before
    fun setUp() {
        server = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        thread(isDaemon = true) { runCatching { answerOneRequest() } }
        audio = File.createTempFile("test-audio", ".m4a").apply { writeBytes(byteArrayOf(1, 2, 3)) }
    }

    @After
    fun tearDown() {
        server.close()
        audio.delete()
    }

    /** Reads one HTTP request, remembers it, and replies with the canned status and body. */
    private fun answerOneRequest() {
        server.accept().use { socket ->
            val input = socket.getInputStream()
            val headerBytes = ByteArrayOutputStream()
            while (!headerBytes.toString("ISO-8859-1").endsWith("\r\n\r\n")) {
                val next = input.read()
                if (next < 0) break
                headerBytes.write(next)
            }
            val lines = headerBytes.toString("ISO-8859-1").trim().split("\r\n")
            val requestLine = lines.first().split(" ")
            seenMethod = requestLine[0]
            seenPath = requestLine[1]
            seenHeaders = lines.drop(1).associate {
                it.substringBefore(":").trim().lowercase() to it.substringAfter(":").trim()
            }
            val length = seenHeaders["content-length"]?.toInt() ?: 0
            val received = ByteArray(length)
            var read = 0
            while (read < length) {
                val count = input.read(received, read, length - read)
                if (count < 0) break
                read += count
            }
            seenBody = received

            val bytes = body.toByteArray()
            val head = "HTTP/1.1 $status Test\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
            socket.getOutputStream().apply {
                write(head.toByteArray())
                write(bytes)
                flush()
            }
        }
    }

    private val address get() = "http://127.0.0.1:${server.localPort}"

    private fun send() = DictationClient.dictate(audio, seconds = 7, address = address, token = "test-token")

    private fun assertFails(expected: DictationError) {
        assertEquals(DictationResult.Failure(expected), send())
    }

    @Test
    fun successReturnsTextAndSendsHeadersAndAudio() {
        body = """{"text":"Clean text.","raw":"um clean text"}"""

        assertEquals(DictationResult.Success("Clean text.", "um clean text"), send())

        assertEquals("/dictate", seenPath)
        assertEquals("POST", seenMethod)
        assertEquals("Bearer test-token", seenHeaders["authorization"])
        assertEquals("audio/mp4", seenHeaders["content-type"])
        assertEquals("7", seenHeaders["x-duration-seconds"])
        assertEquals(listOf<Byte>(1, 2, 3), seenBody.toList())
    }

    @Test
    fun unauthorized() {
        status = 401
        body = """{"error":"unauthorized"}"""
        assertFails(DictationError.UNAUTHORIZED)
        assertEquals("Token not accepted, check setup", DictationError.UNAUTHORIZED.message)
    }

    @Test
    fun monthlyLimit() {
        status = 429
        assertFails(DictationError.LIMIT_REACHED)
        assertEquals("Monthly limit reached", DictationError.LIMIT_REACHED.message)
    }

    @Test
    fun tooLong() {
        status = 413
        assertFails(DictationError.TOO_LONG)
    }

    @Test
    fun serverError() {
        status = 502
        assertFails(DictationError.FAILED)
    }

    @Test
    fun badJson() {
        body = "not json"
        assertFails(DictationError.FAILED)
    }

    @Test
    fun serverNotReachableFailsInsteadOfHanging() {
        server.close()
        assertFails(DictationError.FAILED)
    }

    @Test
    fun badAddress() {
        val result = DictationClient.dictate(audio, 7, address = "  ", token = "test-token")
        assertEquals(DictationResult.Failure(DictationError.BAD_ADDRESS), result)
    }

    @Test
    fun endpointAcceptsDifferentWaysOfTypingTheAddress() {
        val expected = "https://worker.example.com/dictate"
        assertEquals(expected, DictationClient.endpoint("worker.example.com").toString())
        assertEquals(expected, DictationClient.endpoint(" https://worker.example.com/ ").toString())
        assertEquals(expected, DictationClient.endpoint("https://worker.example.com/dictate").toString())
        assertNull(DictationClient.endpoint(""))
        assertNull(DictationClient.endpoint("   "))
        assertNull(DictationClient.endpoint("two words.example.com"))
    }
}
