package com.leadaxe.lxbox.vpn

import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import android.system.OsConstants
import androidx.annotation.RequiresApi
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

interface PlatformInterfaceWrapper : PlatformInterface {

    override fun localDNSTransport(): LocalDNSTransport? = LocalResolver

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {}

    override fun openTun(options: TunOptions): Int = error("invalid argument")

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String, sourcePort: Int,
        destinationAddress: String, destinationPort: Int
    ): ConnectionOwner {








        val uid = try {
            BoxApplication.connectivity.getConnectionOwnerUid(
                ipProtocol,
                InetSocketAddress(sourceAddress, sourcePort),
                InetSocketAddress(destinationAddress, destinationPort)
            )
        } catch (e: Exception) {
            android.util.Log.w("PIW", "findConnectionOwner: getConnectionOwnerUid failed: ${e.message}")
            Process.INVALID_UID
        }
        if (uid == Process.INVALID_UID) {
            return ConnectionOwner().apply { userId = Process.INVALID_UID }
        }




        val packages = try {
            BoxApplication.packageManager.getPackagesForUid(uid)?.toList() ?: emptyList()
        } catch (e: Exception) {
            android.util.Log.w("PIW", "findConnectionOwner: getPackagesForUid failed: ${e.message}")
            emptyList()
        }
        return ConnectionOwner().apply {
            userId = uid



            userName = packages.firstOrNull() ?: ""
            setAndroidPackageNames(StringArray(packages.iterator()))
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(null)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {







        return runCatching { buildInterfaces() }
            .getOrElse {
                android.util.Log.w("PIW", "getInterfaces failed, returning empty: ${it.message}")
                emptyInterfaceIterator()
            }
    }

    private fun buildInterfaces(): NetworkInterfaceIterator {
        val networks = BoxApplication.connectivity.allNetworks
        val sysInterfaces = NetworkInterface.getNetworkInterfaces().toList()
        val result = mutableListOf<LibboxNetworkInterface>()
        for (network in networks) {
            val lp = BoxApplication.connectivity.getLinkProperties(network) ?: continue
            val caps = BoxApplication.connectivity.getNetworkCapabilities(network) ?: continue
            val ni = sysInterfaces.find { it.name == lp.interfaceName } ?: continue
            val box = LibboxNetworkInterface().apply {
                name = lp.interfaceName
                dnsServer = StringArray(lp.dnsServers.mapNotNull { it.hostAddress }.iterator())
                type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                index = ni.index
                runCatching { mtu = ni.mtu }
                addresses = StringArray(ni.interfaceAddresses.map { it.toPrefix() }.iterator())
                var flags = 0
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
                    flags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                if (ni.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
                if (ni.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
                if (ni.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
                this.flags = flags
                metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            }
            result.add(box)
        }
        return object : NetworkInterfaceIterator {
            val iter = result.iterator()
            override fun hasNext() = iter.hasNext()
            override fun next() = iter.next()
        }
    }

    private fun emptyInterfaceIterator(): NetworkInterfaceIterator =
        object : NetworkInterfaceIterator {
            override fun hasNext() = false





            override fun next(): LibboxNetworkInterface = LibboxNetworkInterface()
        }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}






























    override fun readWIFIState(): WIFIState? {
        val state = WifiInfoReader.readAsState(BoxApplication.application)
        if (state == null) {
            android.util.Log.w("PIW",
                "readWIFIState: null (permission missing / location off / no wifi / runtime error)")
        } else if (state.ssid.isEmpty()) {
            android.util.Log.w("PIW",
                "readWIFIState: <unknown ssid> — see WifiInfoReader log for the reason")
        } else {
            android.util.Log.d("PIW",
                "readWIFIState: ssid='${state.ssid}' bssid='${state.bssid}'")
        }
        return state
    }


















    override fun registerMyInterface(name: String) {}

    override fun usePlatformShell(): Boolean = false

    override fun checkPlatformShell() {}

    override fun lookupUser(username: String): io.nekohasekai.libbox.PlatformUser =
        io.nekohasekai.libbox.PlatformUser()

    override fun lookupSFTPServer(): String = ""

    override fun readSystemSSHHostKey(): String = ""

    override fun tailscaleHostname(): String = ""

    override fun openShellSession(
        user: io.nekohasekai.libbox.PlatformUser,
        command: String,
        env: StringIterator,
        termType: String,
        width: Int,
        height: Int
    ): io.nekohasekai.libbox.ShellSession = throw UnsupportedOperationException("shell not supported on Android")

    override fun startNeighborMonitor(listener: io.nekohasekai.libbox.NeighborUpdateListener) {}

    override fun closeNeighborMonitor(listener: io.nekohasekai.libbox.NeighborUpdateListener) {}










    override fun usePlatformBridge(): Boolean = false







    override fun cancelNotification(identifier: String, typeID: Int) {}

    override fun createBridge(
        options: io.nekohasekai.libbox.BridgeOptions
    ): io.nekohasekai.libbox.BridgeSession =
        throw UnsupportedOperationException("platform bridge not used on Android")

    private class StringArray(private val iter: Iterator<String>) : StringIterator {
        override fun hasNext() = iter.hasNext()


        override fun next(): String = if (iter.hasNext()) iter.next() else ""
        override fun len(): Int = 0
    }
}

private fun InterfaceAddress.toPrefix(): String {
    return if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }
}

