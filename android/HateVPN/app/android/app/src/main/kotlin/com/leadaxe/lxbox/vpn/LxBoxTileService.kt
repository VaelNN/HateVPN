package com.leadaxe.lxbox.vpn

import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import android.widget.Toast
import androidx.annotation.RequiresApi
import com.leadaxe.lxbox.MainActivity
import com.leadaxe.lxbox.R

class LxBoxTileService : TileService() {

    companion object {
        private const val TAG = "LxBoxTileService"






        @Volatile
        private var instanceRef: java.lang.ref.WeakReference<LxBoxTileService>? = null

        private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())









        fun refreshTile(ctx: android.content.Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
            try {
                instanceRef?.get()?.let { svc ->
                    mainHandler.post { runCatching { svc.renderTile() } }
                }
                requestListeningState(
                    ctx,
                    ComponentName(ctx, LxBoxTileService::class.java),
                )
            } catch (e: Throwable) {


                Log.w(TAG, "refreshTile failed: ${e.message}")
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        instanceRef = java.lang.ref.WeakReference(this)
        renderTile()
    }

    override fun onStopListening() {
        super.onStopListening()

        if (instanceRef?.get() === this) instanceRef = null
    }

    override fun onClick() {
        super.onClick()
        val cur = BoxVpnService.currentStatus
        Log.d(TAG, "onClick — currentStatus=${cur.name}")
        when (cur) {
            VpnStatus.Stopped -> {




                renderTile(VpnStatus.Started)
                connectOrPromptConsent()
            }
            VpnStatus.Started -> {
                renderTile(VpnStatus.Stopped)
                BoxVpnService.stop(applicationContext)
            }

            else -> {
                Log.d(TAG, "onClick ignored in transient state ${cur.name}")
                renderTile()
            }
        }
    }

    private fun connectOrPromptConsent() {

        val needConsent = BootReceiver.hasTun(applicationContext) &&
            VpnService.prepare(applicationContext) != null
        if (!needConsent) {
            BoxVpnService.start(applicationContext)
            return
        }






        mainHandler.post {

            Toast.makeText(
                applicationContext,
                L10n.str(applicationContext, R.string.qc_first_open),
                Toast.LENGTH_SHORT,
            ).show()
        }
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            putExtra("action", "connect")
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {


            val pi = android.app.PendingIntent.getActivity(
                applicationContext,
                0,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }



    private fun renderTile(override: VpnStatus? = null) {
        val tile = qsTile ?: return
        val effective = override ?: BoxVpnService.currentStatus

        val (state, subtitle) = when (effective) {
            VpnStatus.Started ->
                Tile.STATE_ACTIVE to L10n.str(this, R.string.status_connected)


            VpnStatus.Starting ->
                Tile.STATE_ACTIVE to L10n.str(this, R.string.tile_status_connecting)


            VpnStatus.Stopping ->
                Tile.STATE_INACTIVE to L10n.str(this, R.string.tile_status_stopping)
            VpnStatus.Stopped ->
                Tile.STATE_INACTIVE to L10n.str(this, R.string.tile_status_disconnected)
        }
        tile.state = state
        tile.label = L10n.str(this, R.string.app_name)




        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            applySubtitle(tile, subtitle)
        }
        try {
            tile.icon = Icon.createWithResource(this, R.drawable.ic_lxbox_tile)
        } catch (_: Exception) {


        }
        tile.updateTile()
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun applySubtitle(tile: Tile, text: String) {
        tile.subtitle = text
    }
}
