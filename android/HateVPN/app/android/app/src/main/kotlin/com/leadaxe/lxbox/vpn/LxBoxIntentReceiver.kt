package com.leadaxe.lxbox.vpn

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.util.Log
import com.leadaxe.lxbox.MainActivity
















class LxBoxIntentReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "LxBoxIntent"

        const val ACTION_START_VPN = "com.leadaxe.lxbox.START_VPN"
        const val ACTION_STOP_VPN = "com.leadaxe.lxbox.STOP_VPN"
        const val ACTION_TOGGLE_VPN = "com.leadaxe.lxbox.TOGGLE_VPN"
        const val ACTION_SWITCH_NODE = "com.leadaxe.lxbox.SWITCH_NODE"
        const val ACTION_SET_GROUP = "com.leadaxe.lxbox.SET_GROUP"
        const val ACTION_REBUILD_CONFIG = "com.leadaxe.lxbox.REBUILD_CONFIG"
        const val ACTION_REFRESH_SUBS = "com.leadaxe.lxbox.REFRESH_SUBS"
        const val ACTION_RESET_NETWORK = "com.leadaxe.lxbox.RESET_NETWORK"
        const val ACTION_URLTEST_GROUP = "com.leadaxe.lxbox.URLTEST_GROUP"

        const val EXTRA_TAG = "tag"
        const val EXTRA_GROUP = "group"
        const val EXTRA_FORCE = "force"








        fun setEnabled(ctx: Context, enabled: Boolean) {
            val pm = ctx.packageManager
            val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED

            val components = listOf(
                ComponentName(ctx, LxBoxIntentReceiver::class.java),
                ComponentName(ctx, "com.leadaxe.lxbox.automation.LocaleSettingReceiver"),
                ComponentName(ctx, "com.leadaxe.lxbox.automation.LocaleConditionReceiver"),
            )
            for (c in components) {
                pm.setComponentEnabledSetting(c, state, PackageManager.DONT_KILL_APP)
            }
            Log.d(TAG, "automation receivers ${if (enabled) "enabled" else "disabled"} (raw + Locale)")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {



        try {
            dispatch(context, intent)
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed for ${intent.action}", t)
        }
    }

    private fun dispatch(context: Context, intent: Intent) {
        val action = intent.action ?: return



        val callerPkg = intent.`package` ?: "<unknown>"
        Log.d(TAG, "received $action from $callerPkg")

        when (action) {
            ACTION_START_VPN -> BoxVpnService.start(context)
            ACTION_STOP_VPN -> BoxVpnService.stop(context)
            ACTION_TOGGLE_VPN -> handleToggle(context)
            ACTION_SWITCH_NODE -> {
                val tag = intent.getStringExtra(EXTRA_TAG)
                if (tag.isNullOrEmpty()) {
                    Log.w(TAG, "SWITCH_NODE missing extra '$EXTRA_TAG'")
                    return
                }
                forward(context, "switch-node", mapOf("tag" to tag))
            }
            ACTION_SET_GROUP -> {
                val group = intent.getStringExtra(EXTRA_GROUP)
                if (group.isNullOrEmpty()) {
                    Log.w(TAG, "SET_GROUP missing extra '$EXTRA_GROUP'")
                    return
                }
                forward(context, "set-group", mapOf("group" to group))
            }
            ACTION_REBUILD_CONFIG -> forward(context, "rebuild-config", emptyMap())
            ACTION_REFRESH_SUBS -> {
                val force = intent.getBooleanExtra(EXTRA_FORCE, false)
                forward(context, "refresh-subs", mapOf("force" to force))
            }
            ACTION_RESET_NETWORK -> forward(context, "reset-network", emptyMap())
            ACTION_URLTEST_GROUP -> {
                val group = intent.getStringExtra(EXTRA_GROUP)
                if (group.isNullOrEmpty()) {
                    Log.w(TAG, "URLTEST_GROUP missing extra '$EXTRA_GROUP'")
                    return
                }
                forward(context, "urltest-group", mapOf("group" to group))
            }
            else -> Log.w(TAG, "unknown action $action")
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




    private fun forward(context: Context, name: String, args: Map<String, Any?>) {
        VpnPlugin.handleAutomationAction(name, args)
    }
}
