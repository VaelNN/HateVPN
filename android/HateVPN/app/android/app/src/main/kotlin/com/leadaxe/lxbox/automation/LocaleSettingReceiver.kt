package com.leadaxe.lxbox.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import com.leadaxe.lxbox.MainActivity
import com.leadaxe.lxbox.vpn.BootReceiver
import com.leadaxe.lxbox.vpn.BoxVpnService
import com.leadaxe.lxbox.vpn.VpnPlugin
import com.leadaxe.lxbox.vpn.VpnStatus














class LocaleSettingReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "LocaleSetting"
    }

    override fun onReceive(context: Context, intent: Intent) {


        try {
            if (intent.action != LocaleApi.ACTION_FIRE_SETTING) return
            val parsed = LocaleApi.parseSetting(
                intent.getBundleExtra(LocaleApi.EXTRA_BUNDLE),
            )
            if (parsed == null) {
                Log.w(TAG, "FIRE_SETTING — invalid/missing bundle, ignored")
                return
            }
            val (cmd, args) = parsed
            Log.d(TAG, "fire cmd=$cmd args=$args")
            when (cmd) {
                "start-vpn" -> BoxVpnService.start(context)
                "stop-vpn" -> BoxVpnService.stop(context)
                "toggle-vpn" -> handleToggle(context)
                else -> VpnPlugin.handleAutomationAction(cmd, args)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed", t)
        }
    }


    private fun handleToggle(context: Context) {
        if (BoxVpnService.currentStatus == VpnStatus.Started) {
            BoxVpnService.stop(context)
            return
        }

        if (!BootReceiver.hasTun(context) ||
            VpnService.prepare(context.applicationContext) == null) {
            BoxVpnService.start(context)
        } else {
            val launch = Intent(context, MainActivity::class.java).apply {
                putExtra(MainActivity.EXTRA_ACTION, MainActivity.ACTION_TOGGLE)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(launch)
        }
    }
}
