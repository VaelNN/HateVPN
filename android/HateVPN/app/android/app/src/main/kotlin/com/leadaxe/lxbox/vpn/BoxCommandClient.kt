package com.leadaxe.lxbox.vpn

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Connections
import io.nekohasekai.libbox.DnsQuery
import io.nekohasekai.libbox.GetURLResult
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.PoolSlotIterator
import io.nekohasekai.libbox.RuleIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TailscalePeer
import io.nekohasekai.libbox.TailscalePingHandler
import io.nekohasekai.libbox.TailscalePingResult
import io.nekohasekai.libbox.TailscalePingSession
import io.nekohasekai.libbox.TailscaleStatusHandler
import io.nekohasekai.libbox.TailscaleStatusSubscription
import io.nekohasekai.libbox.TailscaleStatusUpdate
import io.nekohasekai.libbox.URLTestOutboundResult
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference






























class BoxCommandClient {

    companion object {
        private const val TAG = "BoxCommandClient"








        private const val STATUS_INTERVAL_FAST = 100_000_000L
        private const val STATUS_INTERVAL_NORMAL = 500_000_000L



        private const val QUEUE_MAX = 4096

        private const val RECONNECT_BACKOFF_START_MS = 500L
        private const val RECONNECT_BACKOFF_MAX_MS = 8_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())


    private val statusClient = AtomicReference<CommandClient?>(null)
    private val screenClient = AtomicReference<CommandClient?>(null)
    private val profilerClient = AtomicReference<CommandClient?>(null)




    private val pingClient = AtomicReference<CommandClient?>(null)







    private val statusGen = AtomicInteger(0)
    private val screenGen = AtomicInteger(0)
    private val profilerGen = AtomicInteger(0)


    @Volatile
    private var tunnelAlive = false






    @Volatile private var statusIntervalNs = STATUS_INTERVAL_NORMAL


    @Volatile private var statusPaused = false



    fun startStatus() {
        tunnelAlive = true
        statusPaused = false
        connectStatus()
    }

    fun stopStatus() {
        tunnelAlive = false
        disconnectClient(statusClient, "stopStatus")
    }




    fun setStatusFast(fast: Boolean) {
        val want = if (fast) STATUS_INTERVAL_FAST else STATUS_INTERVAL_NORMAL
        if (statusIntervalNs == want) return
        statusIntervalNs = want
        if (tunnelAlive && !statusPaused) connectStatus()
    }



    fun pauseStatus() {
        if (statusPaused) return
        statusPaused = true
        disconnectClient(statusClient, "pauseStatus")
    }



    fun resumeStatus() {
        if (!statusPaused) return
        statusPaused = false
        if (tunnelAlive) connectStatus()
    }






    private val screenRefs = AtomicInteger(0)

    fun connectScreen() {


        val wasZero = screenRefs.getAndIncrement() == 0
        if (wasZero && !screenPaused) connectScreenClient()
    }

    fun disconnectScreen() {

        val n = screenRefs.updateAndGet { if (it > 0) it - 1 else 0 }
        if (n == 0) disconnectClient(screenClient, "disconnectScreen")
    }




    @Volatile private var screenPaused = false




    fun pauseScreen() {
        if (screenPaused) return
        screenPaused = true
        disconnectClient(screenClient, "pauseScreen")
    }




    fun resumeScreen() {
        if (!screenPaused) return
        screenPaused = false
        if (tunnelAlive && screenRefs.get() > 0) connectScreenClient()
    }


































    fun resyncForReopen() {

        screenRefs.set(0)
        screenPaused = false
        disconnectClient(screenClient, "resyncForReopen")



        disconnectClient(pingClient, "resyncForReopen")










        statusPaused = false
        statusIntervalNs = STATUS_INTERVAL_NORMAL
        if (tunnelAlive) connectStatus()
    }


    fun connectProfiler() = connectProfilerClient()
    fun disconnectProfiler() {

        disconnectClient(profilerClient, "disconnectProfiler")
    }


    fun shutdownAll() {
        tunnelAlive = false
        screenRefs.set(0)
        screenPaused = false
        statusPaused = false
        disconnectClient(statusClient, "shutdownAll")
        disconnectClient(screenClient, "shutdownAll")
        disconnectClient(profilerClient, "shutdownAll")
        disconnectClient(pingClient, "shutdownAll")
        stopTailscaleStatus()
        stopTailscalePing()
        screenAccumulator.set(null)
        profilerAccumulator.set(null)
    }



    private fun connectStatus() {
        if (statusPaused) return
        val gen = statusGen.incrementAndGet()
        runCatching {
            val options = CommandClientOptions().apply {
                addCommand(Libbox.CommandStatus)
                setStatusInterval(statusIntervalNs)
            }
            val client = CommandClient(StatusHandler(gen), options)
            client.connect()
            statusClient.getAndSet(client)?.runCatching { disconnect() }
        }.onFailure {
            Log.w(TAG, "connectStatus failed (gen=$gen): ${it.message}")
            scheduleReconnect(RECONNECT_BACKOFF_START_MS) { if (tunnelAlive && !statusPaused) connectStatus() }
        }
    }

    private fun connectScreenClient() {
        val gen = screenGen.incrementAndGet()
        ensureAccumulator(screenAccumulator)
        runCatching {
            val options = CommandClientOptions().apply {
                addCommand(Libbox.CommandOutbounds)
                addCommand(Libbox.CommandGroup)
                addCommand(Libbox.CommandConnections)
            }
            val client = CommandClient(ScreenHandler(gen), options)
            client.connect()
            screenClient.getAndSet(client)?.runCatching { disconnect() }
        }.onFailure { Log.w(TAG, "connectScreen failed (gen=$gen): ${it.message}") }
    }

    private fun connectProfilerClient() {
        val gen = profilerGen.incrementAndGet()
        ensureAccumulator(profilerAccumulator)
        runCatching {





            val options = CommandClientOptions().apply {
                addCommand(Libbox.CommandConnections)
                addCommand(Libbox.CommandDNS)
                setDNSIncludeAnswers(true)
            }
            val client = CommandClient(ProfilerHandler(gen), options)
            client.connect()
            profilerClient.getAndSet(client)?.runCatching { disconnect() }
        }.onFailure { Log.w(TAG, "connectProfiler failed (gen=$gen): ${it.message}") }
    }

    private fun disconnectClient(ref: AtomicReference<CommandClient?>, reason: String) {
        ref.getAndSet(null)?.runCatching { disconnect() }
            ?.onFailure { Log.w(TAG, "disconnect($reason) failed: ${it.message}") }
    }

    private fun scheduleReconnect(delayMs: Long, action: () -> Unit) {
        val capped = delayMs.coerceAtMost(RECONNECT_BACKOFF_MAX_MS)
        mainHandler.postDelayed({ runCatching { action() } }, capped)
    }








    private val tailscaleClient = AtomicReference<CommandClient?>(null)
    private val tailscaleSub = AtomicReference<TailscaleStatusSubscription?>(null)
    private val tailscaleGen = AtomicInteger(0)




    fun startTailscaleStatus() {
        stopTailscaleStatus()
        val gen = tailscaleGen.incrementAndGet()
        runCatching {
            val client = CommandClient(PingHandler(), CommandClientOptions())
            client.connect()
            tailscaleClient.getAndSet(client)?.runCatching { disconnect() }
            val sub = client.subscribeTailscaleStatus(TailscaleHandler(gen))
            tailscaleSub.getAndSet(sub)?.runCatching { close() }
        }.onFailure { Log.w(TAG, "startTailscaleStatus failed (gen=$gen): ${it.message}") }
    }

    fun stopTailscaleStatus() {
        tailscaleGen.incrementAndGet()
        tailscaleSub.getAndSet(null)?.runCatching { close() }
            ?.onFailure { Log.w(TAG, "tailscale sub close failed: ${it.message}") }
        disconnectClient(tailscaleClient, "stopTailscaleStatus")
    }


    private inner class TailscaleHandler(private val gen: Int) : TailscaleStatusHandler {
        override fun onStatusUpdate(update: TailscaleStatusUpdate?) {
            runCatching {
                if (gen != tailscaleGen.get() || update == null) return@runCatching
                val out = ArrayList<Map<String, Any>>()
                val iter = update.endpoints() ?: return@runCatching
                while (iter.hasNext()) {
                    val e = iter.next() ?: continue


                    val groups = ArrayList<Map<String, Any>>()
                    val gi = e.userGroups()
                    while (gi != null && gi.hasNext()) {
                        val g = gi.next() ?: continue
                        val peers = ArrayList<Map<String, Any>>()
                        val pi = g.peers()
                        while (pi != null && pi.hasNext()) {
                            val p = pi.next() ?: continue
                            peers.add(tailscalePeerMap(p))
                        }
                        groups.add(mapOf(
                            "user_id" to g.userID,
                            "login_name" to (g.loginName ?: ""),
                            "display_name" to (g.displayName ?: ""),
                            "peers" to peers,
                        ))
                    }
                    val m = HashMap<String, Any>()
                    m["tag"] = e.endpointTag ?: ""
                    m["backend_state"] = e.backendState ?: ""
                    m["state_text"] = e.stateText ?: ""
                    m["auth_url"] = e.authURL ?: ""
                    m["network_name"] = e.networkName ?: ""
                    m["magic_dns_suffix"] = e.magicDNSSuffix ?: ""
                    m["key_auth"] = e.keyAuth
                    e.self?.let { m["self"] = tailscalePeerMap(it) }
                    e.exitNode?.let { m["exit_node"] = tailscalePeerMap(it) }
                    m["user_groups"] = groups
                    out.add(m)
                }
                tailscaleEmitter.offer(out)
            }.onFailure { Log.w(TAG, "tailscale onStatusUpdate failed: ${it.javaClass.simpleName}") }
        }

        override fun onError(message: String?) {
            runCatching { Log.w(TAG, "tailscale status stream error (gen=$gen): $message") }
        }
    }



    private fun tailscalePeerMap(p: TailscalePeer): Map<String, Any> {
        val ips = ArrayList<String>()
        val iter = p.tailscaleIPs()
        while (iter != null && iter.hasNext()) iter.next()?.let { ips.add(it) }
        return mapOf(
            "stable_id" to (p.stableID ?: ""),
            "host_name" to (p.hostName ?: ""),
            "dns_name" to (p.dnsName ?: ""),
            "os" to (p.os ?: ""),
            "online" to p.online,
            "exit_node" to p.exitNode,
            "exit_node_option" to p.exitNodeOption,
            "sharee_node" to p.shareeNode,
            "expired" to p.expired,
            "key_expiry" to p.keyExpiry,
            "last_seen" to p.lastSeen,
            "ips" to ips,
        )
    }



    fun setTailscaleExitNode(tag: String, stableID: String): String? {
        val client = ensurePingClient() ?: return "no command client"
        return runCatching { client.setTailscaleExitNode(tag, stableID); null }
            .getOrElse { Log.w(TAG, "setTailscaleExitNode failed"); it.message ?: "failed" }
    }


    fun tailscaleLogout(tag: String): String? {
        val client = ensurePingClient() ?: return "no command client"
        return runCatching { client.tailscaleLogout(tag); null }
            .getOrElse { Log.w(TAG, "tailscaleLogout failed"); it.message ?: "failed" }
    }



    private val tailscalePingClient = AtomicReference<CommandClient?>(null)
    private val tailscalePingSession = AtomicReference<TailscalePingSession?>(null)
    private val tailscalePingGen = AtomicInteger(0)
    private val tailscalePingEmitter = SnapshotEmitter { BoxVpnService.ccTailscalePingSink }

    fun startTailscalePing(tag: String, peerIP: String) {
        stopTailscalePing()
        val gen = tailscalePingGen.incrementAndGet()
        runCatching {
            val client = CommandClient(PingHandler(), CommandClientOptions())
            client.connect()
            tailscalePingClient.getAndSet(client)?.runCatching { disconnect() }
            val session = client.startTailscalePing(tag, peerIP, TailscalePingCallback(gen))
            tailscalePingSession.getAndSet(session)?.runCatching { close() }
        }.onFailure {
            Log.w(TAG, "startTailscalePing failed (gen=$gen)")
            tailscalePingEmitter.offer(mapOf("error" to (it.message ?: "failed")))
        }
    }

    fun stopTailscalePing() {
        tailscalePingGen.incrementAndGet()
        tailscalePingSession.getAndSet(null)?.runCatching { close() }
        disconnectClient(tailscalePingClient, "stopTailscalePing")
    }


    private inner class TailscalePingCallback(private val gen: Int) : TailscalePingHandler {
        override fun onPingResult(result: TailscalePingResult?) {
            runCatching {
                if (gen != tailscalePingGen.get() || result == null) return@runCatching
                tailscalePingEmitter.offer(mapOf(
                    "latency_ms" to result.latencyMs,
                    "is_direct" to result.isDirect,
                    "endpoint" to (result.endpoint ?: ""),
                    "derp_region_code" to (result.derpRegionCode ?: ""),
                    "error" to (result.error ?: ""),
                ))
            }
        }

        override fun onError(message: String?) {
            runCatching {
                if (gen != tailscalePingGen.get()) return@runCatching
                tailscalePingEmitter.offer(mapOf("error" to (message ?: "failed")))
            }
        }
    }





    private fun anyClient(): CommandClient? =
        statusClient.get() ?: screenClient.get() ?: profilerClient.get()






    fun urlTestOutbound(tag: String, link: String, timeoutMs: Int): Map<String, Any> {
        val client = ensurePingClient()
            ?: return mapOf("delay" to 0, "error" to "command client not connected")
        return runCatching {
            val r: URLTestOutboundResult = client.urlTestOutbound(tag, link, timeoutMs)
            mapOf("delay" to r.getDelay(), "error" to r.getError())
        }.getOrElse { mapOf("delay" to 0, "error" to (it.message ?: "urlTestOutbound failed")) }
    }













    fun getUrlViaOutbound(
        tag: String,
        link: String,
        timeoutMs: Int,
        maxBytes: Int,
    ): Map<String, Any> {
        val client = ensurePingClient()
            ?: return mapOf("error" to "command client not connected")
        return runCatching {


            val r: GetURLResult = client.getURLViaOutbound(tag, link, timeoutMs, maxBytes, null)



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






    fun urlTestGroup(tag: String): Boolean {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "urlTestGroup: no command client (paused/down)")
            return false
        }
        return runCatching { client.urlTest(tag); true }
            .getOrElse { Log.w(TAG, "urlTestGroup failed: ${it.message}"); false }
    }










    private fun ensurePingClient(): CommandClient? {
        pingClient.get()?.let { return it }
        return runCatching {
            val options = CommandClientOptions()
            val client = CommandClient(PingHandler(), options)
            client.connect()
            if (pingClient.compareAndSet(null, client)) client
            else { client.runCatching { disconnect() }; pingClient.get() }
        }.getOrElse { Log.w(TAG, "ensurePingClient failed: ${it.message}"); null }
    }





    fun cancelPing() {
        disconnectClient(pingClient, "cancelPing")
    }




    fun getRules(): List<Map<String, Any>>? {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "getRules: no command client (paused/down)")
            return null
        }
        return runCatching {
            val out = ArrayList<Map<String, Any>>()
            val it: RuleIterator = client.getRules()
            while (it.hasNext()) {
                val r = it.next()
                out.add(mapOf(
                    "type" to r.getType(),
                    "payload" to r.getPayload(),
                    "action" to r.getAction(),
                    "isDNS" to r.getIsDNS(),
                ))
            }
            out
        }.getOrElse {
            Log.w(TAG, "getRules RPC failed: ${it.message}")
            null
        }
    }










    fun getGroups(): List<Map<String, Any>>? {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "getGroups: no command client (paused/down)")
            return null
        }
        return runCatching {
            val out = ArrayList<Map<String, Any>>()
            val it: OutboundGroupIterator = client.getGroups()
            while (it.hasNext()) out.add(serializeGroup(it.next()))
            out
        }.getOrElse {

            Log.d(TAG, "getGroups unavailable: ${it.message}")
            null
        }
    }













    fun getOutbounds(): List<Map<String, Any>>? {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "getOutbounds: no command client (paused/down)")
            return null
        }
        return runCatching {
            val out = ArrayList<Map<String, Any>>()
            val it = client.getOutbounds()
            while (it.hasNext()) {
                val item = it.next()
                out.add(mapOf(
                    "tag" to item.tag,
                    "type" to item.type,
                    "urlTestDelay" to item.urlTestDelay,
                    "urlTestTime" to item.urlTestTime,
                    "endpointState" to item.endpointState,
                    "idleSinceSeconds" to item.idleSinceSeconds,
                ))
            }
            out
        }.getOrElse {

            Log.d(TAG, "getOutbounds unavailable: ${it.message}")
            null
        }
    }
















    fun getDnsGroups(): List<Map<String, Any>>? {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "getDnsGroups: no command client (paused/down)")
            return null
        }
        return runCatching {
            val out = ArrayList<Map<String, Any>>()
            val it = client.getDNSGroups()
            while (it.hasNext()) {
                val g = it.next()
                val members = ArrayList<Map<String, Any>>()
                val mi = g.members()
                while (mi.hasNext()) {
                    val m = mi.next()
                    members.add(mapOf(
                        "tag" to m.tag,
                        "serverType" to m.serverType,
                        "clean" to m.clean,
                        "liveErrors" to m.liveErrors,
                        "lastErrorAgeMs" to m.lastErrorAgeMs,
                        "liveWins" to m.liveWins,
                        "current" to m.current,

                        "lastRttMs" to m.lastRTTMs,
                    ))
                }
                out.add(mapOf(
                    "tag" to g.tag,
                    "mode" to g.mode,
                    "current" to g.current,
                    "members" to members,
                ))
            }
            out
        }.getOrElse {

            Log.d(TAG, "getDnsGroups unavailable: ${it.message}")
            null
        }
    }















    fun getRunningConfig(): String? {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "getRunningConfig: no command client (paused/down)")
            return null
        }
        return runCatching {
            client.getRunningConfig().content().takeIf { it.isNotEmpty() }
        }.getOrElse {

            Log.d(TAG, "getRunningConfig unavailable: ${it.message}")
            null
        }
    }

    fun getPool(tag: String): List<Map<String, Any>>? {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "getPool: no command client (paused/down)")
            return null
        }
        return runCatching {
            val out = ArrayList<Map<String, Any>>()
            val it: PoolSlotIterator = client.getPool(tag)
            while (it.hasNext()) {
                val s = it.next()
                out.add(mapOf(
                    "slot" to s.slot,
                    "tag" to s.tag,
                    "delay" to s.delay,
                ))
            }
            out
        }.getOrElse {
            Log.w(TAG, "getPool RPC failed: ${it.message}")
            null
        }
    }













    fun selectedNodeLabel(configRaw: String): String? {
        val groups = getGroups() ?: return null
        val selectors = groups.filter { (it["tag"] as? String) != "GLOBAL" }
        if (selectors.isEmpty()) return null

        val finalTag = routeFinalTag(configRaw)
        val group = selectors.firstOrNull { (it["tag"] as? String) == finalTag }
            ?: selectors.first()

        val groupTag = group["tag"] as? String ?: return null
        val node = (group["selected"] as? String).orEmpty()
        return if (node.isNotEmpty()) "$groupTag: $node" else groupTag
    }



    private fun routeFinalTag(configRaw: String): String? = runCatching {
        org.json.JSONObject(configRaw)
            .optJSONObject("route")
            ?.optString("final")
            ?.takeIf { it.isNotEmpty() }
    }.getOrNull()



    private fun serializeGroup(g: OutboundGroup): Map<String, Any> {
        val items = ArrayList<Map<String, Any>>()
        val gi = g.getItems()
        while (gi.hasNext()) {
            val item = gi.next()
            items.add(mapOf(
                "tag" to item.tag,
                "type" to item.type,
                "urlTestDelay" to item.urlTestDelay,
                "urlTestTime" to item.urlTestTime,
            ))
        }
        return mapOf(
            "tag" to g.getTag(),
            "type" to g.getType(),
            "selectable" to g.getSelectable(),
            "selected" to g.getSelected(),
            "isExpand" to g.getIsExpand(),
            "items" to items,
        )
    }





    fun selectOutbound(group: String, tag: String): Boolean {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "selectOutbound: no command client (paused/down)")
            return false
        }
        return runCatching { client.selectOutbound(group, tag); true }
            .getOrElse { Log.w(TAG, "selectOutbound failed: ${it.message}"); false }
    }







    fun setEndpointEnabled(tag: String, enabled: Boolean): Map<String, String> {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "setEndpointEnabled: no command client (paused/down)")
            return mapOf("error" to "error", "message" to "no command client")
        }
        return runCatching {
            val r = client.setEndpointEnabled(tag, enabled)
            mapOf("state" to (r?.state ?: ""))
        }.getOrElse {
            val msg = it.message ?: it.toString()
            Log.w(TAG, "setEndpointEnabled($tag, $enabled) failed: $msg")
            mapOf("error" to endpointToggleErrorCode(msg), "message" to msg)
        }
    }

    private fun endpointToggleErrorCode(message: String): String =
        when (Regex("""code = (\w+)""").find(message)?.groupValues?.get(1)) {
            "NotFound" -> "not_found"
            "InvalidArgument" -> "invalid_argument"
            "FailedPrecondition" -> "failed_precondition"
            "Unavailable" -> "unavailable"
            else -> "error"
        }

    fun closeConnection(id: String): Boolean {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "closeConnection: no command client (paused/down)")
            return false
        }
        return runCatching { client.closeConnection(id); true }
            .getOrElse { Log.w(TAG, "closeConnection failed: ${it.message}"); false }
    }

    fun closeConnections(): Boolean {
        val client = ensurePingClient() ?: run {
            Log.w(TAG, "closeConnections: no command client (paused/down)")
            return false
        }
        return runCatching { client.closeConnections(); true }
            .getOrElse { Log.w(TAG, "closeConnections failed: ${it.message}"); false }
    }














    private val screenAccumulator = AtomicReference<Connections?>(null)
    private val profilerAccumulator = AtomicReference<Connections?>(null)

    private fun ensureAccumulator(ref: AtomicReference<Connections?>) {
        if (ref.get() == null) {
            runCatching { ref.compareAndSet(null, Connections()) }
                .onFailure { Log.w(TAG, "ensureAccumulator failed: ${it.message}") }
        }
    }





    private abstract inner class BaseHandler(protected val gen: Int) : CommandClientHandler {
        override fun connected() { runCatching { Log.d(TAG, "connected gen=$gen") } }
        override fun disconnected(message: String) {
            runCatching { Log.d(TAG, "disconnected gen=$gen: $message") }
        }
        override fun clearLogs() { runCatching { } }
        override fun setDefaultLogLevel(level: Int) { runCatching { } }
        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) { runCatching { } }
        override fun updateClashMode(newMode: String?) { runCatching { } }
        override fun writeLogs(messageList: LogIterator?) { runCatching { } }
        override fun writeStatus(message: StatusMessage?) { runCatching { } }
        override fun writeGroups(groups: OutboundGroupIterator?) { runCatching { } }
        override fun writeOutbounds(outbounds: OutboundGroupItemIterator?) { runCatching { } }
        override fun writeConnectionEvents(message: ConnectionEvents?) { runCatching { } }


        override fun writeDNSQuery(query: DnsQuery?) { runCatching { } }
    }


    private inner class StatusHandler(gen: Int) : BaseHandler(gen) {
        override fun disconnected(message: String) {
            runCatching {
                Log.d(TAG, "status disconnected gen=$gen: $message")
                if (gen == statusGen.get() && tunnelAlive) {
                    scheduleReconnect(RECONNECT_BACKOFF_START_MS) { if (tunnelAlive) connectStatus() }
                }
            }
        }

        override fun writeStatus(message: StatusMessage?) {
            runCatching {
                if (gen != statusGen.get()) return
                val m = message ?: return
                if (BoxVpnService.ccStatusSink == null) return
                val snap = HashMap<String, Any>(10)
                snap["uplink"] = m.getUplink()
                snap["downlink"] = m.getDownlink()
                snap["uplinkTotal"] = m.getUplinkTotal()
                snap["downlinkTotal"] = m.getDownlinkTotal()
                snap["memory"] = m.getMemory()
                snap["goroutines"] = m.getGoroutines()
                snap["connectionsIn"] = m.getConnectionsIn()
                snap["connectionsOut"] = m.getConnectionsOut()
                statusEmitter.offer(snap)
            }.onFailure { Log.w(TAG, "writeStatus failed: ${it.message}") }
        }
    }


    private inner class ScreenHandler(gen: Int) : BaseHandler(gen) {
        override fun writeOutbounds(outbounds: OutboundGroupItemIterator?) {
            runCatching {
                if (gen != screenGen.get()) return
                val it = outbounds ?: return
                if (BoxVpnService.ccOutboundsSink == null) return
                val list = ArrayList<Map<String, Any>>()
                while (it.hasNext()) {
                    val item = it.next()
                    list.add(mapOf(
                        "tag" to item.getTag(),
                        "type" to item.getType(),
                        "urlTestDelay" to item.getURLTestDelay(),
                        "urlTestTime" to item.getURLTestTime(),
                    ))
                }
                outboundsEmitter.offer(list)
            }.onFailure { Log.w(TAG, "writeOutbounds failed: ${it.message}") }
        }

        override fun writeGroups(groups: OutboundGroupIterator?) {
            runCatching {
                if (gen != screenGen.get()) return
                val it = groups ?: return
                if (BoxVpnService.ccGroupsSink == null) return
                val list = ArrayList<Map<String, Any>>()
                while (it.hasNext()) list.add(serializeGroup(it.next()))
                groupsEmitter.offer(list)
            }.onFailure { Log.w(TAG, "writeGroups failed: ${it.message}") }
        }

        override fun writeConnectionEvents(message: ConnectionEvents?) {
            applyConnectionEvents(message, screenGen, gen, screenAccumulator)
        }
    }






    private inner class ProfilerHandler(gen: Int) : BaseHandler(gen) {
        override fun writeConnectionEvents(message: ConnectionEvents?) {
            applyConnectionEvents(message, profilerGen, gen, profilerAccumulator)
        }

        override fun writeDNSQuery(query: DnsQuery?) {
            runCatching {
                val q = query ?: return
                if (BoxVpnService.ccDnsQueriesSink == null) return

                var pkg = ""
                var processPath = ""
                runCatching {
                    val pi = q.getProcessInfo()
                    if (pi != null) {
                        processPath = pi.getProcessPath() ?: ""
                        val pkgIt = pi.packageNames()
                        if (pkgIt != null && pkgIt.hasNext()) pkg = pkgIt.next() ?: ""
                    }
                }


                val answers = ArrayList<Map<String, Any>>()
                runCatching {
                    val it = q.answers()
                    while (it != null && it.hasNext()) {
                        val a = it.next() ?: continue
                        answers.add(mapOf(
                            "name" to a.getName(),
                            "type" to a.getType(),
                            "rdata" to a.getRData(),
                            "ttl" to a.getTTL(),
                        ))
                    }
                }


                var dnsServer = ""
                var dnsServerType = ""
                runCatching {
                    dnsServer = q.getDNSServer() ?: ""
                    dnsServerType = q.getDNSServerType() ?: ""
                }



                val outbound = ArrayList<String>()
                runCatching {
                    val it = q.outbound()
                    while (it != null && it.hasNext()) {
                        val s = it.next() ?: continue
                        if (s.isNotEmpty()) outbound.add(s)
                    }
                }




                val groupPath = ArrayList<String>()
                runCatching {
                    val it = q.groupPath()
                    while (it != null && it.hasNext()) {
                        val s = it.next() ?: continue
                        if (s.isNotEmpty()) groupPath.add(s)
                    }
                }
                val attempts = ArrayList<Map<String, Any>>()
                runCatching {
                    val it = q.attempts()
                    while (it != null && it.hasNext()) {
                        val a = it.next() ?: continue
                        attempts.add(mapOf(
                            "server" to a.server,
                            "serverType" to a.serverType,
                            "outcome" to a.outcome,

                            "rttMs" to a.rttMs,
                        ))
                    }
                }
                var fanned = false
                var survival = false
                runCatching {
                    fanned = q.fanned
                    survival = q.survival
                }



                dnsQueriesEmitter.offer(mapOf(
                    "domain" to q.getDomain(),
                    "queryType" to q.getQueryType(),
                    "rcode" to q.getRcode(),
                    "ttl" to q.getTTL(),
                    "source" to q.getSource(),
                    "failed" to q.getFailed(),
                    "error" to q.getError(),
                    "packageName" to pkg,
                    "processPath" to processPath,
                    "dnsServer" to dnsServer,
                    "dnsServerType" to dnsServerType,
                    "outbound" to outbound,
                    "answers" to answers,

                    "groupPath" to groupPath,
                    "attempts" to attempts,
                    "fanned" to fanned,
                    "survival" to survival,
                ))
            }.onFailure { Log.w(TAG, "writeDNSQuery failed: ${it.message}") }
        }
    }



    private inner class PingHandler : BaseHandler(0)












    private fun applyConnectionEvents(
        message: ConnectionEvents?,
        genRef: AtomicInteger,
        gen: Int,
        accRef: AtomicReference<Connections?>,
    ) {
        runCatching {
            if (gen != genRef.get()) return
            val events = message ?: return
            val acc = accRef.get() ?: run { ensureAccumulator(accRef); accRef.get() } ?: return


            acc.applyEvents(events)












            acc.filterState(Libbox.ConnectionStateAll.toInt())




            if (BoxVpnService.ccConnectionsSink == null) return
            connectionsEmitter.offer(serializeConnections(acc))
        }.onFailure { Log.w(TAG, "applyConnectionEvents failed: ${it.message}") }
    }



    private fun serializeConnections(acc: Connections): List<Map<String, Any>> {
        val list = ArrayList<Map<String, Any>>()
        val it = acc.iterator()
        while (it.hasNext()) {
            val c = it.next()


            var pkg = ""
            var processPath = ""
            runCatching {
                val pi = c.getProcessInfo()
                if (pi != null) {
                    processPath = pi.getProcessPath() ?: ""
                    val pkgIt = pi.packageNames()
                    if (pkgIt != null && pkgIt.hasNext()) pkg = pkgIt.next() ?: ""
                }
            }


            val chains = ArrayList<String>()
            runCatching {
                val chainIt = c.chain()
                while (chainIt != null && chainIt.hasNext()) {
                    chainIt.next()?.let { chains.add(it) }
                }
            }


            val detours = ArrayList<String>()
            runCatching {
                val detourIt = c.detour()
                while (detourIt != null && detourIt.hasNext()) {
                    detourIt.next()?.let { detours.add(it) }
                }
            }

            list.add(mapOf(
                "id" to c.getID(),
                "network" to c.getNetwork(),
                "domain" to c.getDomain(),
                "destination" to c.getDestination(),
                "rule" to c.getRule(),
                "uplink" to c.getUplinkTotal(),
                "downlink" to c.getDownlinkTotal(),
                "uplinkDelta" to c.getUplink(),
                "downlinkDelta" to c.getDownlink(),
                "outbound" to c.getOutbound(),
                "outboundType" to c.getOutboundType(),
                "protocol" to c.getProtocol(),
                "chains" to chains,
                "detours" to detours,
                "packageName" to pkg,
                "processPath" to processPath,
                "createdAt" to c.getCreatedAt(),
                "closedAt" to c.getClosedAt(),
            ))
        }
        return list
    }







    fun reEmitScreenConnections() {
        runCatching {
            val acc = screenAccumulator.get() ?: return
            connectionsEmitter.offer(serializeConnections(acc))
        }.onFailure { Log.w(TAG, "reEmitScreenConnections failed: ${it.message}") }
    }



    private val statusEmitter = SnapshotEmitter { BoxVpnService.ccStatusSink }
    private val outboundsEmitter = SnapshotEmitter { BoxVpnService.ccOutboundsSink }
    private val groupsEmitter = SnapshotEmitter { BoxVpnService.ccGroupsSink }
    private val connectionsEmitter = SnapshotEmitter { BoxVpnService.ccConnectionsSink }

    private val dnsQueriesEmitter = EventEmitter { BoxVpnService.ccDnsQueriesSink }

    private val tailscaleEmitter = SnapshotEmitter { BoxVpnService.ccTailscaleSink }




    private inner class SnapshotEmitter(private val sinkProvider: () -> EventChannel.EventSink?) {
        private val queue = LinkedBlockingQueue<Any>()
        private val scheduled = AtomicBoolean(false)

        fun offer(snapshot: Any) {



            queue.clear()
            queue.offer(snapshot)
            if (scheduled.compareAndSet(false, true)) {
                mainHandler.post(drainer)
            }
        }

        private val drainer = Runnable {
            scheduled.set(false)
            val sink = sinkProvider() ?: run { queue.clear(); return@Runnable }
            val latest = queue.poll() ?: return@Runnable
            queue.clear()
            runCatching { sink.success(latest) }
                .onFailure { Log.w(TAG, "emitter sink.success failed: ${it.message}") }
        }
    }







    private inner class EventEmitter(private val sinkProvider: () -> EventChannel.EventSink?) {
        private val queue = LinkedBlockingQueue<Any>()
        private val scheduled = AtomicBoolean(false)

        fun offer(event: Any) {
            if (queue.size < QUEUE_MAX) queue.offer(event)
            if (scheduled.compareAndSet(false, true)) {
                mainHandler.post(drainer)
            }
        }

        private val drainer = Runnable {
            scheduled.set(false)
            val sink = sinkProvider() ?: run { queue.clear(); return@Runnable }
            val batch = ArrayList<Any>()
            queue.drainTo(batch)
            if (batch.isEmpty()) return@Runnable
            runCatching { sink.success(batch) }
                .onFailure { Log.w(TAG, "dns emitter sink.success failed: ${it.message}") }
        }
    }
}
