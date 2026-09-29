package com.leadaxe.lxbox.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import java.io.File
import androidx.core.content.ContextCompat
import io.nekohasekai.libbox.TunOptions
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout








class BoxVpnService : VpnService(), PlatformInterfaceWrapper {

    companion object {
        private const val TAG = "BoxVpnService"
        const val ACTION_START = "com.leadaxe.lxbox.ACTION_START"
        const val ACTION_STOP = "com.leadaxe.lxbox.ACTION_STOP"

        const val ACTION_FORCE_STOP = "com.leadaxe.lxbox.ACTION_FORCE_STOP"
        const val ACTION_RELOAD = "com.leadaxe.lxbox.ACTION_RELOAD"
        const val ACTION_RESET_NETWORK = "com.leadaxe.lxbox.ACTION_RESET_NETWORK"

        const val ACTION_CLEAR_DNS_CACHE = "com.leadaxe.lxbox.ACTION_CLEAR_DNS_CACHE"


        const val ACTION_RECONNECT = "com.leadaxe.lxbox.ACTION_RECONNECT"

        const val ACTION_UPDATE_NOTIFICATION = "com.leadaxe.lxbox.ACTION_UPDATE_NOTIFICATION"


        const val ACTION_CLEAR_STALE_NOTIFICATION = "com.leadaxe.lxbox.ACTION_CLEAR_STALE_NOTIFICATION"








        fun clearStaleNotification(context: Context) {
            if (currentStatus != VpnStatus.Stopped) return
            if (!ServiceNotification.isStalePresent()) return
            Log.w(TAG, "[vpn §430] stale FGS notification from a dead service — bouncing service so AMS cancels it")
            val intent = Intent(context, BoxVpnService::class.java)
                .apply { action = ACTION_CLEAR_STALE_NOTIFICATION }
            runCatching { ContextCompat.startForegroundService(context, intent) }
                .onFailure { Log.w(TAG, "[vpn §430] bounce start failed: $it") }
        }
        const val BROADCAST_STATUS = "com.leadaxe.lxbox.BROADCAST_STATUS"
        const val EXTRA_STATUS = "status"





















        const val STOP_AWAIT_TIMEOUT_MS = 9_000L







        const val EXTRA_REVOKED = "revoked"









        const val EXTRA_CORE_ERROR = "core_error"




        @Volatile
        var currentStatus: VpnStatus = VpnStatus.Stopped
            private set






        @Volatile
        var currentSessionAllowBypass: Boolean = false
            private set






        @Volatile
        var tunnelStartedElapsedMs: Long = 0L
            private set






        @Volatile
        var currentRevoked: Boolean = false
            private set


        internal fun setCurrentStatus(s: VpnStatus, revoked: Boolean = false) {
            currentStatus = s


            currentRevoked = when (s) {
                VpnStatus.Starting, VpnStatus.Started -> false
                else -> revoked
            }


            when (s) {
                VpnStatus.Started ->
                    if (tunnelStartedElapsedMs == 0L) {
                        tunnelStartedElapsedMs = SystemClock.elapsedRealtime()
                    }
                VpnStatus.Stopped -> tunnelStartedElapsedMs = 0L
                else -> {   }
            }
        }






        @Volatile
        var stopReceiverAlive: Boolean = false
            private set

        internal fun setStopReceiverAlive(alive: Boolean) {
            stopReceiverAlive = alive
        }



        @Volatile
        private var stopCompleter: CompletableDeferred<Unit>? = null


        internal fun completeStopIfWaiting() {
            stopCompleter?.complete(Unit)
            stopCompleter = null
        }



        @JvmStatic
        fun perAppDebugLine(
            mode: String?,
            allowBypass: Boolean,
            applied: List<String>,
            missing: List<String>,
        ): String =
            "INFO per-app: mode=${mode ?: "off"} allow_bypass=$allowBypass " +
                "applied=${applied.size} [${applied.joinToString(",")}] " +
                "not_installed=${missing.size} [${missing.joinToString(",")}]"


        @Volatile
        var coreLogSink: io.flutter.plugin.common.EventChannel.EventSink? = null



        @Volatile
        var ccStatusSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        @Volatile
        var ccOutboundsSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        @Volatile
        var ccGroupsSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        @Volatile
        var ccConnectionsSink: io.flutter.plugin.common.EventChannel.EventSink? = null

        @Volatile
        var ccDnsQueriesSink: io.flutter.plugin.common.EventChannel.EventSink? = null


        @Volatile
        var ccTailscaleSink: io.flutter.plugin.common.EventChannel.EventSink? = null

        @Volatile
        var ccTailscalePingSink: io.flutter.plugin.common.EventChannel.EventSink? = null

        fun start(context: Context) {
            Log.d(TAG, "[vpn] companion.start() → startForegroundService, current status=${currentStatus.name}")
            val intent = Intent(context, BoxVpnService::class.java).apply { action = ACTION_START }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            Log.d(TAG, "[vpn] companion.stop() → sendBroadcast(ACTION_STOP), current status=${currentStatus.name}")





            VpnPlugin.notifyStopRequested()
            context.sendBroadcast(
                Intent(ACTION_STOP).setPackage(context.packageName)
            )
        }






        fun forceStop(context: Context) {
            Log.w(TAG, "[vpn] companion.forceStop() → sendBroadcast(ACTION_FORCE_STOP), current status=${currentStatus.name}")
            context.sendBroadcast(
                Intent(ACTION_FORCE_STOP).setPackage(context.packageName)
            )
        }

        fun reload(context: Context) {
            Log.d(TAG, "[vpn] companion.reload() current status=${currentStatus.name}")
            context.sendBroadcast(
                Intent(ACTION_RELOAD).setPackage(context.packageName)
            )
        }

        fun resetNetwork(context: Context) {
            Log.d(TAG, "[vpn] companion.resetNetwork() current status=${currentStatus.name}")
            context.sendBroadcast(
                Intent(ACTION_RESET_NETWORK).setPackage(context.packageName)
            )
        }





        fun clearDnsCache(context: Context) {
            Log.d(TAG, "[vpn] companion.clearDnsCache() current status=${currentStatus.name}")
            if (currentStatus == VpnStatus.Started ||
                currentStatus == VpnStatus.Starting
            ) {
                context.sendBroadcast(
                    Intent(ACTION_CLEAR_DNS_CACHE).setPackage(context.packageName)
                )
            } else {
                deleteCacheDbFile()
            }
        }




        internal fun deleteCacheDbFile() {
            val f = File(BoxApplication.application.filesDir, "cache.db")
            if (!f.exists()) {
                Log.i(TAG, "[dns] cache.db absent — nothing to clear")
                return
            }
            val ok = runCatching { f.delete() }.getOrDefault(false)
            Log.i(TAG, "[dns] cache.db delete=$ok (${f.absolutePath})")
        }






        fun updateNotification(context: Context) {
            context.sendBroadcast(
                Intent(ACTION_UPDATE_NOTIFICATION).setPackage(context.packageName)
            )
        }

        fun stopAwait(context: Context): Deferred<Unit> {
            Log.d(TAG, "[vpn] companion.stopAwait() current status=${currentStatus.name}")
            if (currentStatus == VpnStatus.Stopped) {
                return CompletableDeferred(Unit)
            }






            if (!stopReceiverAlive) {
                Log.w(TAG, "[vpn §361] stopAwait: no live receiver (status=${currentStatus.name}) — force Stopped")
                setCurrentStatus(VpnStatus.Stopped)
                runCatching {
                    context.sendBroadcast(
                        Intent(BROADCAST_STATUS)
                            .setPackage(context.packageName)
                            .putExtra(EXTRA_STATUS, VpnStatus.Stopped.name)
                    )
                }
                completeStopIfWaiting()
                return CompletableDeferred(Unit)
            }
            val completer = CompletableDeferred<Unit>()
            stopCompleter?.cancel()
            stopCompleter = completer
            context.sendBroadcast(
                Intent(ACTION_STOP).setPackage(context.packageName)
            )
            return completer
        }






        private val reconnectScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)


        @Volatile
        private var reconnecting: Boolean = false










        fun reconnect(context: Context) {
            Log.d(TAG, "[vpn] companion.reconnect() current status=${currentStatus.name}")
            if (reconnecting) {
                Log.w(TAG, "[vpn] reconnect already in progress — ignore")
                return
            }
            if (currentStatus == VpnStatus.Stopped) {
                start(context)
                return
            }
            reconnecting = true
            reconnectScope.launch {
                val stopped = try {


                    withTimeout(STOP_AWAIT_TIMEOUT_MS) { stopAwait(context).await(); true }
                } catch (t: Throwable) {
                    Log.w(TAG, "[vpn] reconnect: stop phase failed/timeout: ${t.message}")
                    false
                }
                if (stopped) {
                    start(context)
                } else {


                    Log.w(TAG, "[vpn] reconnect aborted — stop not confirmed")
                }
                reconnecting = false
            }
        }
    }





    private val service = BoxService(this, this)


    @JvmField var systemProxyAvailable = false
    @JvmField var systemProxyEnabled = false





    override fun onCreate() {
        super.onCreate()
        service.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return service.onStartCommand(intent, flags, startId)
    }

    override fun onBind(intent: Intent): IBinder? = super.onBind(intent) ?: android.os.Binder()

    override fun onDestroy() {
        service.onDestroy()


        currentSessionAllowBypass = false
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        service.onTaskRemoved(rootIntent)
        super.onTaskRemoved(rootIntent)
    }

    override fun onRevoke() {
        service.onRevoke()
        super.onRevoke()
    }





    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }



    private fun sortPerApp(pkg: String, applied: MutableList<String>, missing: MutableList<String>) {
        try {
            packageManager.getApplicationInfo(pkg, 0)
            applied.add(pkg)
        } catch (_: NameNotFoundException) {
            missing.add(pkg)
        }
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing vpn permission")

        val builder = Builder()
            .setSession("HateVPN")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)



        val allowBypass = BootReceiver.isAllowBypass(this)
        currentSessionAllowBypass = allowBypass
        if (allowBypass) {
            builder.allowBypass()
        }

        val inet4 = options.inet4Address
        while (inet4.hasNext()) { val a = inet4.next(); builder.addAddress(a.address(), a.prefix()) }
        val inet6 = options.inet6Address
        while (inet6.hasNext()) { val a = inet6.next(); builder.addAddress(a.address(), a.prefix()) }

        if (options.autoRoute) {


            val dnsServers = options.dnsServerAddress
            while (dnsServers.hasNext()) {
                val dns = dnsServers.next()
                if (dns.isNotEmpty()) builder.addDnsServer(dns)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                if (r4.hasNext()) { while (r4.hasNext()) builder.addRoute(r4.next().toIpPrefix()) }
                else if (options.inet4Address.hasNext()) builder.addRoute("0.0.0.0", 0)

                val r6 = options.inet6RouteAddress
                if (r6.hasNext()) { while (r6.hasNext()) builder.addRoute(r6.next().toIpPrefix()) }
                else if (options.inet6Address.hasNext()) builder.addRoute("::", 0)

                val x4 = options.inet4RouteExcludeAddress
                while (x4.hasNext()) builder.excludeRoute(x4.next().toIpPrefix())
                val x6 = options.inet6RouteExcludeAddress
                while (x6.hasNext()) builder.excludeRoute(x6.next().toIpPrefix())
            } else {
                val r4 = options.inet4RouteRange
                if (r4.hasNext()) { while (r4.hasNext()) { val a = r4.next(); builder.addRoute(a.address(), a.prefix()) } }
                val r6 = options.inet6RouteRange
                if (r6.hasNext()) { while (r6.hasNext()) { val a = r6.next(); builder.addRoute(a.address(), a.prefix()) } }
            }







            val perAppDebug = BootReceiver.isCoreLogsVerbose(this)
            val applied = if (perAppDebug) mutableListOf<String>() else null
            val missing = if (perAppDebug) mutableListOf<String>() else null
            var perAppMode: String? = null
            val incl = options.includePackage
            if (incl.hasNext()) {
                perAppMode = "allow"
                while (incl.hasNext()) {
                    val pkg = incl.next()
                    try { builder.addAllowedApplication(pkg); if (perAppDebug) sortPerApp(pkg, applied!!, missing!!) }
                    catch (_: NameNotFoundException) { missing?.add(pkg) }
                }
            }
            val excl = options.excludePackage
            if (excl.hasNext()) {
                perAppMode = if (perAppMode == null) "deny" else "allow+deny"
                while (excl.hasNext()) {
                    val pkg = excl.next()
                    try { builder.addDisallowedApplication(pkg); if (perAppDebug) sortPerApp(pkg, applied!!, missing!!) }
                    catch (_: NameNotFoundException) { missing?.add(pkg) }
                }
            }
            if (perAppDebug) {
                val line = perAppDebugLine(perAppMode, allowBypass, applied!!, missing!!)
                Log.i(TAG, line)
                service.writeDebugMessage(line)
            }
        }


        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            systemProxyAvailable = true
            systemProxyEnabled = true
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                    options.httpProxyBypassDomain.toList()
                )
            )
        } else {
            systemProxyAvailable = false
            systemProxyEnabled = false
        }

        val pfd = builder.establish() ?: error("android: the application is not prepared or is revoked")






        Log.w(TAG, "[fd §329] openTun fd=${pfd.fd} at=${SystemClock.elapsedRealtime()}ms")












        service.fileDescriptor.getAndSet(pfd)?.runCatching { close() }
            ?.onFailure { Log.w(TAG, "[fd §329] stale pfd close failed: ${it.message}") }
        return pfd.fd
    }

    override fun protect(fd: Int): Boolean = super.protect(fd)


    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
        service.sendNotification(notification)
    }


    override fun cancelNotification(identifier: String, typeID: Int) {
        service.cancelNotification(identifier, typeID)
    }
}
