package com.leadaxe.lxbox.vpn

import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import io.nekohasekai.libbox.InterfaceUpdateListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.net.NetworkInterface

object DefaultNetworkMonitor {


    private const val RESET_DEBOUNCE_MS = 1500L

    var defaultNetwork: Network? = null
    private var listener: InterfaceUpdateListener? = null
    private var scope: CoroutineScope? = null


    private var onNetworkSwitch: (() -> Unit)? = null



    @Volatile
    private var lastIfName: String? = null
    private var resetJob: Job? = null

    suspend fun start(scope: CoroutineScope, onNetworkSwitch: () -> Unit) {
        this.scope = scope
        this.onNetworkSwitch = onNetworkSwitch









        defaultNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            BoxApplication.connectivity.activeNetwork?.takeUnless(::isVpn)
        } else null
        logDefaultNetwork("init", defaultNetwork)

        DefaultNetworkListener.start(this) {
            defaultNetwork = it
            checkUpdate(it)
        }

        if (defaultNetwork == null && Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            defaultNetwork = DefaultNetworkListener.get()
        }
    }

    suspend fun stop() {
        DefaultNetworkListener.stop(this)
        resetJob?.cancel()
        resetJob = null
        onNetworkSwitch = null
        lastIfName = null
        scope = null
        listener = null
    }

    fun setListener(listener: InterfaceUpdateListener?) {
        this.listener = listener
        if (listener != null) notifySync(defaultNetwork, listener)
    }














    private fun notifySync(network: Network?, listener: InterfaceUpdateListener) {
        runCatching {
            if (network == null) {
                listener.updateDefaultInterface("", -1, false, false)
                return@runCatching
            }
            val linkProps = BoxApplication.connectivity.getLinkProperties(network)
            val ifName = linkProps?.interfaceName ?: ""
            if (ifName.isEmpty()) {
                listener.updateDefaultInterface("", -1, false, false)
                return@runCatching
            }
            for (attempt in 0 until 10) {
                try {
                    val ni = NetworkInterface.getByName(ifName) ?: continue
                    lastIfName = ifName
                    listener.updateDefaultInterface(ifName, ni.index, false, false)
                    return@runCatching
                } catch (_: Exception) {
                    Thread.sleep(50)
                }
            }
            listener.updateDefaultInterface("", -1, false, false)
        }.onFailure { e ->
            Log.e("LxBoxNet", "notifySync failed (fail-safe empty interface)", e)
            runCatching { listener.updateDefaultInterface("", -1, false, false) }
        }
    }

    private fun checkUpdate(network: Network?) {
        val l = listener ?: return
        val s = scope ?: return
        if (network == null) {



            s.launch(Dispatchers.IO) {
                runCatching { l.updateDefaultInterface("", -1, false, false) }
            }
            return
        }
        logDefaultNetwork("update", network)
        val linkProps = BoxApplication.connectivity.getLinkProperties(network)
        val ifName = linkProps?.interfaceName ?: return
        for (attempt in 0 until 10) {
            try {
                val ni = NetworkInterface.getByName(ifName) ?: continue
                maybeResetOnSwitch(ifName, s)
                lastIfName = ifName
                s.launch(Dispatchers.IO) {
                    runCatching { l.updateDefaultInterface(ifName, ni.index, false, false) }
                }
                return
            } catch (_: Exception) {
                Thread.sleep(100)
            }
        }
    }









    private fun maybeResetOnSwitch(newIfName: String, s: CoroutineScope) {
        val prev = lastIfName
        if (prev.isNullOrEmpty() || newIfName.isEmpty() || prev == newIfName) return
        resetJob?.cancel()
        resetJob = s.launch(Dispatchers.IO) {
            delay(RESET_DEBOUNCE_MS)
            runCatching { onNetworkSwitch?.invoke() }
        }
    }





    private fun isVpn(network: Network): Boolean =
        BoxApplication.connectivity.getNetworkCapabilities(network)
            ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

















    private fun logDefaultNetwork(where: String, network: Network?) {
        runCatching {
            if (network == null) {
                Log.i("LxBoxNet", "[$where] defaultNetwork=null")
                return
            }
            val ifName = BoxApplication.connectivity
                .getLinkProperties(network)?.interfaceName ?: "?"
            Log.i("LxBoxNet", "[$where] defaultNetwork iface=$ifName vpn=${isVpn(network)}")
        }
    }
}
