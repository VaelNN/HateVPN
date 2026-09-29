package com.leadaxe.lxbox.vpn

import android.util.Log
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PProfServer
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL




















object PProfClient {
    private const val TAG = "PProfClient"


    private val PORT_CANDIDATES = intArrayOf(6060, 6061, 6062, 6063, 6064, 6065)


    private const val CONNECT_TIMEOUT_MS = 2000


    fun goroutineDump(): String =
        String(fetch("goroutine?debug=2", readTimeoutMs = 5000), Charsets.UTF_8)





    fun cpuProfile(seconds: Int, headroomMs: Int = 5000): ByteArray =
        fetch("profile?seconds=$seconds", readTimeoutMs = seconds * 1000 + headroomMs)








    fun fetch(pathAndQuery: String, readTimeoutMs: Int): ByteArray =
        withServer { port ->
            httpGet("http://127.0.0.1:$port/debug/pprof/$pathAndQuery", readTimeoutMs)
        }




    private fun <T> withServer(block: (port: Int) -> T): T {
        var server: PProfServer? = null
        var boundPort = -1
        var lastErr: Throwable? = null
        for (port in PORT_CANDIDATES) {
            try {
                val s = Libbox.newPProfServer(port.toLong())
                s.start()
                server = s
                boundPort = port
                break
            } catch (t: Throwable) {
                lastErr = t
                Log.d(TAG, "pprof start on :$port failed: ${t.message}")
            }
        }
        if (server == null) {
            throw IllegalStateException(
                "pprof server: no free port in ${PORT_CANDIDATES.first()}..${PORT_CANDIDATES.last()}",
                lastErr,
            )
        }
        try {
            return block(boundPort)
        } finally {
            try {
                server.close()
            } catch (t: Throwable) {
                Log.w(TAG, "pprof close failed", t)
            }
        }
    }

    private fun httpGet(url: String, readTimeoutMs: Int): ByteArray {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = readTimeoutMs
        }
        try {
            val code = conn.responseCode
            if (code != 200) {
                throw IllegalStateException("pprof GET $url → HTTP $code")
            }
            val out = ByteArrayOutputStream()
            conn.inputStream.use { it.copyTo(out) }
            return out.toByteArray()
        } finally {
            conn.disconnect()
        }
    }
}
