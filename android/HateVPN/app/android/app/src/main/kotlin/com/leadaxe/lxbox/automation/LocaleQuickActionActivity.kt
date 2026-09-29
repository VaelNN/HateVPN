package com.leadaxe.lxbox.automation

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.leadaxe.lxbox.R
import com.leadaxe.lxbox.vpn.L10n










class LocaleQuickActionActivity : Activity() {

    companion object {


        private val ALIAS_CMD = mapOf(
            "com.leadaxe.lxbox.automation.LocaleStartAlias" to
                ("start-vpn" to R.string.automation_blurb_start),
            "com.leadaxe.lxbox.automation.LocaleStopAlias" to
                ("stop-vpn" to R.string.automation_blurb_stop),
            "com.leadaxe.lxbox.automation.LocaleToggleAlias" to
                ("toggle-vpn" to R.string.automation_blurb_toggle),
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val alias = intent.component?.className
        val entry = ALIAS_CMD[alias]
            ?: ("toggle-vpn" to R.string.automation_blurb_toggle)
        val (cmd, blurbRes) = entry
        val blurb = L10n.str(this, blurbRes)

        val data = Intent().apply {
            putExtra(
                LocaleApi.EXTRA_BUNDLE,
                LocaleApi.buildSettingBundle(cmd, emptyMap()),
            )
            putExtra(LocaleApi.EXTRA_STRING_BLURB, blurb)
        }
        setResult(RESULT_OK, data)
        finish()
    }
}
