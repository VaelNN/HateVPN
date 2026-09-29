package com.leadaxe.lxbox.vpn

import android.util.Log
import java.io.File





object ConfigManager {
    private const val TAG = "ConfigManager"
    private const val CONFIG_FILE = "singbox_config.json"

    var notificationTitle: String = "HateVPN"
        private set



    var notificationText: String = ""
        private set

    private var cachedConfig: String? = null

    fun save(json: String): Boolean {
        return try {

            val clean = stripClashApi(json)
            val file = File(BoxApplication.application.filesDir, CONFIG_FILE)
            file.writeText(clean)
            cachedConfig = clean
            Log.d(TAG, "Config saved (${clean.length} bytes)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save config", e)
            false
        }
    }

    fun load(): String {
        cachedConfig?.let { return it }
        return try {
            val file = File(BoxApplication.application.filesDir, CONFIG_FILE)
            if (file.exists()) {
                val content = stripClashApi(file.readText())
                cachedConfig = content
                content
            } else {
                "{}"
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load config", e)
            "{}"
        }
    }






    private fun stripClashApi(json: String): String {
        return try {
            val root = org.json.JSONObject(json)
            val exp = root.optJSONObject("experimental") ?: return json
            if (!exp.has("clash_api")) return json
            exp.remove("clash_api")
            Log.d(TAG, "stripClashApi: removed experimental.clash_api (rc.2 has no with_clash_api)")
            root.toString()
        } catch (e: Exception) {

            Log.w(TAG, "stripClashApi failed, passing through: ${e.message}")
            json
        }
    }

    fun setNotificationTitle(title: String) {
        notificationTitle = title
    }

    fun setNotificationText(text: String) {
        notificationText = text
    }
}

