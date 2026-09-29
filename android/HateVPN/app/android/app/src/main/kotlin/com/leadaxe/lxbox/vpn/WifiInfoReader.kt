package com.leadaxe.lxbox.vpn

import android.content.Context
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.nekohasekai.libbox.WIFIState














object WifiInfoReader {




    private const val PLACEHOLDER_BSSID = "02:00:00:00:00:00"

    private const val UNKNOWN_SSID = "<unknown ssid>"

    private const val TAG = "WifiInfoReader"
    const val PERM_NEARBY = "android.permission.NEARBY_WIFI_DEVICES"
    const val PERM_FINE = "android.permission.ACCESS_FINE_LOCATION"
    const val PERM_BACKGROUND = "android.permission.ACCESS_BACKGROUND_LOCATION"






















    fun read(ctx: Context): Result {
        val blocked = preflight(ctx)
        if (blocked != null) {
            when (blocked) {
                is Result.PermissionMissing ->
                    Log.w(TAG, "permission missing: ${blocked.missing.joinToString(",")}")
                else -> Log.w(TAG, "location disabled: system location toggle is off")
            }


            if (Build.VERSION.SDK_INT >= 31) BoxApplication.wifiStateCacheOrNull?.stop()
            return blocked
        }

        var cacheUnknown = false
        var cacheNoWifi = false
        if (Build.VERSION.SDK_INT >= 31) {
            val cache = BoxApplication.wifiStateCacheOrNull
            if (cache != null) {
                cache.ensureCurrent()
                val snap = cache.latest
                if (snap != null && snap.ssid.isNotEmpty()) {
                    Log.d(TAG, "ok: source=cache ssid='${snap.ssid}' bssid='${snap.bssid}'")
                    return Result.Success(snap.ssid, snap.bssid)
                }
                if (snap != null) {


                    cacheUnknown = true
                    Log.d(TAG, "cache has unknown ssid, falling back: source=legacy")
                } else {
                    cacheNoWifi = true
                    Log.d(TAG, "cache empty (registered=${cache.isRegistered}), falling back: source=legacy")
                }
            }
        }
        return readLegacy(cacheUnknown, cacheNoWifi)
    }








    private fun readLegacy(cacheUnknown: Boolean, cacheNoWifi: Boolean = false): Result {
        @Suppress("DEPRECATION")
        val info = try {
            BoxApplication.wifiManager.connectionInfo
        } catch (e: SecurityException) {
            Log.w(TAG, "permission missing: SecurityException from connectionInfo: ${e.message}")
            return Result.PermissionMissing(emptyList())
        } catch (e: RuntimeException) {
            val msg = e.message ?: e.javaClass.simpleName
            Log.w(TAG, "runtime error from connectionInfo: $msg")
            return Result.RuntimeError(msg)
        }
        if (info == null) {
            Log.w(TAG, "no wifi: connectionInfo is null")
            return Result.NoWifi
        }

        val rawSsid = info.ssid
        val rawBssid = info.bssid
        val ssid = normalizeSsid(rawSsid)
        val bssid = normalizeBssid(rawBssid)
        if (cacheNoWifi && ssid.isEmpty() && rawBssid == null) {
            Log.w(TAG, "no wifi: not connected (cache has no wifi network, connectionInfo bssid=null)")
            return Result.NoWifi
        }
        if (ssid.isEmpty() || rawBssid?.lowercase() == PLACEHOLDER_BSSID) {
            val suffix = if (cacheUnknown) " (cache also unknown)" else ""
            Log.w(TAG, "unknown ssid: android returned ssid=$rawSsid bssid=$rawBssid$suffix")
            return Result.UnknownSsid
        }
        Log.d(TAG, "ok: source=legacy ssid='$ssid' bssid='$bssid'")
        return Result.Success(ssid, bssid)
    }



    fun normalizeSsid(raw: String?): String {
        if (raw == null || raw == UNKNOWN_SSID) return ""
        if (raw.length >= 2 && raw.startsWith("\"") && raw.endsWith("\"")) {
            return raw.substring(1, raw.length - 1)
        }
        return raw
    }



    fun normalizeBssid(raw: String?): String {
        val b = raw?.lowercase() ?: return ""
        return if (b == PLACEHOLDER_BSSID) "" else b
    }




    fun readAsState(ctx: Context): WIFIState? = when (val r = read(ctx)) {
        is Result.Success -> WIFIState(r.ssid, r.bssid)
        is Result.UnknownSsid -> WIFIState("", "")
        else -> null
    }




    fun preflight(ctx: Context): Result? {
        val missing = missingPermissions(ctx)
        if (missing.isNotEmpty()) return Result.PermissionMissing(missing)
        if (!isLocationEnabled(ctx)) return Result.LocationDisabled
        return null
    }




    fun permissionSnapshot(ctx: Context): String {
        fun bit(v: Boolean) = if (v) '1' else '0'
        val nearby = Build.VERSION.SDK_INT < 33 || PermissionUtils.has(ctx, PERM_NEARBY)
        val fine = PermissionUtils.has(ctx, PERM_FINE)
        val bg = Build.VERSION.SDK_INT < 29 || PermissionUtils.has(ctx, PERM_BACKGROUND)
        return "nearby=${bit(nearby)} fine=${bit(fine)} bg=${bit(bg)} loc=${bit(isLocationEnabled(ctx))}"
    }







    private fun missingPermissions(ctx: Context): List<String> {
        val missing = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33 && !PermissionUtils.has(ctx, PERM_NEARBY)) {
            missing += PERM_NEARBY
        }
        if (!PermissionUtils.has(ctx, PERM_FINE)) {
            missing += PERM_FINE
        }
        if (Build.VERSION.SDK_INT >= 29 && !PermissionUtils.has(ctx, PERM_BACKGROUND)) {
            missing += PERM_BACKGROUND
        }
        return missing
    }




    private fun isLocationEnabled(ctx: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= 28) {
            val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            lm?.isLocationEnabled ?: true
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(ctx.contentResolver, Settings.Secure.LOCATION_MODE) !=
                Settings.Secure.LOCATION_MODE_OFF
        }
    } catch (_: Exception) {
        true
    }

    sealed interface Result {
        data class Success(val ssid: String, val bssid: String) : Result
        data class PermissionMissing(val missing: List<String>) : Result
        object LocationDisabled : Result
        object NoWifi : Result
        object UnknownSsid : Result
        data class RuntimeError(val message: String) : Result
    }
}
