package com.leadaxe.lxbox.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREF_NAME = "boxvpn_boot"
        private const val KEY_AUTO_START = "auto_start_vpn"
        private const val KEY_KEEP_ON_EXIT = "keep_vpn_on_exit"
        private const val KEY_BACKGROUND_MODE = "background_mode"





        private const val KEY_CORE_LOGS = "core_logs_enabled"

        private const val KEY_CORE_LOGS_VERBOSE = "core_logs_verbose"






        private const val KEY_ALLOW_BYPASS = "allow_bypass"







        private const val KEY_AUTO_REDIRECT = "auto_redirect"









        private const val KEY_HAS_TUN = "has_tun"





        private const val KEY_MEMORY_LIMIT = "memory_limit"

        const val MEMORY_LIMIT_AUTO = "auto"
        const val MEMORY_LIMIT_OFF = "off"






        private const val KEY_APP_LANGUAGE = "app_language"







        private const val KEY_LAST_PUSHED_LOCALE = "last_pushed_locale"




        private const val KEY_SHORTCUT_RELABEL_PENDING = "shortcut_relabel_pending"



        private const val KEY_STICKY_RESTART_COUNT = "sticky_restart_count"
        private const val KEY_STICKY_RESTART_WINDOW_START = "sticky_restart_window_start"
        const val STICKY_RESTART_WINDOW_MS = 5 * 60 * 1000L


        private const val KEY_VPN_DESIRED = "vpn_desired"
        const val STICKY_RESTART_LIMIT = 3








        const val BG_MODE_NEVER = "never"
        const val BG_MODE_LAZY = "lazy"
        const val BG_MODE_ALWAYS = "always"



        fun setAppLanguage(context: Context, value: String) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putString(KEY_APP_LANGUAGE, value).apply()
        }

        fun getAppLanguage(context: Context): String {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(KEY_APP_LANGUAGE, "system") ?: "system"
        }


        fun setLastPushedLocale(context: Context, value: String) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putString(KEY_LAST_PUSHED_LOCALE, value).apply()
        }

        fun getLastPushedLocale(context: Context): String? {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(KEY_LAST_PUSHED_LOCALE, null)
        }


        fun setShortcutRelabelPending(context: Context, pending: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_SHORTCUT_RELABEL_PENDING, pending).apply()
        }




        fun noteStickyRestart(context: Context, now: Long = System.currentTimeMillis()): Int {
            val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            val windowStart = prefs.getLong(KEY_STICKY_RESTART_WINDOW_START, 0L)
            val inWindow = windowStart > 0L && now - windowStart < STICKY_RESTART_WINDOW_MS
            val count = if (inWindow) prefs.getInt(KEY_STICKY_RESTART_COUNT, 0) + 1 else 1
            prefs.edit()
                .putInt(KEY_STICKY_RESTART_COUNT, count)
                .putLong(KEY_STICKY_RESTART_WINDOW_START, if (inWindow) windowStart else now)
                .apply()
            return count
        }

        fun setVpnDesired(context: Context, desired: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_VPN_DESIRED, desired).apply()
        }

        fun isVpnDesired(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_VPN_DESIRED, false)
        }

        fun resetStickyRestarts(context: Context) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_STICKY_RESTART_COUNT)
                .remove(KEY_STICKY_RESTART_WINDOW_START)
                .apply()
        }

        fun isShortcutRelabelPending(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_SHORTCUT_RELABEL_PENDING, false)
        }

        fun setMemoryLimit(context: Context, value: String) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putString(KEY_MEMORY_LIMIT, value).apply()
        }

        fun getMemoryLimit(context: Context): String {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(KEY_MEMORY_LIMIT, MEMORY_LIMIT_AUTO) ?: MEMORY_LIMIT_AUTO
        }

        fun setBackgroundMode(context: Context, mode: String) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putString(KEY_BACKGROUND_MODE, mode).apply()
        }

        fun getBackgroundMode(context: Context): String {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(KEY_BACKGROUND_MODE, BG_MODE_NEVER) ?: BG_MODE_NEVER
        }

        fun setEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_AUTO_START, enabled).apply()
        }

        fun isEnabled(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_AUTO_START, false)
        }

        fun setKeepOnExit(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_KEEP_ON_EXIT, enabled).apply()
        }

        fun isKeepOnExit(context: Context): Boolean {


            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_KEEP_ON_EXIT, true)
        }




        fun setCoreLogsEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_CORE_LOGS, enabled).apply()
        }

        fun isCoreLogsEnabled(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_CORE_LOGS, false)
        }




        fun setCoreLogsVerbose(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_CORE_LOGS_VERBOSE, enabled).apply()
        }

        fun isCoreLogsVerbose(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_CORE_LOGS_VERBOSE, false)
        }



        fun setAllowBypass(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_ALLOW_BYPASS, enabled).apply()
        }

        fun isAllowBypass(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_ALLOW_BYPASS, false)
        }


        fun setAutoRedirect(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_AUTO_REDIRECT, enabled).apply()
        }

        fun isAutoRedirect(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_AUTO_REDIRECT, false)
        }


        fun setHasTun(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_HAS_TUN, enabled).apply()
        }

        fun hasTun(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_HAS_TUN, true)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!isEnabled(context)) return

        Log.d(TAG, "Boot completed — auto-starting VPN")
        BoxApplication.initialize(context)
        BoxVpnService.start(context)
    }
}
