package com.leadaxe.lxbox.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log











class LocaleChangedReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "LocaleChangedReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_LOCALE_CHANGED) return
        if (L10n.setting(context) != L10n.SETTING_SYSTEM) return
        Log.d(TAG, "system locale changed → refresh native surfaces")
        runCatching { L10n.refreshSurfaces(context.applicationContext) }
            .onFailure { Log.w(TAG, "refreshSurfaces failed: ${it.message}") }
    }
}
