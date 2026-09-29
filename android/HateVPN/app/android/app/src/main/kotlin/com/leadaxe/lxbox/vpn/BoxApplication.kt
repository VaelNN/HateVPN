package com.leadaxe.lxbox.vpn

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.PowerManager
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.SetupOptions
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import java.util.Locale













class BoxApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        instance = this














        runCatching {
            Libbox.setLocale(Locale.getDefault().toLanguageTag().replace("-", "_"))
        }.recoverCatching {
            Libbox.setLocale(Locale.getDefault().language)
        }.onFailure {
            android.util.Log.w(TAG, "setLocale failed, using core default: ${it.message}")
        }

        runCatching { QuickShortcuts.refresh(this) }
            .onFailure { android.util.Log.w(TAG, "QuickShortcuts.refresh failed: ${it.message}") }




        wifiObserver = WifiNetworkObserver(this)




        wifiStateCache = WifiStateCache(this)




        @Suppress("OPT_IN_USAGE")
        GlobalScope.launch(Dispatchers.IO) {
            try {
                initializeLibbox(this@BoxApplication)
                libboxReady.complete(Unit)
            } catch (t: Throwable) {
                android.util.Log.e(TAG, "initializeLibbox failed", t)
                libboxReady.completeExceptionally(t)
            }
        }
    }

    private fun initializeLibbox(context: Context) {
        val baseDir = context.filesDir.also { it.mkdirs() }
        val workingDir = baseDir
        val tempDir = context.cacheDir.also { it.mkdirs() }

        val fixAndroidStack =
            android.os.Build.VERSION.SDK_INT in android.os.Build.VERSION_CODES.N..android.os.Build.VERSION_CODES.N_MR1 ||
                    android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P

        val opts = SetupOptions().apply {
            basePath = baseDir.path
            workingPath = workingDir.path
            tempPath = tempDir.path
            this.fixAndroidStack = fixAndroidStack


            logMaxLines = 3000


            debug = BootReceiver.isCoreLogsEnabled(context)









            oomKillerEnabled = true
            oomMemoryLimit = resolveMemoryLimitBytes(context)




            crashReportSource = "lxbox"
        }





        if (CrashRecovery.crashedOnPreviousLaunch(workingDir)) {
            CrashRecovery.resetKernelCaches(tempDir)
        }
        Libbox.setup(opts)
    }

    companion object {
        private const val TAG = "BoxApplication"


        private val MEMORY_LIMIT_PRESETS_MB = setOf(200L, 384L, 512L, 768L)











        fun resolveMemoryLimitBytes(context: Context): Long {
            val value = BootReceiver.getMemoryLimit(context)
            value.toLongOrNull()?.let { mb ->
                if (mb in MEMORY_LIMIT_PRESETS_MB) return mb * 1024 * 1024
            }
            if (value == BootReceiver.MEMORY_LIMIT_OFF) return 0L

            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val mi = android.app.ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            val gib = 1024L * 1024 * 1024
            val autoMb = when {
                mi.totalMem < 7L * gib / 2 -> 200L
                mi.totalMem < 7L * gib -> 384L
                else -> 512L
            }
            return autoMb * 1024 * 1024
        }



        @Volatile
        internal lateinit var instance: BoxApplication


        val libboxReady: CompletableDeferred<Unit> = CompletableDeferred()




        @Volatile
        internal lateinit var wifiObserver: WifiNetworkObserver



        @Volatile
        internal lateinit var wifiStateCache: WifiStateCache


        internal val wifiStateCacheOrNull: WifiStateCache?
            get() = if (::wifiStateCache.isInitialized) wifiStateCache else null






        val application: Context get() = instance

        val powerManager: PowerManager
            get() = instance.getSystemService(Context.POWER_SERVICE) as PowerManager

        val connectivity: ConnectivityManager
            get() = instance.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val packageManager get() = instance.packageManager

        val notificationManager: NotificationManager
            get() = instance.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager





        val wifiManager: WifiManager
            get() = instance.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager








        @Suppress("UNUSED_PARAMETER")
        fun initialize(context: Context) {

        }
    }
}
