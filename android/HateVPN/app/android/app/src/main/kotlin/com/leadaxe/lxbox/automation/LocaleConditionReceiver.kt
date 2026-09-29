package com.leadaxe.lxbox.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.leadaxe.lxbox.vpn.BoxVpnService
import com.leadaxe.lxbox.vpn.VpnStatus










class LocaleConditionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "LocaleCondition"
        private const val PREFS = "lxbox_automation"
        private const val KEY_ACTIVE_NODE = "active_node"
        private const val KEY_ACTIVE_GROUP = "active_group"
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action != LocaleApi.ACTION_QUERY_CONDITION) {
                setResultCode(LocaleApi.RESULT_CONDITION_UNKNOWN)
                return
            }
            val parsed = LocaleApi.parseCondition(
                intent.getBundleExtra(LocaleApi.EXTRA_BUNDLE),
            )
            if (parsed == null) {
                Log.w(TAG, "QUERY — invalid/missing bundle → UNKNOWN")
                setResultCode(LocaleApi.RESULT_CONDITION_UNKNOWN)
                return
            }
            val (check, equals) = parsed
            val result = evaluate(context, check, equals)
            Log.d(TAG, "query check=$check equals=$equals → $result")
            setResultCode(result)
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed → UNKNOWN", t)

            runCatching { setResultCode(LocaleApi.RESULT_CONDITION_UNKNOWN) }
        }
    }

    private fun evaluate(context: Context, check: String, equals: String?): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return when (check) {
            "vpn-up" -> satisfied(BoxVpnService.currentStatus == VpnStatus.Started)
            "active-node" -> matchCached(prefs.getString(KEY_ACTIVE_NODE, null), equals)
            "active-group" -> matchCached(prefs.getString(KEY_ACTIVE_GROUP, null), equals)
            else -> LocaleApi.RESULT_CONDITION_UNKNOWN
        }
    }



    private fun matchCached(cached: String?, equals: String?): Int {
        if (equals.isNullOrEmpty() || cached == null) {
            return LocaleApi.RESULT_CONDITION_UNKNOWN
        }
        return satisfied(cached == equals)
    }

    private fun satisfied(value: Boolean): Int =
        if (value) LocaleApi.RESULT_CONDITION_SATISFIED
        else LocaleApi.RESULT_CONDITION_UNSATISFIED
}
