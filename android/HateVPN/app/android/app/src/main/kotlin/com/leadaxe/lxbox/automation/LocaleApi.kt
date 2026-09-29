package com.leadaxe.lxbox.automation

import android.content.Context
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject










object LocaleApi {

    const val ACTION_EDIT_SETTING = "com.twofortyfouram.locale.intent.action.EDIT_SETTING"
    const val ACTION_FIRE_SETTING = "com.twofortyfouram.locale.intent.action.FIRE_SETTING"
    const val ACTION_EDIT_CONDITION = "com.twofortyfouram.locale.intent.action.EDIT_CONDITION"
    const val ACTION_QUERY_CONDITION = "com.twofortyfouram.locale.intent.action.QUERY_CONDITION"

    const val EXTRA_BUNDLE = "com.twofortyfouram.locale.intent.extra.BUNDLE"
    const val EXTRA_STRING_BLURB = "com.twofortyfouram.locale.intent.extra.BLURB"


    const val RESULT_CONDITION_SATISFIED = 16
    const val RESULT_CONDITION_UNSATISFIED = 17
    const val RESULT_CONDITION_UNKNOWN = 18


    const val BUNDLE_MAX_BYTES = 25_000


    const val KEY_CONFIG = "com.leadaxe.lxbox.plugin.CONFIG"


    const val BUNDLE_VERSION = 1





    fun buildSettingBundle(cmd: String, args: Map<String, Any?>): Bundle {
        val json = JSONObject()
            .put("v", BUNDLE_VERSION)
            .put("cmd", cmd)
            .put("args", JSONObject(args.filterValues { it != null }))
        return Bundle().apply { putString(KEY_CONFIG, json.toString()) }
    }


    fun parseSetting(bundle: Bundle?): Pair<String, Map<String, Any?>>? {
        val raw = bundle?.getString(KEY_CONFIG) ?: return null
        return runCatching {
            val obj = JSONObject(raw)
            val cmd = obj.optString("cmd").ifEmpty { return@runCatching null }
            val argsObj = obj.optJSONObject("args") ?: JSONObject()
            val args = mutableMapOf<String, Any?>()
            for (key in argsObj.keys()) args[key] = argsObj.get(key)
            cmd to args
        }.getOrNull()
    }





    fun buildConditionBundle(check: String, equals: String?): Bundle {
        val json = JSONObject()
            .put("v", BUNDLE_VERSION)
            .put("check", check)
        if (equals != null) json.put("equals", equals)
        return Bundle().apply { putString(KEY_CONFIG, json.toString()) }
    }



    private const val PREFS = "lxbox_automation"




    fun cachedNodes(ctx: Context): List<String> =
        readStringArray(ctx, "all_nodes")


    fun cachedGroups(ctx: Context): List<String> =
        readStringArray(ctx, "all_groups")

    private fun readStringArray(ctx: Context, key: String): List<String> {
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(key, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }
        }.getOrDefault(emptyList())
    }


    fun parseCondition(bundle: Bundle?): Pair<String, String?>? {
        val raw = bundle?.getString(KEY_CONFIG) ?: return null
        return runCatching {
            val obj = JSONObject(raw)
            val check = obj.optString("check").ifEmpty { return@runCatching null }
            val equals = if (obj.has("equals")) obj.optString("equals") else null
            check to equals
        }.getOrNull()
    }
}
