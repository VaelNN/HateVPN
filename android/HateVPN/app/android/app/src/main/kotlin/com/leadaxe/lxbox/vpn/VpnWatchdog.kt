package com.leadaxe.lxbox.vpn

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import com.leadaxe.lxbox.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch


































object VpnWatchdog {
    private const val TAG = "VpnWatchdog"
    const val INTERVAL_MS = 2 * 60 * 1000L
    const val PERIOD_MS = INTERVAL_MS / 2
    private const val REQUEST_CODE = 428

    private fun pendingIntent(ctx: Context): PendingIntent =
        PendingIntent.getBroadcast(
            ctx, REQUEST_CODE,
            Intent(ctx, VpnWatchdogReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )



    fun arm(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        runCatching {
            am.set(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + INTERVAL_MS,
                pendingIntent(ctx),
            )
        }.onFailure { Log.w(TAG, "arm failed: $it") }
    }

    fun disarm(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        runCatching { am.cancel(pendingIntent(ctx)) }
            .onFailure { Log.w(TAG, "disarm failed: $it") }
    }




    fun startTicker(ctx: Context, scope: CoroutineScope, isStarted: () -> Boolean): Job {
        arm(ctx)
        return scope.launch {
            while (isActive) {
                delay(PERIOD_MS)
                if (isStarted()) arm(ctx)
            }
        }
    }
}

class VpnWatchdogReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "VpnWatchdog"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val ctx = context.applicationContext
        if (!BootReceiver.isVpnDesired(ctx)) {
            Log.d(TAG, "[vpn §428] alarm fired, VPN not desired — ignore")
            return
        }
        val status = BoxVpnService.currentStatus
        if (status != VpnStatus.Stopped) {

            Log.d(TAG, "[vpn §428] alarm fired, service alive (status=${status.name}) — re-arm")
            VpnWatchdog.arm(ctx)
            return
        }
        val n = BootReceiver.noteStickyRestart(ctx)
        Log.w(TAG, "[vpn §428] alarm fired, VPN desired but service dead — restart #$n")
        if (n >= BootReceiver.STICKY_RESTART_LIMIT) {
            BootReceiver.setVpnDesired(ctx, false)
            ServiceNotification.showAlert(
                ctx,
                L10n.str(ctx, R.string.sticky_restart_storm_title),
                L10n.str(ctx, R.string.sticky_restart_storm_text),
            )
            return
        }
        BoxVpnService.start(ctx)
    }
}
