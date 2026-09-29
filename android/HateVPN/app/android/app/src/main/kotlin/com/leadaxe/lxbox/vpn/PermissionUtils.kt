package com.leadaxe.lxbox.vpn

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build










object PermissionUtils {






    fun has(ctx: Context, name: String, minSdk: Int = 0): Boolean {
        if (Build.VERSION.SDK_INT < minSdk) return true
        return ctx.checkSelfPermission(name) ==
            PackageManager.PERMISSION_GRANTED
    }
}
