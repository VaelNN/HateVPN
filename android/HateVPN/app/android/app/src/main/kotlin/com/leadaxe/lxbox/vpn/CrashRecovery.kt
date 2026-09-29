package com.leadaxe.lxbox.vpn

import android.util.Log
import java.io.File











































internal object CrashRecovery {

    private const val TAG = "CrashRecovery"


    private const val CRASH_REPORT_NAME = "CrashReport-lxbox.log"











    fun crashedOnPreviousLaunch(workingDir: File): Boolean {
        val report = File(workingDir, CRASH_REPORT_NAME)
        return runCatching { report.isFile && report.length() > 0 }
            .getOrElse {
                Log.w(TAG, "crash report probe failed: ${it.message}")
                false
            }
    }



















    fun resetKernelCaches(tempDir: File) {
        Log.i(TAG, "[§334] previous launch crashed — resetting kernel caches")
        BoxVpnService.deleteCacheDbFile()
        clearTempDir(tempDir)
    }





    private fun clearTempDir(tempDir: File) {
        val entries = runCatching { tempDir.listFiles() }.getOrNull()
        if (entries == null) {
            Log.i(TAG, "[§334] temp dir unreadable or absent — nothing to clear")
            return
        }
        var removed = 0
        for (entry in entries) {
            if (runCatching { entry.deleteRecursively() }.getOrDefault(false)) removed++
        }
        Log.i(TAG, "[§334] temp dir cleared: $removed/${entries.size} (${tempDir.absolutePath})")
    }
}
