package com.leadaxe.lxbox.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.os.Build
import android.os.SystemClock
import android.util.Log






















class WifiStateCache(private val ctx: Context) {

    data class WifiSnapshot(

        val ssid: String,

        val bssid: String,
        val network: Network,
        val atMillis: Long,
    )

    @Volatile
    var latest: WifiSnapshot? = null
        private set

    private var callback: ConnectivityManager.NetworkCallback? = null


    private var registeredWith: String? = null

    private val cm: ConnectivityManager
        get() = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    val isRegistered: Boolean
        @Synchronized get() = callback != null




    @Synchronized
    fun ensureCurrent() {
        if (Build.VERSION.SDK_INT < 31) return
        val snap = WifiInfoReader.permissionSnapshot(ctx)
        if (callback != null) {
            if (registeredWith == snap) return
            Log.d(TAG, "permissions changed ($registeredWith -> $snap), re-registering")
            stop()
        }
        start()
    }




    @Synchronized
    fun start() {
        if (Build.VERSION.SDK_INT < 31) return
        if (callback != null) return
        val reason = WifiInfoReader.preflight(ctx)
        if (reason != null) {
            Log.d(TAG, "not started: preflight failed ($reason)")
            return
        }
        val cb = newCallback()
        try {
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            cm.registerNetworkCallback(req, cb)
        } catch (e: SecurityException) {
            Log.w(TAG, "registerNetworkCallback denied: ${e.message}")
            return
        } catch (e: RuntimeException) {
            Log.w(TAG, "registerNetworkCallback failed: ${e.javaClass.simpleName}: ${e.message}")
            return
        }
        callback = cb
        registeredWith = WifiInfoReader.permissionSnapshot(ctx)
        Log.d(TAG, "started (perms=$registeredWith)")
    }



    @Synchronized
    fun stop() {
        latest = null
        val cb = callback ?: return
        callback = null
        registeredWith = null
        runCatching { cm.unregisterNetworkCallback(cb) }
            .onFailure { Log.w(TAG, "unregister failed: ${it.message}") }
        Log.d(TAG, "stopped")
    }

    private fun newCallback(): ConnectivityManager.NetworkCallback =
        object : ConnectivityManager.NetworkCallback(
            ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO,
        ) {
            override fun onCapabilitiesChanged(net: Network, caps: NetworkCapabilities) {


                val info = caps.transportInfo as? WifiInfo ?: return
                val snap = WifiSnapshot(
                    ssid = WifiInfoReader.normalizeSsid(info.ssid),
                    bssid = WifiInfoReader.normalizeBssid(info.bssid),
                    network = net,
                    atMillis = SystemClock.elapsedRealtime(),
                )
                val prev = latest
                latest = snap
                if (prev == null || prev.ssid != snap.ssid || prev.bssid != snap.bssid ||
                    prev.network != snap.network) {
                    Log.d(TAG, "update: ssid='${snap.ssid}' bssid='${snap.bssid}' net=$net")
                }
            }

            override fun onLost(net: Network) {
                if (latest?.network == net) {
                    latest = null
                    Log.d(TAG, "lost: net=$net")
                }
            }
        }

    private companion object {
        const val TAG = "WifiStateCache"
    }
}
