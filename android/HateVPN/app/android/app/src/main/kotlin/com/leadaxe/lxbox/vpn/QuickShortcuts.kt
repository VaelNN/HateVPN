package com.leadaxe.lxbox.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import com.leadaxe.lxbox.MainActivity
import com.leadaxe.lxbox.R















object QuickShortcuts {
    private const val TAG = "QuickShortcuts"

    private const val ID_CONNECT = "qc_connect"
    private const val ID_DISCONNECT = "qc_disconnect"

    fun refresh(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            doRefresh(ctx)
        } catch (t: Throwable) {

            Log.w(TAG, "refresh failed: ${t.message}")
        }
    }

    private fun doRefresh(ctx: Context) {
        val sm = ctx.getSystemService(ShortcutManager::class.java) ?: return

        val list = mutableListOf<ShortcutInfo>()
        when (BoxVpnService.currentStatus) {
            VpnStatus.Stopped -> list += buildConnect(ctx)
            VpnStatus.Started -> list += buildDisconnect(ctx)
            VpnStatus.Starting, VpnStatus.Stopping -> {
                list += buildConnect(ctx)
                list += buildDisconnect(ctx)
            }
        }
        try {
            sm.dynamicShortcuts = list
        } catch (e: IllegalStateException) {


            Log.w(TAG, "dynamicShortcuts rate-limited: ${e.message}")
        }
    }

    private fun buildConnect(ctx: Context): ShortcutInfo = build(
        ctx, ID_CONNECT,
        L10n.str(ctx, R.string.qc_connect_label),
        MainActivity.ACTION_CONNECT,
    )

    private fun buildDisconnect(ctx: Context): ShortcutInfo = build(
        ctx, ID_DISCONNECT,
        L10n.str(ctx, R.string.qc_disconnect_label),
        MainActivity.ACTION_DISCONNECT,
    )









    fun relabel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val sm = ctx.getSystemService(ShortcutManager::class.java) ?: return
            val both = listOf(buildConnect(ctx), buildDisconnect(ctx))
            val ok = try {
                sm.updateShortcuts(both)
            } catch (e: IllegalStateException) {
                Log.w(TAG, "updateShortcuts rate-limited: ${e.message}")
                false
            }
            BootReceiver.setShortcutRelabelPending(ctx, !ok)
        } catch (t: Throwable) {
            Log.w(TAG, "relabel failed: ${t.message}")
            BootReceiver.setShortcutRelabelPending(ctx, true)
        }
    }


    fun retryPendingRelabel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            if (!BootReceiver.isShortcutRelabelPending(ctx)) return
            relabel(ctx)
        } catch (t: Throwable) {
            Log.w(TAG, "retryPendingRelabel failed: ${t.message}")
        }
    }

    private fun build(ctx: Context, id: String, label: String, action: String): ShortcutInfo {





        val iconRes = when (action) {
            MainActivity.ACTION_CONNECT -> R.mipmap.ic_qc_connect
            MainActivity.ACTION_DISCONNECT -> R.mipmap.ic_qc_disconnect
            else -> R.drawable.ic_lxbox_tile
        }
        val intent = Intent(ctx, MainActivity::class.java).apply {
            this.action = Intent.ACTION_MAIN
            putExtra(MainActivity.EXTRA_ACTION, action)


            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return ShortcutInfo.Builder(ctx, id)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(Icon.createWithResource(ctx, iconRes))
            .setIntent(intent)
            .build()
    }
}
