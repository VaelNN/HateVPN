package com.leadaxe.lxbox.vpn

import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.DnsQuery
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking














object ProbeSession : CommandServerHandler {
    private const val TAG = "ProbeSession"

    private val server = AtomicReference<CommandServer?>(null)
    private val client = AtomicReference<CommandClient?>(null)





    private var probeScope: CoroutineScope? = null
    private var monitorOwned = false

    val active: Boolean get() = server.get() != null




    @Synchronized
    fun start(config: String): String {
        if (BoxService.commandClient != null) {
            return "VPN is running — test uses the live tunnel instead"
        }
        stopInternal()
        return runCatching {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            probeScope = scope


            runBlocking { DefaultNetworkMonitor.start(scope) { } }
            monitorOwned = true
            val cs = CommandServer(this, ProbePlatform)
            cs.start()
            server.set(cs)
            cs.startOrReloadService(config, OverrideOptions())
            val cl = CommandClient(ProbeClientHandler, CommandClientOptions())
            cl.connect()
            client.set(cl)
            Log.d(TAG, "probe session started")
            ""
        }.getOrElse {
            Log.e(TAG, "probe start failed", it)
            stopInternal()
            it.message ?: "probe start failed"
        }
    }




    fun urlTest(tag: String, link: String, timeoutMs: Int): Map<String, Any> {
        val cl = client.get()
            ?: return mapOf("delay" to 0, "error" to "probe session not running")
        return runCatching {
            val r = cl.urlTestOutbound(tag, link, timeoutMs)
            mapOf("delay" to r.delay, "error" to (r.error ?: ""))
        }.getOrElse {
            mapOf("delay" to 0, "error" to (it.message ?: "urlTestOutbound failed"))
        }
    }







    fun getUrl(tag: String, link: String, timeoutMs: Int, maxBytes: Int): Map<String, Any> {
        val cl = client.get()
            ?: return mapOf("error" to "probe session not running")
        return runCatching {
            val r = cl.getURLViaOutbound(tag, link, timeoutMs, maxBytes, null)

            mapOf(
                "status" to r.status(),
                "content" to r.content(),
                "truncated" to r.truncated(),
                "contentType" to r.contentType(),
                "remoteAddr" to r.remoteAddr(),
                "elapsedMs" to r.elapsedMs(),
                "error" to "",
            )
        }.getOrElse {
            mapOf("error" to (it.message ?: "getURLViaOutbound failed"))
        }
    }

    @Synchronized
    fun stop() = stopInternal()

    private fun stopInternal() {
        client.getAndSet(null)?.let { runCatching { it.disconnect() } }
        server.getAndSet(null)?.let {
            runCatching { it.closeService() }
            runCatching { it.close() }
            Log.d(TAG, "probe session stopped")
        }
        if (monitorOwned) {
            monitorOwned = false


            if (BoxService.commandClient == null) {
                runCatching { runBlocking { DefaultNetworkMonitor.stop() } }
            }
        }
        probeScope?.cancel()
        probeScope = null
    }



    override fun serviceReload() {}




    override fun serviceStop() {
        Thread { runCatching { stop() } }.start()
    }

    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}



    override fun connectSSHAgent(): Int =
        throw UnsupportedOperationException("SSH agent not supported")

    override fun triggerNativeCrash() {}

    override fun writeDebugMessage(message: String) {
        runCatching { Log.d(TAG, "[core] $message") }
    }




    private object ProbePlatform : PlatformInterfaceWrapper {
        override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {}
    }


    private object ProbeClientHandler : CommandClientHandler {
        override fun connected() { runCatching { Log.d(TAG, "client connected") } }
        override fun disconnected(message: String) {
            runCatching { Log.d(TAG, "client disconnected: $message") }
        }
        override fun clearLogs() { runCatching { } }
        override fun setDefaultLogLevel(level: Int) { runCatching { } }
        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {
            runCatching { }
        }
        override fun updateClashMode(newMode: String?) { runCatching { } }
        override fun writeLogs(messageList: LogIterator?) { runCatching { } }
        override fun writeStatus(message: StatusMessage?) { runCatching { } }
        override fun writeGroups(groups: OutboundGroupIterator?) { runCatching { } }
        override fun writeOutbounds(outbounds: OutboundGroupItemIterator?) { runCatching { } }
        override fun writeConnectionEvents(message: ConnectionEvents?) { runCatching { } }

        override fun writeDNSQuery(query: DnsQuery?) { runCatching { } }
    }
}
