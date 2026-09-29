package com.leadaxe.lxbox.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
















class WifiNetworkObserver(private val ctx: Context) {

    private val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE)
            as ConnectivityManager
    private val handler = Handler(Looper.getMainLooper())




    private var pendingSsid: String? = null
    private var pendingBssid: String = ""
    private var pendingTimer: Runnable? = null
    private var registered = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(
            net: Network,
            caps: NetworkCapabilities,
        ) {
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return



            val state = readWifi() ?: return
            if (state.first.isEmpty()) return
            handlePending(state.first, state.second)
        }

        override fun onLost(net: Network) {


            cancelPending()
        }
    }

    @Synchronized
    fun start() {
        if (registered) return




        try {
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            cm.registerNetworkCallback(req, callback)
            registered = true
            Log.d(TAG, "started")
        } catch (e: SecurityException) {
            Log.w(TAG, "registerNetworkCallback denied: ${e.message}")
        } catch (e: RuntimeException) {
            Log.w(TAG, "registerNetworkCallback failed: ${e.message}")
        }
    }

    @Synchronized
    fun stop() {
        cancelPending()
        if (!registered) return
        runCatching { cm.unregisterNetworkCallback(callback) }
            .onFailure { Log.w(TAG, "unregister failed: ${it.message}") }
        registered = false
        Log.d(TAG, "stopped")
    }





    private fun readWifi(): Pair<String, String>? {
        return when (val r = WifiInfoReader.read(ctx)) {
            is WifiInfoReader.Result.Success -> r.ssid to r.bssid
            is WifiInfoReader.Result.UnknownSsid -> "" to ""
            else -> null
        }
    }


    private fun handlePending(ssid: String, bssid: String) {
        if (pendingSsid == ssid && pendingBssid == bssid) return
        cancelPending()
        pendingSsid = ssid
        pendingBssid = bssid
        val task = Runnable {


            val s = pendingSsid
            val b = pendingBssid
            pendingSsid = null
            pendingTimer = null
            if (s != null && s.isNotEmpty()) {
                WifiHistoryBridge.notifySeen(s, b)
            }
        }
        pendingTimer = task
        handler.postDelayed(task, STICKINESS_THRESHOLD_MS)
    }

    private fun cancelPending() {
        pendingTimer?.let(handler::removeCallbacks)
        pendingTimer = null
        pendingSsid = null
        pendingBssid = ""
    }

    companion object {
        private const val TAG = "WifiNetObserver"





        const val STICKINESS_THRESHOLD_MS = 300_000L
    }
}







object WifiHistoryBridge {
    private const val TAG = "WifiHistoryBridge"
    private const val METHOD_ON_WIFI_SEEN = "onWifiSeen"

    @Volatile
    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())

    fun attach(ch: MethodChannel) {
        channel = ch
    }

    fun detach() {
        channel = null
    }

    fun notifySeen(ssid: String, bssid: String) {
        val ch = channel ?: run {
            Log.w(TAG, "notifySeen but channel not attached, dropped")
            return
        }
        handler.post {
            ch.invokeMethod(
                METHOD_ON_WIFI_SEEN,
                mapOf("ssid" to ssid, "bssid" to bssid),
            )
        }
    }
}
