package com.leadaxe.lxbox.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.leadaxe.lxbox.R
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import io.nekohasekai.libbox.StringIterator
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference














class BoxService(
    private val service: Service,
    private val platformInterface: PlatformInterface,
) : CommandServerHandler {

    companion object {
        private const val TAG = "BoxService"





        @Volatile
        @JvmStatic
        var coreLogsVerbose: Boolean = false




        private const val NOTIFICATION_SNAPSHOT_DELAY_MS = 3000L





        @Volatile
        var commandClient: BoxCommandClient? = null
            private set
    }



    private var serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var watchdogJob: kotlinx.coroutines.Job? = null








    private var forceStopScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun resetScope() {
        serviceScope.cancel()
        serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        forceStopScope.cancel()
        forceStopScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }





    val fileDescriptor = AtomicReference<ParcelFileDescriptor?>(null)


    private val commandServer = AtomicReference<CommandServer?>(null)









    @Volatile
    private var receiverRegistered = false
        set(value) {
            field = value
            BoxVpnService.setStopReceiverAlive(value)
        }
    private var status = VpnStatus.Stopped

    private val notification: ServiceNotification by lazy { ServiceNotification(service) }

    private val receiver = object : BroadcastReceiver() {















        private fun offloadFromMain(action: String, block: () -> Unit) {
            val pending = goAsync()
            serviceScope.launch {
                try {
                    block()
                } catch (t: Throwable) {
                    Log.e(TAG, "$action failed", t)
                } finally {
                    runCatching { pending.finish() }
                        .onFailure { Log.e(TAG, "$action: finish() failed", it) }
                }
            }
        }

        override fun onReceive(context: Context, intent: Intent) {
            Log.d(TAG, "[vpn] service.receiver.onReceive action=${intent.action} status=${status.name} registered=$receiverRegistered")
            when (intent.action) {
                BoxVpnService.ACTION_STOP -> doStop()
                BoxVpnService.ACTION_FORCE_STOP -> doForceStop()
                BoxVpnService.ACTION_RECONNECT -> {


                    Log.d(TAG, "[vpn] receiver: ACTION_RECONNECT → BoxVpnService.reconnect()")
                    runCatching { BoxVpnService.reconnect(service.applicationContext) }
                        .onFailure { Log.e(TAG, "ACTION_RECONNECT failed", it) }
                }
                BoxVpnService.ACTION_RELOAD -> {




                    Log.d(TAG, "[vpn] receiver: ACTION_RELOAD → serviceReload() (off-main)")
                    offloadFromMain("ACTION_RELOAD") { serviceReload() }
                }
                BoxVpnService.ACTION_RESET_NETWORK -> {

                    Log.d(TAG, "[vpn] receiver: ACTION_RESET_NETWORK → cs.resetNetwork() (off-main)")
                    offloadFromMain("ACTION_RESET_NETWORK") {
                        commandServer.get()?.resetNetwork()
                    }
                }
                BoxVpnService.ACTION_CLEAR_DNS_CACHE -> {








                    Log.d(TAG, "[vpn] receiver: ACTION_CLEAR_DNS_CACHE → delete cache.db + serviceReload() (off-main)")
                    offloadFromMain("ACTION_CLEAR_DNS_CACHE") {
                        BoxVpnService.deleteCacheDbFile()
                        serviceReload()
                    }
                }
                BoxVpnService.ACTION_UPDATE_NOTIFICATION -> {





                    if (status == VpnStatus.Started) {
                        runCatching {
                            notification.show(
                                ConfigManager.notificationTitle,
                                ConfigManager.notificationText.ifEmpty {
                                    L10n.str(service, R.string.status_connected)
                                },
                            )
                        }.onFailure { Log.e(TAG, "ACTION_UPDATE_NOTIFICATION failed", it) }
                    }
                }
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) onIdleModeChanged()
                }
                Intent.ACTION_SCREEN_OFF -> {
                    Log.d(TAG, "[vpn] SCREEN_OFF → pause")
                    commandServer.get()?.pause()
                }
                Intent.ACTION_SCREEN_ON -> {


                    if (BootReceiver.getBackgroundMode(service) == BootReceiver.BG_MODE_ALWAYS) {
                        Log.d(TAG, "[vpn] SCREEN_ON → wake")
                        commandServer.get()?.wake()
                    }







                    Log.d(TAG, "[vpn] SCREEN_ON → rebindStaleEndpoints")
                    runCatching { commandServer.get()?.rebindStaleEndpoints() }
                        .onFailure { Log.e(TAG, "rebindStaleEndpoints failed", it) }
                }
            }
        }
    }





    fun onCreate() {







        BoxApplication.initialize(service.applicationContext)
    }





















    fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "[vpn] onStartCommand action=${intent?.action} status=${status.name} startId=$startId receiverRegistered=$receiverRegistered")
        if (intent?.action == BoxVpnService.ACTION_CLEAR_STALE_NOTIFICATION) {





            if (status != VpnStatus.Stopped) {




                return Service.START_STICKY
            }
            runCatching {
                notification.show(
                    ConfigManager.notificationTitle,
                    L10n.str(service, R.string.notification_status_starting),
                )
            }
            notification.stop()
            service.stopSelf(startId)
            Log.w(TAG, "[vpn §430] bounce done — foreground shown and removed, stopSelf($startId)")
            return Service.START_NOT_STICKY
        }
        if (intent == null) {
            val n = BootReceiver.noteStickyRestart(service)
            Log.w(TAG, "[vpn §428] sticky restart #$n (limit=${BootReceiver.STICKY_RESTART_LIMIT} per ${BootReceiver.STICKY_RESTART_WINDOW_MS / 1000}s)")
            if (n >= BootReceiver.STICKY_RESTART_LIMIT) {
                notification.showAlert(
                    L10n.str(service, R.string.sticky_restart_storm_title),
                    L10n.str(service, R.string.sticky_restart_storm_text),
                )
                service.stopSelf()
                return Service.START_NOT_STICKY
            }
        }
        try {
            notification.show(
                ConfigManager.notificationTitle,
                L10n.str(service, R.string.notification_status_starting),
            )
        } catch (t: Throwable) {



            Log.e(TAG, "[vpn §428] startForeground failed — stopSelf", t)
            service.stopSelf()
            return Service.START_NOT_STICKY
        }

        if (status != VpnStatus.Stopped) {
            Log.w(TAG, "[vpn] onStartCommand GUARD — status=${status.name} != Stopped, silent return")
            return Service.START_STICKY
        }
        resetScope()
        setStatus(VpnStatus.Starting)


        coreLogsVerbose = BootReceiver.isCoreLogsVerbose(service)

        if (!receiverRegistered) {
            val mode = BootReceiver.getBackgroundMode(service)
            Log.d(TAG, "[vpn] registerReceiver from onStartCommand mode=$mode")
            ContextCompat.registerReceiver(service, receiver, IntentFilter().apply {
                addAction(BoxVpnService.ACTION_STOP)
                addAction(BoxVpnService.ACTION_FORCE_STOP)
                addAction(BoxVpnService.ACTION_RECONNECT)
                addAction(BoxVpnService.ACTION_RELOAD)
                addAction(BoxVpnService.ACTION_RESET_NETWORK)
                addAction(BoxVpnService.ACTION_CLEAR_DNS_CACHE)
                addAction(BoxVpnService.ACTION_UPDATE_NOTIFICATION)



                addAction(Intent.ACTION_SCREEN_ON)

                when (mode) {
                    BootReceiver.BG_MODE_LAZY -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                        }
                    }
                    BootReceiver.BG_MODE_ALWAYS -> {
                        addAction(Intent.ACTION_SCREEN_OFF)
                    }
                }
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            receiverRegistered = true
        }

        serviceScope.launch {
            try {
                BoxApplication.libboxReady.await()
                startCommandServer()
                startSingbox()
            } catch (t: Throwable) {
                Log.e(TAG, "Start failed", t)

                stopAndAlert(t.message
                    ?: L10n.str(service, R.string.stop_alert_unknown_error))
            }
        }
        return Service.START_STICKY
    }

    fun onDestroy() {
        Log.d(TAG, "[vpn] onDestroy status=${status.name} receiverRegistered=$receiverRegistered")
        serviceScope.cancel()
        if (receiverRegistered) {
            runCatching { service.unregisterReceiver(receiver) }
            receiverRegistered = false
        }
        if (BoxVpnService.currentStatus != VpnStatus.Stopped) {
            BoxVpnService.setCurrentStatus(VpnStatus.Stopped)
            runCatching { LxBoxTileService.refreshTile(service.applicationContext) }
                .onFailure { Log.w(TAG, "refreshTile in onDestroy failed: ${it.message}") }
        }
    }

    fun onTaskRemoved(rootIntent: Intent?) {
        if (!BootReceiver.isKeepOnExit(service)) {
            Log.d(TAG, "App removed from recents — stopping VPN")
            doStop()
        }
    }

    fun onRevoke() {
        Log.d(TAG, "onRevoke — VPN taken by another app")

        closeFileDescriptor("onRevoke")
        closeCommandServerAtomic("revoke")

        if (receiverRegistered) {
            runCatching { service.unregisterReceiver(receiver) }
            receiverRegistered = false
        }
        notification.stop()






        setStatus(
            VpnStatus.Stopped,
            error = "Another VPN app took the system VPN slot " +
                "(e.g. an always-on VPN). Start again to reconnect.",
            revoked = true,
        )
        serviceScope.cancel()
        service.stopSelf()
    }















    private fun closeFileDescriptor(reason: String) {
        val pfd = fileDescriptor.getAndSet(null)



        val fd = pfd?.runCatching { fd }?.getOrNull()

        Log.w(TAG, "[fd §329] close($reason) fd=${fd ?: "already-closed"} at=${SystemClock.elapsedRealtime()}ms")
        pfd?.runCatching { close() }
            ?.onFailure { Log.w(TAG, "closeFileDescriptor($reason): close failed: ${it.message}") }
    }

    private fun closeCommandServerAtomic(reason: String) {


        runCatching { commandClient?.shutdownAll() }
            .onFailure { Log.w(TAG, "closeCommandServerAtomic($reason): commandClient shutdown failed: ${it.message}") }
        commandClient = null
        val cs = commandServer.getAndSet(null) ?: return





















        runCatching { cs.close() }
            .onFailure { Log.w(TAG, "closeCommandServerAtomic($reason): close failed: ${it.message}") }
        Log.w(TAG, "[fd §330] listener closed($reason) at=${SystemClock.elapsedRealtime()}ms")

        runCatching { cs.closeService() }.onFailure {
            Log.e(TAG, "closeCommandServerAtomic($reason): closeService failed", it)
            runCatching { cs.setError("android: $reason close service: ${it.message}") }
        }
    }

    private suspend fun startSingbox() {
        try {
            BoxApplication.libboxReady.await()
        } catch (t: Throwable) {
            stopAndAlert(L10n.str(
                service, R.string.stop_alert_libbox_init_failed, t.message ?: ""))
            return
        }

        val config = ConfigManager.load()
        if (config.isBlank() || config == "{}") {
            stopAndAlert(L10n.str(service, R.string.stop_alert_empty_config))
            return
        }




        DefaultNetworkMonitor.start(serviceScope) {
            Log.d(TAG, "[vpn] interface switch → resetNetwork()")
            runCatching { commandServer.get()?.resetNetwork() }
                .onFailure { Log.e(TAG, "auto resetNetwork failed", it) }
        }




        val cs = commandServer.get() ?: run {
            stopAndAlert(L10n.str(service, R.string.stop_alert_no_command_server))
            return
        }

        try {
            cs.startOrReloadService(config, buildOverrideOptions(config))
        } catch (t: Throwable) {




            val core = t.message ?: ""
            stopAndAlert(
                L10n.str(service, R.string.stop_alert_start_failed, core),
                coreError = core,
            )
            return
        }















        if (runCatching { cs.needWIFIState() }.getOrDefault(false)) {






            val needed = mutableListOf<String>()
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                needed += android.Manifest.permission.ACCESS_FINE_LOCATION
            } else {
                needed += android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            }
            if (Build.VERSION.SDK_INT >= 33) {
                needed += "android.permission.NEARBY_WIFI_DEVICES"
            }
            val missing = needed.filter {
                service.checkSelfPermission(it) !=
                    android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            if (missing.isNotEmpty()) {
                Log.e(TAG, "[vpn] config requires WIFI state but missing: $missing")


                stopAndAlert("alert:permission_location:${missing.joinToString(",")}")
                return
            }
            Log.d(TAG, "[vpn] sing-box uses WIFI state, all permissions granted: $needed")
        }



















        if (!currentCoroutineContext().isActive) {
            Log.w(TAG, "[vpn §361] start cancelled while blocked — skip setStatus(Started)")
            return
        }










        if (status != VpnStatus.Starting) {
            Log.w(TAG, "[vpn §387] status=${status.name} after start returned — skip setStatus(Started)")
            return
        }
        setStatus(VpnStatus.Started)




        runCatching {
            val cc = BoxCommandClient()
            commandClient = cc
            cc.startStatus()
        }.onFailure { Log.w(TAG, "BoxCommandClient.startStatus failed: ${it.message}") }

        withContext(Dispatchers.Main) {


            notification.show(
                ConfigManager.notificationTitle,
                ConfigManager.notificationText.ifEmpty {
                    L10n.str(service, R.string.status_connected)
                },
            )
        }
    }



    private fun startCommandServer() {



        runCatching { ProbeSession.stop() }
        val cs = CommandServer(this, platformInterface)
        cs.start()
        commandServer.set(cs)
    }

    private fun doStop() {
        Log.d(TAG, "[vpn] doStop ENTER status=${status.name} receiverRegistered=$receiverRegistered")
        if (status == VpnStatus.Stopped || status == VpnStatus.Stopping) {
            Log.w(TAG, "[vpn] doStop GUARD — already ${status.name}, return without action")
            return
        }
        setStatus(VpnStatus.Stopping)

        if (receiverRegistered) {
            Log.d(TAG, "[vpn] unregisterReceiver from doStop")
            runCatching { service.unregisterReceiver(receiver) }
            receiverRegistered = false
        }
        notification.stop()

        serviceScope.launch {
            closeFileDescriptor("doStop")
            DefaultNetworkMonitor.stop()
            closeCommandServerAtomic("doStop")

            withContext(Dispatchers.Main) {
                Log.d(TAG, "[vpn] doStop cleanup done → setStatus(Stopped) + stopSelf()")
                setStatus(VpnStatus.Stopped)
                service.stopSelf()
            }
        }
    }























    private fun doForceStop() {
        Log.w(TAG, "[vpn] doForceStop ENTER status=${status.name} receiverRegistered=$receiverRegistered")
        if (status == VpnStatus.Stopped) {
            Log.d(TAG, "[vpn] doForceStop — already Stopped, no-op")
            return
        }



        if (receiverRegistered) {
            runCatching { service.unregisterReceiver(receiver) }
            receiverRegistered = false
        }
        notification.stop()
        setStatus(VpnStatus.Stopped)
        Log.w(TAG, "[vpn] doForceStop — UI/notification stopped, teardown+stopSelf on forceStopScope")





        forceStopScope.launch {
            runCatching {
                withTimeout(2_000) { closeFileDescriptor("doForceStop") }
            }.onFailure { Log.w(TAG, "doForceStop: closeFileDescriptor timeout/fail: ${it.message}") }
            runCatching {
                withTimeout(2_000) { DefaultNetworkMonitor.stop() }
            }.onFailure { Log.w(TAG, "doForceStop: DefaultNetworkMonitor.stop timeout/fail: ${it.message}") }
            runCatching {
                withTimeout(2_000) { closeCommandServerAtomic("doForceStop") }
            }.onFailure { Log.w(TAG, "doForceStop: closeCommandServer timeout/fail: ${it.message}") }
            Log.d(TAG, "[vpn] doForceStop — teardown done → stopSelf()")
            withContext(Dispatchers.Main) { service.stopSelf() }
        }
    }




    private suspend fun stopAndAlert(message: String, coreError: String? = null) {
        Log.e(TAG, "stopAndAlert: $message")








        closeFileDescriptor("stopAndAlert")
        DefaultNetworkMonitor.stop()
        closeCommandServerAtomic("stopAndAlert: $message")

        withContext(Dispatchers.Main) {
            notification.show(
                L10n.str(service, R.string.notification_error_title), message)
            if (receiverRegistered) {
                runCatching { service.unregisterReceiver(receiver) }
                receiverRegistered = false
            }
            notification.stop()
            setStatus(VpnStatus.Stopped, error = message, coreError = coreError)
            service.stopSelf()
        }
    }




    private fun setStatus(
        newStatus: VpnStatus,
        error: String? = null,
        revoked: Boolean = false,
        coreError: String? = null,
    ) {







        if (status == newStatus && error == null) {
            Log.d(TAG, "[vpn] setStatus(${newStatus.name}) — same status, dedup (no broadcast)")
            return
        }
        Log.d(TAG, "[vpn] setStatus(${newStatus.name})${if (error != null) " error=$error" else ""} — sendBroadcast")
        status = newStatus
        BoxVpnService.setCurrentStatus(newStatus, revoked)




        val appCtx = service.applicationContext
        when (newStatus) {
            VpnStatus.Started -> {
                BootReceiver.resetStickyRestarts(appCtx)
                BootReceiver.setVpnDesired(appCtx, true)
                watchdogJob?.cancel()
                watchdogJob = VpnWatchdog.startTicker(appCtx, serviceScope) {
                    status == VpnStatus.Started
                }
            }
            VpnStatus.Stopped -> {
                BootReceiver.setVpnDesired(appCtx, false)
                watchdogJob?.cancel()
                watchdogJob = null
                VpnWatchdog.disarm(appCtx)
            }
            else -> {}
        }




        if (newStatus == VpnStatus.Stopped) {
            BoxVpnService.completeStopIfWaiting()
        }
        service.sendBroadcast(
            Intent(BoxVpnService.BROADCAST_STATUS).apply {
                `package` = service.packageName
                putExtra(BoxVpnService.EXTRA_STATUS, newStatus.name)
                if (error != null) putExtra("error", error)
                if (revoked) putExtra(BoxVpnService.EXTRA_REVOKED, true)

                if (!coreError.isNullOrEmpty()) {
                    putExtra(BoxVpnService.EXTRA_CORE_ERROR, coreError)
                }
            }
        )
        runCatching { LxBoxTileService.refreshTile(service.applicationContext) }
            .onFailure { Log.w(TAG, "refreshTile failed: ${it.message}") }
        runCatching { QuickShortcuts.refresh(service.applicationContext) }
            .onFailure { Log.w(TAG, "QuickShortcuts.refresh failed: ${it.message}") }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun onIdleModeChanged() {
        val cs = commandServer.get() ?: return
        if (BoxApplication.powerManager.isDeviceIdleMode) cs.pause() else cs.wake()
    }














    override fun serviceReload() {
        runCatching {
            val cs = commandServer.get() ?: run {
                Log.w(TAG, "serviceReload: commandServer == null, treating as fresh start")
                notification.stop()
                setStatus(VpnStatus.Starting)
                serviceScope.launch { startSingbox() }
                return@runCatching
            }
            val config = ConfigManager.load()
            if (config.isBlank() || config == "{}") {
                Log.e(TAG, "serviceReload: empty config")
                return@runCatching
            }
            runCatching { cs.startOrReloadService(config, buildOverrideOptions(config)) }
                .onFailure {
                    Log.e(TAG, "serviceReload failed", it)
                    runCatching { cs.setError("android: reload: ${it.message}") }
                }
        }.onFailure { Log.e(TAG, "serviceReload: unexpected error (swallowed)", it) }
    }

    override fun serviceStop() { doStop() }


















    private fun buildOverrideOptions(config: String): OverrideOptions {
        val options = OverrideOptions()




        options.autoRedirect = BootReceiver.isAutoRedirect(service)

        val isAllowMode = runCatching {
            val inbounds = JSONObject(config).optJSONArray("inbounds") ?: return@runCatching false
            for (i in 0 until inbounds.length()) {
                val inb = inbounds.optJSONObject(i) ?: continue
                if (inb.optString("type") == "tun") {
                    return@runCatching inb.has("include_package")
                }
            }
            false
        }.getOrDefault(false)

        if (isAllowMode) {
            options.includePackage = singleStringIterator(service.packageName)
            Log.d(TAG, "[vpn] override: +self (${service.packageName}) — allow-mode")
        }
        return options
    }



    private fun singleStringIterator(value: String): StringIterator =
        object : StringIterator {
            private var consumed = false
            override fun len(): Int = 1
            override fun hasNext(): Boolean = !consumed



            override fun next(): String {
                if (consumed) return ""
                consumed = true
                return value
            }
        }








    override fun getSystemProxyStatus(): SystemProxyStatus = runCatching {
        SystemProxyStatus().apply {
            if (service is BoxVpnService) {
                available = service.systemProxyAvailable
                enabled = service.systemProxyEnabled
            }
        }
    }.getOrElse {
        Log.e(TAG, "getSystemProxyStatus failed (fail-safe empty)", it)
        SystemProxyStatus()
    }


    override fun setSystemProxyEnabled(isEnabled: Boolean) { serviceReload() }







    override fun connectSSHAgent(): Int =
        throw UnsupportedOperationException("SSH agent not supported on Android")


    override fun triggerNativeCrash() {}


















    override fun writeDebugMessage(message: String) {




        if (BoxVpnService.coreLogSink == null) return
        val plain = ansiEscapeRe.replace(message, "")


        if (!coreLogsVerbose && traceDebugRe.containsMatchIn(plain)) return

        if (coreLogQueue.size >= LOG_QUEUE_MAX) {
            coreLogDrops.incrementAndGet()
            return
        }
        coreLogQueue.offer(plain)
        if (drainerScheduled.compareAndSet(false, true)) {
            coreLogMainHandler.post(coreLogDrainer)
        }
    }









    private val ansiEscapeRe = Regex("\\u001B\\[[0-9;]*[A-Za-z]|\\u001B")
    private val traceDebugRe = Regex("\\b(TRACE|DEBUG)\\b")



    private val LOG_QUEUE_MAX = 4096



    private val DRAIN_BATCH_MAX = 200

    private val coreLogQueue: java.util.concurrent.LinkedBlockingQueue<String> by lazy {
        java.util.concurrent.LinkedBlockingQueue()
    }
    private val drainerScheduled = java.util.concurrent.atomic.AtomicBoolean(false)
    private val coreLogDrops = java.util.concurrent.atomic.AtomicLong(0)







    private val coreLogDrainer: Runnable by lazy {
        Runnable {
            drainerScheduled.set(false)
            val sink = BoxVpnService.coreLogSink ?: run { coreLogQueue.clear(); return@Runnable }
            val batch = ArrayList<String>(DRAIN_BATCH_MAX.coerceAtMost(64))
            var taken = 0
            while (taken < DRAIN_BATCH_MAX) {
                val line = coreLogQueue.poll() ?: break
                batch.add(line)
                taken++
            }
            if (batch.isNotEmpty()) {
                runCatching { sink.success(batch) }
            }

            if (coreLogQueue.isNotEmpty() &&
                drainerScheduled.compareAndSet(false, true)) {
                coreLogMainHandler.post(coreLogDrainer)
            }
        }
    }

    private val coreLogMainHandler by lazy {
        android.os.Handler(android.os.Looper.getMainLooper())
    }




    fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
        val context = service.applicationContext
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channelId = notification.identifier.ifBlank { "lxbox-core" }
        val channelName = notification.typeName.ifBlank {
            L10n.str(context, R.string.core_channel_fallback_name)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH,
            )
            nm.createNotificationChannel(channel)
        }

        val pendingIntent: PendingIntent? = if (notification.openURL.isNotBlank()) {
            runCatching {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(notification.openURL)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                PendingIntent.getActivity(
                    context,
                    notification.typeID,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }.getOrNull()
        } else null

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
        if (notification.subtitle.isNotBlank()) {
            builder.setSubText(notification.subtitle)
        }
        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent)
        }

        runCatching {
            nm.notify(notification.typeID, builder.build())
        }.onFailure {
            Log.e(TAG, "sendNotification.notify failed", it)
        }

        Log.d(TAG, "Notification: ${notification.title} → ${notification.openURL}")
        commandServer.get()?.writeMessage(
            0,
            "platform notification: ${notification.title} (${notification.openURL})",
        )
    }







    fun cancelNotification(identifier: String, typeID: Int) {
        val context = service.applicationContext
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        runCatching {
            nm.cancel(typeID)
        }.onFailure {
            Log.e(TAG, "cancelNotification failed", it)
        }
        Log.d(TAG, "Notification cancelled: $identifier/$typeID")
    }
}
