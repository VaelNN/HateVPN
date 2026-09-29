package com.leadaxe.lxbox.vpn

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val TAG = "VpnPlugin"
        private const val METHOD_CHANNEL = "com.leadaxe.lxbox/methods"
        private const val STATUS_CHANNEL = "com.leadaxe.lxbox/status_events"
        private const val CORE_LOG_CHANNEL = "lxbox/coreLog"

        private const val CC_STATUS_CHANNEL = "lxbox/cc/status"
        private const val CC_OUTBOUNDS_CHANNEL = "lxbox/cc/outbounds"
        private const val CC_GROUPS_CHANNEL = "lxbox/cc/groups"
        private const val CC_CONNECTIONS_CHANNEL = "lxbox/cc/connections"
        private const val CC_DNS_CHANNEL = "lxbox/cc/dns"
        private const val CC_TAILSCALE_CHANNEL = "lxbox/cc/tailscale"
        private const val CC_TAILSCALE_PING_CHANNEL = "lxbox/cc/tailscale_ping"
        private const val VPN_REQUEST_CODE = 24



        private val PPROF_PROFILES = setOf(
            "goroutine", "profile", "heap", "allocs",
            "block", "mutex", "threadcreate",
        )




        @Volatile
        private var bridgeChannel: MethodChannel? = null
        @Volatile
        private var appContext: Context? = null
        private val bridgeHandler =
            android.os.Handler(android.os.Looper.getMainLooper())




        fun handleAutomationAction(name: String, args: Map<String, Any?>) {
            val channel = bridgeChannel
            if (channel == null) {
                Log.w(TAG, "[automation] handleAutomationAction($name) — no Flutter engine, skip")
                return
            }
            bridgeHandler.post {
                runCatching {
                    channel.invokeMethod(
                        "automationAction",
                        mapOf("name" to name, "args" to args),
                    )
                }.onFailure {
                    Log.e(TAG, "[automation] invokeMethod(automationAction) failed", it)
                }
            }
        }





        fun notifyStopRequested() = handleAutomationAction("vpn-stop-requested", emptyMap())






        fun sendAutomationBroadcast(action: String, extras: Map<String, Any?>) {
            val ctx = appContext ?: return
            val intent = Intent("com.leadaxe.lxbox.event.$action")
            for ((k, v) in extras) {
                when (v) {
                    null -> {}
                    is String -> intent.putExtra(k, v)
                    is Boolean -> intent.putExtra(k, v)
                    is Int -> intent.putExtra(k, v)
                    is Long -> intent.putExtra(k, v)
                    is Double -> intent.putExtra(k, v)
                    else -> intent.putExtra(k, v.toString())
                }
            }


            ctx.sendBroadcast(intent)
            Log.d(TAG, "[automation] emit $action (${extras.size} extras)")
        }
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var statusEventChannel: EventChannel
    private lateinit var coreLogEventChannel: EventChannel

    private lateinit var ccStatusEventChannel: EventChannel
    private lateinit var ccOutboundsEventChannel: EventChannel
    private lateinit var ccGroupsEventChannel: EventChannel
    private lateinit var ccConnectionsEventChannel: EventChannel
    private lateinit var ccDnsEventChannel: EventChannel
    private lateinit var ccTailscaleEventChannel: EventChannel
    private lateinit var ccTailscalePingEventChannel: EventChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var statusSink: EventChannel.EventSink? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())




    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action != BoxVpnService.BROADCAST_STATUS) return
            val name = intent.getStringExtra(BoxVpnService.EXTRA_STATUS) ?: return
            val error = intent.getStringExtra("error")

            val revoked = intent.getBooleanExtra(BoxVpnService.EXTRA_REVOKED, false)

            val coreError = intent.getStringExtra(BoxVpnService.EXTRA_CORE_ERROR)
            Log.d(TAG, "[vpn] plugin.statusReceiver.onReceive name=$name${if (error != null) " error=$error" else ""}${if (revoked) " revoked=true" else ""} sink=${statusSink != null}")
            mainHandler.post {
                val event = mutableMapOf<String, Any>("status" to name)
                if (error != null) event["error"] = error
                if (revoked) event[BoxVpnService.EXTRA_REVOKED] = true
                if (!coreError.isNullOrEmpty()) {
                    event[BoxVpnService.EXTRA_CORE_ERROR] = coreError
                }





                runCatching { statusSink?.success(event) }
                    .onFailure { Log.w(TAG, "[vpn] statusSink.success failed: $it") }
            }
        }
    }





    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        context = binding.applicationContext
        BoxApplication.initialize(context)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        bridgeChannel = methodChannel
        appContext = context

        statusEventChannel = EventChannel(binding.binaryMessenger, STATUS_CHANNEL)
        statusEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                Log.d(TAG, "[vpn] statusEventChannel.onListen — sink installed")
                statusSink = sink
            }
            override fun onCancel(args: Any?) {
                Log.d(TAG, "[vpn] statusEventChannel.onCancel — sink cleared")
                statusSink = null
            }
        })




        coreLogEventChannel = EventChannel(binding.binaryMessenger, CORE_LOG_CHANNEL)
        coreLogEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                Log.d(TAG, "[vpn] coreLogEventChannel.onListen — sink installed")
                BoxVpnService.coreLogSink = sink
            }
            override fun onCancel(args: Any?) {
                Log.d(TAG, "[vpn] coreLogEventChannel.onCancel — sink cleared")
                BoxVpnService.coreLogSink = null
            }
        })



        ccStatusEventChannel = EventChannel(binding.binaryMessenger, CC_STATUS_CHANNEL)
        ccStatusEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { BoxVpnService.ccStatusSink = sink }
            override fun onCancel(args: Any?) { BoxVpnService.ccStatusSink = null }
        })
        ccOutboundsEventChannel = EventChannel(binding.binaryMessenger, CC_OUTBOUNDS_CHANNEL)
        ccOutboundsEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { BoxVpnService.ccOutboundsSink = sink }
            override fun onCancel(args: Any?) { BoxVpnService.ccOutboundsSink = null }
        })
        ccGroupsEventChannel = EventChannel(binding.binaryMessenger, CC_GROUPS_CHANNEL)
        ccGroupsEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { BoxVpnService.ccGroupsSink = sink }
            override fun onCancel(args: Any?) { BoxVpnService.ccGroupsSink = null }
        })
        ccConnectionsEventChannel = EventChannel(binding.binaryMessenger, CC_CONNECTIONS_CHANNEL)
        ccConnectionsEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                BoxVpnService.ccConnectionsSink = sink





                BoxService.commandClient?.reEmitScreenConnections()
            }
            override fun onCancel(args: Any?) { BoxVpnService.ccConnectionsSink = null }
        })

        ccDnsEventChannel = EventChannel(binding.binaryMessenger, CC_DNS_CHANNEL)
        ccDnsEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { BoxVpnService.ccDnsQueriesSink = sink }
            override fun onCancel(args: Any?) { BoxVpnService.ccDnsQueriesSink = null }
        })

        ccTailscaleEventChannel = EventChannel(binding.binaryMessenger, CC_TAILSCALE_CHANNEL)
        ccTailscaleEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { BoxVpnService.ccTailscaleSink = sink }
            override fun onCancel(args: Any?) { BoxVpnService.ccTailscaleSink = null }
        })

        ccTailscalePingEventChannel = EventChannel(binding.binaryMessenger, CC_TAILSCALE_PING_CHANNEL)
        ccTailscalePingEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { BoxVpnService.ccTailscalePingSink = sink }
            override fun onCancel(args: Any?) { BoxVpnService.ccTailscalePingSink = null }
        })

        Log.d(TAG, "[vpn] onAttachedToEngine: registerReceiver(statusReceiver)")




        runCatching {
            context.registerReceiver(
                statusReceiver,
                IntentFilter(BoxVpnService.BROADCAST_STATUS),
                Context.RECEIVER_NOT_EXPORTED
            )
        }.onFailure { Log.e(TAG, "[vpn] registerReceiver(statusReceiver) failed: $it") }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "[vpn] onDetachedFromEngine: unregisterReceiver(statusReceiver)")
        methodChannel.setMethodCallHandler(null)
        statusEventChannel.setStreamHandler(null)
        coreLogEventChannel.setStreamHandler(null)
        ccStatusEventChannel.setStreamHandler(null)
        ccOutboundsEventChannel.setStreamHandler(null)
        ccGroupsEventChannel.setStreamHandler(null)
        ccConnectionsEventChannel.setStreamHandler(null)
        ccDnsEventChannel.setStreamHandler(null)
        ccTailscaleEventChannel.setStreamHandler(null)
        ccTailscalePingEventChannel.setStreamHandler(null)
        statusSink = null
        BoxVpnService.coreLogSink = null
        BoxVpnService.ccStatusSink = null
        BoxVpnService.ccOutboundsSink = null
        BoxVpnService.ccGroupsSink = null
        BoxVpnService.ccConnectionsSink = null
        BoxVpnService.ccDnsQueriesSink = null
        BoxVpnService.ccTailscaleSink = null

        bridgeChannel = null
        appContext = null
        runCatching { context.unregisterReceiver(statusReceiver) }
        pluginScope.cancel()
    }





    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "saveConfig" -> {
                val config = call.argument<String>("config") ?: ""
                result.success(ConfigManager.save(config))
            }
            "getConfig" -> result.success(ConfigManager.load())




            "getFilesDir" -> result.success(context.filesDir.path)
            "startVPN" -> startVpn(result)




            "startVpnHeadless" -> {


                val needConsent = BootReceiver.hasTun(context) &&
                    VpnService.prepare(context.applicationContext) != null
                if (needConsent) {
                    result.success(mapOf("started" to false, "needs_consent" to true))
                } else {
                    BoxVpnService.start(context)
                    result.success(mapOf("started" to true, "needs_consent" to false))
                }
            }
            "stopVPN" -> stopVpn(result)
            "forceStopVPN" -> {



                BoxVpnService.forceStop(context)
                result.success(true)
            }
            "getVpnStatus" -> {






                result.success(
                    mapOf(
                        "status" to BoxVpnService.currentStatus.name,
                        BoxVpnService.EXTRA_REVOKED to BoxVpnService.currentRevoked,
                    )
                )
            }




            "isForeignVpnActive" -> result.success(isForeignVpnActive())
            "getTunnelUptimeMs" -> {




                val started = BoxVpnService.tunnelStartedElapsedMs
                val uptime = if (started > 0L) SystemClock.elapsedRealtime() - started else 0L
                result.success(uptime)
            }
            "getCoreVersion" -> {



                try {
                    result.success(io.nekohasekai.libbox.Libbox.version())
                } catch (t: Throwable) {
                    Log.e(TAG, "getCoreVersion failed", t)
                    result.success("")
                }
            }
            "reloadVPN" -> {


                BoxVpnService.reload(context)
                result.success(true)
            }
            "resetNetwork" -> {


                BoxVpnService.resetNetwork(context)
                result.success(true)
            }
            "setQuicKnob" -> {



                val knob = call.argument<String>("knob")
                val disabled = call.argument<Boolean>("disabled") ?: false
                val ok = try {
                    when (knob) {
                        "gso" -> {
                            io.nekohasekai.libbox.Libbox.setQuicGSODisabled(disabled)
                            true
                        }
                        "ecn" -> {
                            io.nekohasekai.libbox.Libbox.setQuicECNDisabled(disabled)
                            true
                        }
                        else -> false
                    }
                } catch (t: Throwable) {

                    Log.e(TAG, "setQuicKnob($knob) failed", t)
                    false
                }
                result.success(ok)
            }
            "clearDnsCache" -> {


                BoxVpnService.clearDnsCache(context)
                result.success(true)
            }
            "setNotificationTitle" -> {
                val title = call.argument<String>("title")
                    ?: context.getString(com.leadaxe.lxbox.R.string.app_name)


                val changed = title != ConfigManager.notificationTitle
                ConfigManager.setNotificationTitle(title)
                if (changed) BoxVpnService.updateNotification(context)
                result.success(true)
            }
            "setNotificationText" -> {

                val text = call.argument<String>("text") ?: ""
                val changed = text != ConfigManager.notificationText
                ConfigManager.setNotificationText(text)
                if (changed) BoxVpnService.updateNotification(context)
                result.success(true)
            }
            "setAutoStart" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BootReceiver.setEnabled(context, enabled)
                result.success(true)
            }
            "getAutoStart" -> {
                result.success(BootReceiver.isEnabled(context))
            }
            "setKeepOnExit" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BootReceiver.setKeepOnExit(context, enabled)
                result.success(true)
            }
            "getKeepOnExit" -> {
                result.success(BootReceiver.isKeepOnExit(context))
            }
            "setCoreLogsEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BootReceiver.setCoreLogsEnabled(context, enabled)
                result.success(true)
            }
            "getCoreLogsEnabled" -> {
                result.success(BootReceiver.isCoreLogsEnabled(context))
            }



            "setCoreLogsVerbose" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BootReceiver.setCoreLogsVerbose(context, enabled)
                BoxService.coreLogsVerbose = enabled
                result.success(true)
            }
            "getCoreLogsVerbose" -> {
                result.success(BootReceiver.isCoreLogsVerbose(context))
            }


            "setAllowBypass" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BootReceiver.setAllowBypass(context, enabled)
                result.success(true)
            }
            "getAllowBypass" -> {
                result.success(BootReceiver.isAllowBypass(context))
            }



            "setAutoRedirect" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BootReceiver.setAutoRedirect(context, enabled)
                result.success(true)
            }
            "getAutoRedirect" -> {
                result.success(BootReceiver.isAutoRedirect(context))
            }



            "setHasTun" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                BootReceiver.setHasTun(context, enabled)
                result.success(true)
            }


            "getCurrentSessionAllowBypass" -> {
                result.success(BoxVpnService.currentSessionAllowBypass)
            }
            "quitApp" -> {














                result.success(true)
                mainHandler.postDelayed({
                    activity?.finishAffinity()
                }, 50)
                mainHandler.postDelayed({
                    android.os.Process.killProcess(android.os.Process.myPid())
                    kotlin.system.exitProcess(0)
                }, 250)
            }
            "getInstalledApps" -> {



                val pm = context.packageManager
                val apps = pm.getInstalledApplications(0).map { info ->
                    val isSystem = (info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    mapOf(
                        "packageName" to info.packageName,
                        "appName" to (pm.getApplicationLabel(info)?.toString() ?: info.packageName),
                        "isSystemApp" to isSystem,
                    )
                }
                result.success(apps)
            }
            "getAppIcon" -> {
                val pkg = call.argument<String>("packageName") ?: ""
                result.success(encodeAppIcon(pkg))
            }
            "getAppInfo" -> {








                val pkg = call.argument<String>("packageName") ?: ""
                val pm = context.packageManager
                try {
                    val info = pm.getApplicationInfo(pkg, 0)
                    val isSystem = (info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    result.success(mapOf(
                        "packageName" to pkg,
                        "appName" to (pm.getApplicationLabel(info)?.toString() ?: pkg),
                        "isSystemApp" to isSystem,
                    ))
                } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                    result.success(mapOf("notFound" to true))
                } catch (e: Exception) {
                    result.error("APP_INFO_ERROR", e.message, null)
                }
            }
            "isIgnoringBatteryOptimizations" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
            }
            "openBatteryOptimizationSettings" -> {








                result.success(openSystemSettings(
                    primaryAction = android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    primaryWithPackage = true,
                    fallbackAction = android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS,
                ))
            }
            "openAppDetailsSettings" -> {
                result.success(openSystemSettings(
                    primaryAction = android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    primaryWithPackage = true,
                ))
            }
            "areNotificationsEnabled" -> {
                result.success(androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled())
            }
            "getBackgroundMode" -> {
                result.success(BootReceiver.getBackgroundMode(context))
            }
            "setBackgroundMode" -> {
                val mode = call.argument<String>("mode") ?: BootReceiver.BG_MODE_NEVER
                BootReceiver.setBackgroundMode(context, mode)
                result.success(null)
            }
            "getMemoryLimit" -> {
                result.success(BootReceiver.getMemoryLimit(context))
            }




            "setAppLanguage" -> {
                val tag = call.argument<String>("tag") ?: "system"
                L10n.applySetting(context, tag)
                result.success(true)
            }



            "getAppLanguageState" -> {
                result.success(L10n.appLanguageState(context))
            }
            "setMemoryLimit" -> {







                val value = call.argument<String>("value") ?: BootReceiver.MEMORY_LIMIT_AUTO
                BootReceiver.setMemoryLimit(context, value)
                val appContext = context
                pluginScope.launch(Dispatchers.IO) {
                    runCatching {
                        BoxApplication.libboxReady.await()
                        val opts = io.nekohasekai.libbox.SetupOptions().apply {
                            oomKillerEnabled = true
                            oomMemoryLimit = BoxApplication.resolveMemoryLimitBytes(appContext)
                        }
                        io.nekohasekai.libbox.Libbox.reloadSetupOptions(opts)
                    }.onFailure { Log.w(TAG, "reloadSetupOptions failed: ${it.message}") }
                }
                result.success(null)
            }
            "openNotificationSettings" -> {




                result.success(openNotificationSettings())
            }
            "openVpnSettings" -> {



                result.success(openSystemSettings(
                    primaryAction = android.provider.Settings.ACTION_VPN_SETTINGS,
                    primaryWithPackage = false,
                ))
            }
            "requestAddTile" -> {




                requestAddQuickSettingsTile(result)
            }

            "setAutomationEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                LxBoxIntentReceiver.setEnabled(context, enabled)
                result.success(true)
            }
            "sendAutomationBroadcast" -> {
                val action = call.argument<String>("action") ?: ""
                @Suppress("UNCHECKED_CAST")
                val extras = (call.argument<Map<String, Any?>>("extras")
                    ?: emptyMap())
                if (action.isNotEmpty()) {
                    sendAutomationBroadcast(action, extras)
                }
                result.success(true)
            }





            "setAutomationActiveState" -> {
                val node = call.argument<String>("node")
                val group = call.argument<String>("group")
                val nodes = call.argument<List<String>>("nodes")
                val groups = call.argument<List<String>>("groups")
                val edit = context
                    .getSharedPreferences("lxbox_automation", Context.MODE_PRIVATE)
                    .edit()
                    .putString("active_node", node)
                    .putString("active_group", group)


                if (nodes != null) {
                    edit.putString("all_nodes", org.json.JSONArray(nodes).toString())
                }
                if (groups != null) {
                    edit.putString("all_groups", org.json.JSONArray(groups).toString())
                }
                edit.apply()
                result.success(true)
            }
            "getApplicationExitInfo" -> result.success(readApplicationExitInfo())
            "getLogcatTail" -> {
                val count = (call.argument<Int>("count") ?: 1000).coerceIn(50, 5000)
                val level = (call.argument<String>("level") ?: "E")
                    .filter { it.isLetter() }
                    .ifEmpty { "E" }
                result.success(readLogcatTail(count, level))
            }
            "showToast" -> {




                val msg = call.argument<String>("msg") ?: ""
                val duration = when (call.argument<String>("duration")) {
                    "long" -> android.widget.Toast.LENGTH_LONG
                    else -> android.widget.Toast.LENGTH_SHORT
                }
                mainHandler.post {
                    android.widget.Toast.makeText(context, msg, duration).show()
                }
                result.success(true)
            }










            "ccResyncForReopen" -> {
                BoxService.commandClient?.apply {
                    resyncForReopen()
                    disconnectProfiler()
                }
                result.success(true)
            }
            "ccConnectScreen" -> {
                BoxService.commandClient?.connectScreen(); result.success(true)
            }
            "ccDisconnectScreen" -> {
                BoxService.commandClient?.disconnectScreen(); result.success(true)
            }
            "ccConnectProfiler" -> {
                BoxService.commandClient?.connectProfiler(); result.success(true)
            }
            "ccDisconnectProfiler" -> {
                BoxService.commandClient?.disconnectProfiler(); result.success(true)
            }




            "ccStartTailscaleStatus" -> {
                val cc = BoxService.commandClient
                if (cc != null) pluginScope.launch(Dispatchers.IO) { cc.startTailscaleStatus() }
                result.success(cc != null)
            }
            "ccStopTailscaleStatus" -> {
                val cc = BoxService.commandClient
                if (cc != null) pluginScope.launch(Dispatchers.IO) { cc.stopTailscaleStatus() }
                result.success(true)
            }


            "ccSetTailscaleExitNode" -> {
                val cc = BoxService.commandClient
                val tag = call.argument<String>("tag") ?: ""
                val id = call.argument<String>("stable_id") ?: ""
                pluginScope.launch {
                    val err = withContext(Dispatchers.IO) {
                        cc?.setTailscaleExitNode(tag, id) ?: "no command client"
                    }
                    result.success(err)
                }
            }
            "ccTailscaleLogout" -> {
                val cc = BoxService.commandClient
                val tag = call.argument<String>("tag") ?: ""
                pluginScope.launch {
                    val err = withContext(Dispatchers.IO) {
                        cc?.tailscaleLogout(tag) ?: "no command client"
                    }
                    result.success(err)
                }
            }
            "ccStartTailscalePing" -> {
                val cc = BoxService.commandClient
                val tag = call.argument<String>("tag") ?: ""
                val ip = call.argument<String>("peer_ip") ?: ""
                if (cc != null) pluginScope.launch(Dispatchers.IO) { cc.startTailscalePing(tag, ip) }
                result.success(cc != null)
            }
            "ccStopTailscalePing" -> {
                val cc = BoxService.commandClient
                if (cc != null) pluginScope.launch(Dispatchers.IO) { cc.stopTailscalePing() }
                result.success(true)
            }
            "ccCancelPing" -> {
                BoxService.commandClient?.cancelPing(); result.success(true)
            }




            "ccSetStatusFast" -> {
                val fast = call.argument<Boolean>("fast") ?: false
                BoxService.commandClient?.setStatusFast(fast); result.success(true)
            }
            "ccPauseClients" -> {
                BoxService.commandClient?.apply { pauseStatus(); pauseScreen() }
                result.success(true)
            }
            "ccResumeClients" -> {
                BoxService.commandClient?.apply { resumeStatus(); resumeScreen() }
                result.success(true)
            }





            "ccUrlTestOutbound" -> {
                val cc = BoxService.commandClient
                if (cc == null) { result.success(mapOf("delay" to 0, "error" to "not connected")); return }
                val tag = call.argument<String>("tag") ?: ""
                val link = call.argument<String>("link") ?: ""
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 0
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc.urlTestOutbound(tag, link, timeoutMs) }
                    result.success(r)
                }
            }



            "ccGetUrlViaOutbound" -> {
                val cc = BoxService.commandClient
                if (cc == null) { result.success(mapOf("error" to "not connected")); return }
                val tag = call.argument<String>("tag") ?: ""
                val link = call.argument<String>("link") ?: ""
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 0
                val maxBytes = call.argument<Int>("maxBytes") ?: 0
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) {
                        cc.getUrlViaOutbound(tag, link, timeoutMs, maxBytes)
                    }
                    result.success(r)
                }
            }


            "ccUrlTestGroup" -> {
                val cc = BoxService.commandClient
                if (cc == null) { result.success(false); return }
                val tag = call.argument<String>("tag") ?: ""
                pluginScope.launch {
                    val ok = withContext(Dispatchers.IO) { cc.urlTestGroup(tag) }
                    result.success(ok)
                }
            }



            "probeStart" -> {
                val config = call.argument<String>("config") ?: ""
                pluginScope.launch {
                    val err = withContext(Dispatchers.IO) { ProbeSession.start(config) }
                    result.success(err)
                }
            }
            "probeUrlTest" -> {
                val tag = call.argument<String>("tag") ?: ""
                val link = call.argument<String>("link") ?: ""
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 0
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { ProbeSession.urlTest(tag, link, timeoutMs) }
                    result.success(r)
                }
            }


            "probeGetUrl" -> {
                val tag = call.argument<String>("tag") ?: ""
                val link = call.argument<String>("link") ?: ""
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 0
                val maxBytes = call.argument<Int>("maxBytes") ?: 0
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) {
                        ProbeSession.getUrl(tag, link, timeoutMs, maxBytes)
                    }
                    result.success(r)
                }
            }
            "probeStop" -> {
                pluginScope.launch {
                    withContext(Dispatchers.IO) { runCatching { ProbeSession.stop() } }
                    result.success(null)
                }
            }



            "ccGetRules" -> {
                val cc = BoxService.commandClient
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.getRules() }
                    result.success(r)
                }
            }



            "ccGetGroups" -> {
                val cc = BoxService.commandClient
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.getGroups() }
                    result.success(r)
                }
            }




            "ccGetOutbounds" -> {
                val cc = BoxService.commandClient
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.getOutbounds() }
                    result.success(r)
                }
            }








            "ccGetDnsGroups" -> {
                val cc = BoxService.commandClient
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.getDnsGroups() }
                    result.success(r)
                }
            }
            "ccGetRunningConfig" -> {
                val cc = BoxService.commandClient
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.getRunningConfig() }
                    result.success(r)
                }
            }












            "formatConfig" -> {
                val text = call.argument<String>("config") ?: ""
                if (text.isBlank()) {
                    result.success(null)
                } else {
                    pluginScope.launch {
                        val r = withContext(Dispatchers.IO) {
                            try {
                                io.nekohasekai.libbox.Libbox.formatConfig(text)?.value
                            } catch (t: Throwable) {

                                Log.d(TAG, "formatConfig failed: ${t.message}")
                                null
                            }
                        }
                        result.success(r)
                    }
                }
            }








            "checkConfig" -> {
                val text = call.argument<String>("config") ?: ""
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) {
                        try {
                            io.nekohasekai.libbox.Libbox.checkConfig(text)
                            mapOf("ok" to true)
                        } catch (t: Throwable) {
                            Log.d(TAG, "checkConfig rejected: ${t.message}")
                            mapOf("ok" to false, "error" to (t.message ?: t.toString()))
                        }
                    }
                    result.success(r)
                }
            }





            "ccGetPool" -> {
                val cc = BoxService.commandClient
                val tag = call.argument<String>("tag") ?: ""
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.getPool(tag) }
                    result.success(r)
                }
            }
            "ccSelectOutbound" -> {
                val cc = BoxService.commandClient
                val group = call.argument<String>("group") ?: ""
                val tag = call.argument<String>("tag") ?: ""
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.selectOutbound(group, tag) ?: false }
                    result.success(r)
                }
            }




            "ccSetEndpointEnabled" -> {
                val cc = BoxService.commandClient
                val tag = call.argument<String>("tag") ?: ""
                val enabled = call.argument<Boolean>("enabled") ?: true
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) {
                        cc?.setEndpointEnabled(tag, enabled)
                            ?: mapOf("error" to "error", "message" to "no command client")
                    }
                    val err = r["error"]
                    if (err != null) {
                        result.error(err, r["message"], null)
                    } else {
                        result.success(r["state"] ?: "")
                    }
                }
            }
            "ccCloseConnection" -> {
                val cc = BoxService.commandClient
                val id = call.argument<String>("id") ?: ""
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.closeConnection(id) ?: false }
                    result.success(r)
                }
            }
            "ccCloseConnections" -> {
                val cc = BoxService.commandClient
                pluginScope.launch {
                    val r = withContext(Dispatchers.IO) { cc?.closeConnections() ?: false }
                    result.success(r)
                }
            }

















            "pprofProfile" -> {
                val pathAndQuery = call.argument<String>("pathAndQuery")
                    ?: "goroutine?debug=2"
                val name = pathAndQuery.substringBefore('?')
                pluginScope.launch {
                    try {
                        if (name !in PPROF_PROFILES) {
                            throw IllegalArgumentException("unknown pprof profile: $name")
                        }
                        val bytes = withContext(Dispatchers.IO) {


                            val secs = if (name == "profile") {
                                Regex("seconds=(\\d+)").find(pathAndQuery)
                                    ?.groupValues?.get(1)?.toIntOrNull()
                                    ?.coerceIn(1, 60) ?: 10
                            } else 0
                            val readTimeout =
                                if (name == "profile") secs * 1000 + 5000 else 5000
                            PProfClient.fetch(pathAndQuery, readTimeoutMs = readTimeout)
                        }
                        result.success(bytes)
                    } catch (t: Throwable) {
                        Log.e(TAG, "pprofProfile($pathAndQuery) failed", t)
                        result.error("PPROF_FAILED",
                            t.message ?: t.javaClass.simpleName, null)
                    }
                }
            }




            "getMemoryInfo" -> {
                val appContext = context
                pluginScope.launch {
                    try {
                        val out = withContext(Dispatchers.IO) {
                            collectProcessMemoryInfo(appContext)
                        }
                        result.success(out)
                    } catch (t: Throwable) {
                        Log.e(TAG, "getMemoryInfo failed", t)
                        result.error("MEMINFO_FAILED",
                            t.message ?: t.javaClass.simpleName, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }















    private fun collectProcessMemoryInfo(context: Context): Map<String, Any> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE)
            as? android.app.ActivityManager
        val fromAm = runCatching {
            am?.getProcessMemoryInfo(intArrayOf(android.os.Process.myPid()))
                ?.firstOrNull()
        }.getOrNull()
        val mi = if (fromAm != null && fromAm.totalPss > 0) {
            fromAm
        } else {
            android.os.Debug.MemoryInfo().also { android.os.Debug.getMemoryInfo(it) }
        }

        fun kb(statName: String, fallbackKb: Int = 0): Long {
            val parsed = mi.getMemoryStat(statName)?.toLongOrNull() ?: 0L
            val value = if (parsed > 0L) parsed else fallbackKb.toLong()
            return value * 1024L
        }

        return hashMapOf(
            "totalPss" to kb("summary.total-pss", mi.totalPss),


            "totalSwap" to kb("summary.total-swap"),
            "javaHeap" to kb("summary.java-heap", mi.dalvikPss),
            "nativeHeap" to kb("summary.native-heap", mi.nativePss),
            "code" to kb("summary.code"),
            "stack" to kb("summary.stack"),
            "graphics" to kb("summary.graphics"),
            "privateOther" to kb("summary.private-other", mi.otherPss),
            "system" to kb("summary.system"),



            "nativeHeapAllocated" to android.os.Debug.getNativeHeapAllocatedSize(),
            "nativeHeapSize" to android.os.Debug.getNativeHeapSize(),
        )
    }




    private fun readApplicationExitInfo(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            ?: return emptyList()
        val infos = runCatching {
            am.getHistoricalProcessExitReasons(context.packageName, 0, 5)
        }.getOrElse {
            Log.w(TAG, "getHistoricalProcessExitReasons failed: ${it.message}")
            return emptyList()
        }
        return infos.map { info ->
            mapOf(
                "timestamp" to info.timestamp,
                "reason" to exitReasonName(info.reason),
                "description" to info.description,
                "importance" to info.importance,
                "pss" to info.pss,
                "rss" to info.rss,
                "status" to info.status,
                "trace" to runCatching {
                    info.traceInputStream?.use { it.bufferedReader().readText() }
                }.getOrNull(),
            )
        }
    }




    private fun readLogcatTail(count: Int, level: String): String {
        return runCatching {
            val proc = ProcessBuilder("logcat", "-d", "-t", count.toString(), "*:$level")
                .redirectErrorStream(true)
                .start()
            val out = proc.inputStream.bufferedReader().readText()
            proc.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)
            out
        }.getOrElse {
            Log.w(TAG, "logcat tail failed: ${it.message}")
            ""
        }
    }


    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    private fun exitReasonName(code: Int): String = when (code) {
        android.app.ApplicationExitInfo.REASON_UNKNOWN -> "UNKNOWN"
        android.app.ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        android.app.ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        android.app.ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        android.app.ApplicationExitInfo.REASON_CRASH -> "CRASH"
        android.app.ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        android.app.ApplicationExitInfo.REASON_ANR -> "ANR"
        android.app.ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        android.app.ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        android.app.ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        android.app.ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        android.app.ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        android.app.ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        android.app.ApplicationExitInfo.REASON_OTHER -> "OTHER"
        android.app.ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "PACKAGE_UPDATED"
        else -> "REASON_$code"
    }





    private fun openSystemSettings(
        primaryAction: String,
        primaryWithPackage: Boolean,
        fallbackAction: String? = null,
    ): Boolean {
        val act = activity
        val launchCtx: Context = act ?: context
        val useNewTask = act == null

        fun needsPackage(action: String) = action in setOf(
            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        )

        fun tryLaunch(action: String, withPackage: Boolean): Boolean {
            val intent = android.content.Intent(action).apply {
                if (withPackage) {
                    data = android.net.Uri.parse("package:${context.packageName}")
                }
                if (useNewTask) addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            return try {
                launchCtx.startActivity(intent)
                Log.d(TAG, "openSystemSettings launched: $action")
                true
            } catch (e: Exception) {
                Log.e(TAG, "openSystemSettings failed for $action: ${e.message}", e)
                false
            }
        }

        if (tryLaunch(primaryAction, primaryWithPackage)) return true
        if (fallbackAction != null &&
            tryLaunch(fallbackAction, needsPackage(fallbackAction))) return true
        return false
    }





    private fun openNotificationSettings(): Boolean {
        val act = activity
        val launchCtx: Context = act ?: context
        val useNewTask = act == null
        val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
            if (useNewTask) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            launchCtx.startActivity(intent)
            true
        } catch (_: Exception) {
            openSystemSettings(
                primaryAction = android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                primaryWithPackage = true,
            )
        }
    }










    private fun requestAddQuickSettingsTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("unsupported")
            return
        }
        val act = activity
        if (act == null) {
            result.success("no_activity")
            return
        }
        try {
            val sbm = act.getSystemService(android.app.StatusBarManager::class.java)
            if (sbm == null) {
                result.success("error: status_bar_unavailable")
                return
            }
            val component = android.content.ComponentName(
                context, com.leadaxe.lxbox.vpn.LxBoxTileService::class.java
            )
            val icon = android.graphics.drawable.Icon.createWithResource(
                context, android.R.drawable.ic_lock_lock
            )


            val replied = java.util.concurrent.atomic.AtomicBoolean(false)
            sbm.requestAddTileService(
                component,
                context.getString(com.leadaxe.lxbox.R.string.app_name),
                icon,
                { runnable -> mainHandler.post(runnable) },
                { code ->
                    if (!replied.compareAndSet(false, true)) return@requestAddTileService
                    val mapped = when (code) {
                        android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                        android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> "already"
                        android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> "dismissed"
                        else -> "error: result=$code"
                    }
                    mainHandler.post { result.success(mapped) }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "requestAddTile failed", e)
            result.success("error: ${e.message}")
        }
    }



    private fun encodeAppIcon(pkg: String): String {
        return try {
            val pm = context.packageManager
            val drawable = pm.getApplicationIcon(pkg)
            val bitmap = if (drawable is android.graphics.drawable.BitmapDrawable) {
                drawable.bitmap
            } else {
                val bmp = android.graphics.Bitmap.createBitmap(
                    48, 48, android.graphics.Bitmap.Config.ARGB_8888
                )
                val canvas = android.graphics.Canvas(bmp)
                drawable.setBounds(0, 0, 48, 48)
                drawable.draw(canvas)
                bmp
            }
            val stream = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 80, stream)
            android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
        } catch (_: Exception) {
            ""
        }
    }



































    private fun isForeignVpnActive(): Boolean {
        if (BoxVpnService.currentStatus != VpnStatus.Stopped) return false
        val cm = BoxApplication.connectivity
        return try {
            val n = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(n) ?: return false
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                caps.ownerUid == android.os.Process.myUid()
            ) {
                Log.d(TAG, "[vpn §361] skipping our own orphaned VPN network (uid=${caps.ownerUid})")
                return false
            }
            true
        } catch (t: Throwable) {
            Log.w(TAG, "isForeignVpnActive: $t")
            false
        }
    }

    private fun startVpn(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "No activity", null)
            return
        }



        if (!BootReceiver.hasTun(context)) {
            BoxVpnService.start(context)
            result.success(true)
            return
        }
        val intent = VpnService.prepare(act)
        if (intent != null) {
            pendingVpnResult = result
            act.startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            BoxVpnService.start(context)
            result.success(true)
        }
    }










    private fun stopVpn(result: MethodChannel.Result) {
        pluginScope.launch {
            val ok = try {
                withTimeout(BoxVpnService.STOP_AWAIT_TIMEOUT_MS) {
                    BoxVpnService.stopAwait(context).await()
                }
                true
            } catch (e: TimeoutCancellationException) {
                Log.w(TAG, "[vpn] stopVPN: ${BoxVpnService.STOP_AWAIT_TIMEOUT_MS}ms timeout — native did not report Stopped")
                false
            } catch (e: Exception) {
                Log.e(TAG, "[vpn] stopVPN: exception $e")
                false
            }
            result.success(ok)
        }
    }





    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }





    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_REQUEST_CODE) return false
        val r = pendingVpnResult
        pendingVpnResult = null
        if (resultCode == Activity.RESULT_OK) {
            BoxVpnService.start(context)
            r?.success(true)
        } else {
            r?.success(false)
        }
        return true
    }
}
