package com.leadaxe.lxbox.vpn

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import android.util.Log
import androidx.annotation.RequiresApi
import io.nekohasekai.libbox.Libbox
import java.util.Locale










object L10n {
    private const val TAG = "L10n"


    private val KNOWN = setOf("system", "en", "ru", "zh")

    const val SETTING_SYSTEM = "system"


    fun setting(base: Context): String {
        val v = BootReceiver.getAppLanguage(base)
        return if (v in KNOWN) v else SETTING_SYSTEM
    }



    fun ctx(base: Context): Context {
        val s = setting(base)
        if (s == SETTING_SYSTEM) return base
        val cfg = Configuration(base.resources.configuration)
        cfg.setLocale(Locale(s))
        return base.createConfigurationContext(cfg)
    }

    fun str(base: Context, id: Int, vararg args: Any): String =
        if (args.isEmpty()) ctx(base).getString(id)
        else ctx(base).getString(id, *args)






    fun applySetting(base: Context, raw: String) {
        val s = if (raw in KNOWN) raw else SETTING_SYSTEM
        BootReceiver.setAppLanguage(base, s)
        if (Build.VERSION.SDK_INT >= 33) {



            runCatching { pushApplicationLocales(base, s) }
                .onFailure { Log.w(TAG, "LocaleManager push failed: ${it.message}") }
        }
        refreshSurfaces(base)
    }

    @RequiresApi(33)
    private fun pushApplicationLocales(base: Context, s: String) {
        val lm = base.getSystemService(LocaleManager::class.java) ?: return
        lm.applicationLocales = if (s == SETTING_SYSTEM) {
            LocaleList.getEmptyLocaleList()
        } else {
            LocaleList.forLanguageTags(s)
        }


        BootReceiver.setLastPushedLocale(base, if (s == SETTING_SYSTEM) "" else s)
    }




    fun refreshSurfaces(base: Context) {

        runCatching { ServiceNotification.createChannel(base) }
            .onFailure { Log.w(TAG, "channel resubmit failed: ${it.message}") }



        runCatching { BoxVpnService.updateNotification(base) }
            .onFailure { Log.w(TAG, "notification relabel failed: ${it.message}") }

        runCatching { QuickShortcuts.relabel(base) }
            .onFailure { Log.w(TAG, "shortcuts relabel failed: ${it.message}") }

        runCatching { LxBoxTileService.refreshTile(base) }
            .onFailure { Log.w(TAG, "tile refresh failed: ${it.message}") }

        applyLibboxLocale(base)
    }







    fun applyLibboxLocale(base: Context) {
        val s = setting(base)
        runCatching {
            if (s == SETTING_SYSTEM) {


                runCatching {
                    Libbox.setLocale(
                        Locale.getDefault().toLanguageTag().replace("-", "_"))
                }.recoverCatching {
                    Libbox.setLocale(Locale.getDefault().language)
                }.getOrThrow()
            } else {
                Libbox.setLocale(s)
            }
        }.onFailure { Log.w(TAG, "Libbox.setLocale failed: ${it.message}") }
    }



    fun appLanguageState(base: Context): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < 33) return mapOf("supported" to false)
        return runCatching { readAppLanguageState(base) }
            .getOrElse { mapOf("supported" to false) }
    }

    @RequiresApi(33)
    private fun readAppLanguageState(base: Context): Map<String, Any?> {
        val lm = base.getSystemService(LocaleManager::class.java)
            ?: return mapOf("supported" to false)
        return mapOf<String, Any?>(
            "supported" to true,
            "applicationLocales" to lm.applicationLocales.toLanguageTags(),
            "lastPushedLocale" to BootReceiver.getLastPushedLocale(base),
        )
    }
}
