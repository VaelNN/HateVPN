package com.leadaxe.lxbox

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.telephony.TelephonyManager
import android.util.Log
import android.widget.Toast
import com.leadaxe.lxbox.vpn.BootReceiver
import com.leadaxe.lxbox.vpn.BoxApplication
import com.leadaxe.lxbox.vpn.BoxVpnService
import com.leadaxe.lxbox.vpn.L10n
import com.leadaxe.lxbox.vpn.PermissionUtils
import com.leadaxe.lxbox.vpn.QuickShortcuts
import com.leadaxe.lxbox.vpn.VpnPlugin
import com.leadaxe.lxbox.vpn.VpnStatus
import com.leadaxe.lxbox.vpn.WifiHistoryBridge
import com.leadaxe.lxbox.vpn.WifiInfoReader
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val VPN_REQUEST_CODE_QUICK = 7032
        private const val NOTIFICATION_PERMISSION_REQUEST = 7033
        private const val NEARBY_WIFI_PERMISSION_REQUEST = 7034
        private const val GET_CONTENT_REQUEST_CODE = 7035

        const val EXTRA_ACTION = "action"

        const val ACTION_CONNECT = "connect"
        const val ACTION_DISCONNECT = "disconnect"
        const val ACTION_TOGGLE = "toggle"
    }




    private var finishAfterConsent = false





    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val result = pendingNotificationResult
            pendingNotificationResult = null
            result?.success(null)
        }
    }

    override fun onDestroy() {
        pendingNotificationResult?.success(null)
        pendingNotificationResult = null
        super.onDestroy()
    }





















    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            Log.d(TAG, "API ${Build.VERSION.SDK_INT} < 31 — disabling Impeller (Skia renderer)")
            args.add("--enable-impeller=false")
        }
        return args
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Log.d(TAG, "configureFlutterEngine — registering VpnPlugin")
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(VpnPlugin())






        val wifiHistoryChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.leadaxe.lxbox/wifi_history",
        )
        WifiHistoryBridge.attach(wifiHistoryChannel)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.leadaxe.lxbox/utils")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url != null) {




                            val fallback = call.argument<String>("fallbackUrl")
                            if (openUrlOrFallback(url, fallback)) {
                                result.success(null)
                            } else {
                                result.error("NO_ACTIVITY", "No handler for $url", null)
                            }
                        } else {
                            result.error("INVALID_URL", "URL is null", null)
                        }
                    }
                    "networkCountry" -> {


                        result.success(networkCountryIso())
                    }
                    "installSource" -> {


                        result.success(installerPackageName())
                    }
                    "openAppSettings" -> {

                        val opened = openAppPermissions()
                        result.success(opened)
                    }
                    "hasRealFilePicker" -> {

                        result.success(hasRealFilePicker())
                    }
                    "filePickerAction" -> {



                        result.success(filePickerAction())
                    }
                    "pickFileViaGetContent" -> {


                        startGetContentPick(
                            call.argument<Boolean>("allowMultiple") ?: false,
                            result,
                        )
                    }
                    "hasCamera" -> {

                        result.success(hasCamera())
                    }
                    "canSaveToDownloads" -> {


                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    }
                    "saveToDownloads" -> {

                        val name = call.argument<String>("fileName")
                        val content = call.argument<String>("content")
                        if (name.isNullOrEmpty() || content == null) {
                            result.error("INVALID_ARGS", "fileName/content is null", null)
                        } else {
                            result.success(saveToDownloads(name, content))
                        }
                    }
                    "checkNotificationPermission" -> {


                        result.success(PermissionUtils.has(
                            this, "android.permission.POST_NOTIFICATIONS",
                            minSdk = 33,
                        ))
                    }
                    "requestNotificationPermission" -> {
                        if (pendingNotificationResult != null) {
                            result.error("PERMISSION_BUSY", "Permission request in progress", null)
                        } else if (Build.VERSION.SDK_INT >= 33) {
                            pendingNotificationResult = result
                            try {
                                requestPermissions(
                                    arrayOf("android.permission.POST_NOTIFICATIONS"),
                                    NOTIFICATION_PERMISSION_REQUEST,
                                )
                            } catch (e: Exception) {
                                pendingNotificationResult = null
                                result.error("PERMISSION_FAILED", e.message, null)
                            }
                        } else {
                            result.success(null)
                        }
                    }
                    "checkNearbyWifiPermission" -> {


                        result.success(PermissionUtils.has(
                            this, "android.permission.NEARBY_WIFI_DEVICES",
                            minSdk = 33,
                        ))
                    }
                    "checkBackgroundLocationPermission" -> {



                        val name = if (android.os.Build.VERSION.SDK_INT >= 29) {
                            "android.permission.ACCESS_BACKGROUND_LOCATION"
                        } else {
                            "android.permission.ACCESS_FINE_LOCATION"
                        }
                        result.success(PermissionUtils.has(this, name))
                    }
                    "requestNearbyWifiPermission" -> {


                        if (android.os.Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(
                                arrayOf("android.permission.NEARBY_WIFI_DEVICES"),
                                NEARBY_WIFI_PERMISSION_REQUEST,
                            )
                        }
                        result.success(null)
                    }
                    "getCurrentWifiInfo" -> {








                        result.success(getCurrentWifiInfoMap())
                    }
                    "openLocationSettings" -> {

                        result.success(openLocationSettings())
                    }
                    "setAutoRecordWifi" -> {




                        val enable = call.argument<Boolean>("enable") ?: false
                        if (enable) {
                            BoxApplication.wifiObserver.start()
                        } else {
                            BoxApplication.wifiObserver.stop()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)


        runCatching { BoxVpnService.clearStaleNotification(this) }
            .onFailure { Log.w("MainActivity", "clearStaleNotification failed: ${it.message}") }
        handleQuickAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleQuickAction(intent)
    }

    override fun onResume() {
        super.onResume()



        QuickShortcuts.retryPendingRelabel(applicationContext)
    }

    private fun handleQuickAction(intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return
        Log.d(TAG, "handleQuickAction action=$action currentStatus=${BoxVpnService.currentStatus.name}")



        finishAfterConsent = true


        intent.removeExtra(EXTRA_ACTION)

        when (action) {
            ACTION_CONNECT -> startVpnWithConsent()
            ACTION_DISCONNECT -> {
                BoxVpnService.stop(applicationContext)
                if (finishAfterConsent) finish()
            }
            ACTION_TOGGLE -> {
                val s = BoxVpnService.currentStatus
                if (s == VpnStatus.Started) {
                    BoxVpnService.stop(applicationContext)
                    if (finishAfterConsent) finish()
                } else if (s == VpnStatus.Stopped) {
                    startVpnWithConsent()
                } else {
                    Log.d(TAG, "toggle ignored in transient state ${s.name}")
                    if (finishAfterConsent) finish()
                }
            }
            else -> Log.w(TAG, "Unknown quick action: $action")
        }
    }

    private fun startVpnWithConsent() {

        if (!BootReceiver.hasTun(applicationContext)) {
            BoxVpnService.start(applicationContext)
            if (finishAfterConsent) finish()
            return
        }
        val prep = VpnService.prepare(applicationContext)
        if (prep == null) {
            BoxVpnService.start(applicationContext)
            if (finishAfterConsent) finish()
            return
        }


        if (finishAfterConsent) {

            Toast.makeText(
                applicationContext,
                L10n.str(applicationContext, R.string.qc_first_open),
                Toast.LENGTH_SHORT,
            ).show()
        }
        try {
            startActivityForResult(prep, VPN_REQUEST_CODE_QUICK)
        } catch (e: Exception) {
            Log.e(TAG, "VPN consent prepare failed: ${e.message}", e)
            if (finishAfterConsent) finish()
        }
    }





















    private fun hasRealFilePicker(): Boolean = filePickerAction() != null
















    private fun filePickerAction(): String? {
        for (action in listOf(Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT)) {
            val intent = Intent(action)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
            val candidates = packageManager.queryIntentActivities(intent, 0)
            if (candidates.any { !isStubHandler(it.activityInfo?.packageName) }) {
                return action
            }
        }
        return null
    }











    private fun startGetContentPick(allowMultiple: Boolean, result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICK_IN_PROGRESS", "Another pick is already running", null)
            return
        }
        val intent = Intent(Intent.ACTION_GET_CONTENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
        try {
            pendingPickResult = result
            startActivityForResult(intent, GET_CONTENT_REQUEST_CODE)
        } catch (e: Exception) {
            pendingPickResult = null
            Log.e(TAG, "startGetContentPick failed", e)
            result.error("PICK_FAILED", e.message, null)
        }
    }



    private fun readPickedUri(uri: Uri): Map<String, Any>? {
        return try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return null
            var name: String? = null
            runCatching {
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && c.moveToFirst()) name = c.getString(idx)
                }
            }
            mapOf(
                "name" to (name ?: uri.lastPathSegment ?: "config"),
                "bytes" to bytes,
            )
        } catch (e: Exception) {
            Log.e(TAG, "readPickedUri failed", e)
            null
        }
    }






    private fun hasCamera(): Boolean =
        packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_CAMERA_ANY)




    private fun isStubHandler(pkg: String?): Boolean =
        pkg != null && pkg.contains("frameworkpackagestubs")












    private fun networkCountryIso(): String? = try {
        val tm = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
        val net = tm?.networkCountryIso?.takeIf { it.length == 2 }
        val sim = tm?.simCountryIso?.takeIf { it.length == 2 }
        (net ?: sim)?.lowercase()
    } catch (e: Throwable) {
        Log.w("MainActivity", "networkCountryIso failed", e)
        null
    }

    private fun installerPackageName(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    } catch (e: Throwable) {

        Log.w("MainActivity", "installerPackageName failed", e)
        null
    }







    private fun openUrlOrFallback(url: String, fallbackUrl: String?): Boolean {
        if (tryOpenUrl(url)) return true
        if (fallbackUrl != null && tryOpenUrl(fallbackUrl)) return true
        return false
    }

    private fun tryOpenUrl(url: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        true
    } catch (e: Throwable) {
        Log.w("MainActivity", "openUrl failed for $url", e)
        false
    }















    private fun saveToDownloads(fileName: String, content: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/json")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values,
            ) ?: return null
            resolver.openOutputStream(uri)?.use { it.write(content.toByteArray()) }
                ?: run {
                    resolver.delete(uri, null, null)
                    return null
                }

            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null, null,
            )
            resolver.query(
                uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null,
            )?.use { c ->
                if (c.moveToFirst()) c.getString(0) else fileName
            } ?: fileName
        } catch (t: Throwable) {
            Log.w(TAG, "saveToDownloads failed: ${t.message}")
            null
        }
    }

    private fun openAppPermissions(): Boolean {

        val direct = Intent("android.intent.action.MANAGE_APP_PERMISSIONS")
            .putExtra("android.intent.extra.PACKAGE_NAME", packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (direct.resolveActivity(packageManager) != null) {
            runCatching { startActivity(direct); return true }
                .onFailure { Log.w(TAG, "MANAGE_APP_PERMISSIONS failed: ${it.message}") }
        }

        val singular = Intent("android.intent.action.MANAGE_PERMISSION_APPS")
            .putExtra("android.intent.extra.PACKAGE_NAME", packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (singular.resolveActivity(packageManager) != null) {
            runCatching { startActivity(singular); return true }
                .onFailure { Log.w(TAG, "MANAGE_PERMISSION_APPS failed: ${it.message}") }
        }

        val fallback = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { startActivity(fallback); return true }
            .onFailure { Log.e(TAG, "openAppSettings (all strategies) failed: ${it.message}") }
        return false
    }


    private fun openLocationSettings(): Boolean {
        val intent = Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { startActivity(intent); true }
            .onFailure { Log.w(TAG, "openLocationSettings failed: ${it.message}") }
            .getOrDefault(false)
    }




    private fun getCurrentWifiInfoMap(): Map<String, String> {
        return when (val r = WifiInfoReader.read(this)) {
            is WifiInfoReader.Result.Success ->
                mapOf("ssid" to r.ssid, "bssid" to r.bssid)
            is WifiInfoReader.Result.PermissionMissing -> {



                val code = if (r.missing.firstOrNull() == WifiInfoReader.PERM_FINE) {
                    "fine_location_missing"
                } else {
                    "permission_missing"
                }
                mapOf("error" to code, "missing" to r.missing.joinToString(","))
            }
            is WifiInfoReader.Result.LocationDisabled ->
                mapOf("error" to "location_disabled")
            is WifiInfoReader.Result.NoWifi ->
                mapOf("error" to "no_wifi")
            is WifiInfoReader.Result.UnknownSsid ->
                mapOf("error" to "unknown_ssid")
            is WifiInfoReader.Result.RuntimeError ->
                mapOf("error" to "runtime_error")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == GET_CONTENT_REQUEST_CODE) {


            val pending = pendingPickResult ?: return
            pendingPickResult = null
            if (resultCode != Activity.RESULT_OK || data == null) {

                pending.success(null)
                return
            }



            val uris = mutableListOf<Uri>()
            val clip = data.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i).uri?.let { uris.add(it) }
                }
            } else {
                data.data?.let { uris.add(it) }
            }
            if (uris.isEmpty()) {
                pending.success(null)
                return
            }
            val picked = uris.mapNotNull { readPickedUri(it) }
            if (picked.isEmpty()) {
                pending.error("PICK_READ_FAILED", "Cannot read the selected file", null)
            } else {
                pending.success(picked)
            }
            return
        }
        if (requestCode != VPN_REQUEST_CODE_QUICK) return
        if (resultCode == Activity.RESULT_OK) {
            BoxVpnService.start(applicationContext)
            if (finishAfterConsent) finish()
        } else {

            Toast.makeText(
                applicationContext,
                L10n.str(applicationContext, R.string.qc_consent_denied),
                Toast.LENGTH_SHORT,
            ).show()
            if (finishAfterConsent) finish()
        }
    }
}
