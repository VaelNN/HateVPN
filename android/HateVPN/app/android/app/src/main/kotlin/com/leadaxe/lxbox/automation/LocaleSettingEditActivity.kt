package com.leadaxe.lxbox.automation

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import com.leadaxe.lxbox.R
import com.leadaxe.lxbox.vpn.L10n












class LocaleSettingEditActivity : Activity() {



    private val commands = listOf(
        Cmd("switch-node", R.string.automation_cmd_switch_node, "tag", Source.NODES),
        Cmd("set-group", R.string.automation_cmd_set_group, "group", Source.GROUPS),
        Cmd("urltest-group", R.string.automation_cmd_urltest_group, "group", Source.GROUPS),
        Cmd("refresh-subs", R.string.automation_cmd_refresh_subs, null, Source.NONE),
        Cmd("rebuild-config", R.string.automation_cmd_rebuild_config, null, Source.NONE),
        Cmd("reset-network", R.string.automation_cmd_reset_network, null, Source.NONE),
    )

    private enum class Source { NONE, NODES, GROUPS }
    private data class Cmd(
        val cmd: String, val labelRes: Int, val extra: String?, val source: Source,
    )

    private lateinit var radioGroup: RadioGroup
    private lateinit var extraLabel: TextView
    private lateinit var extraSpinner: Spinner
    private lateinit var extraInput: EditText

    private var nodes: List<String> = emptyList()
    private var groups: List<String> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = L10n.str(this, R.string.app_name)
        nodes = LocaleApi.cachedNodes(this)
        groups = LocaleApi.cachedGroups(this)

        val pad = (16 * resources.displayMetrics.density).toInt()
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }

        content.addView(TextView(this).apply {
            text = L10n.str(this@LocaleSettingEditActivity,
                R.string.automation_command_prompt)
            setPadding(0, 0, 0, pad / 2)
        })

        radioGroup = RadioGroup(this)
        commands.forEachIndexed { idx, c ->
            radioGroup.addView(RadioButton(this).apply {
                id = idx
                text = L10n.str(this@LocaleSettingEditActivity, c.labelRes)
                setPadding(0, pad / 3, 0, pad / 3)
            })
        }
        radioGroup.setOnCheckedChangeListener { _, checkedId ->
            updateExtra(checkedId, null)
        }
        content.addView(radioGroup)

        extraLabel = TextView(this).apply {
            setPadding(0, pad, 0, 0)
            visibility = View.GONE
        }
        content.addView(extraLabel)
        extraSpinner = Spinner(this).apply { visibility = View.GONE }
        content.addView(extraSpinner)
        extraInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT
            visibility = View.GONE
        }
        content.addView(extraInput)

        val save = Button(this).apply {
            text = L10n.str(this@LocaleSettingEditActivity, R.string.automation_save)
            gravity = Gravity.CENTER
            setOnClickListener { onSave() }
        }
        content.addView(save, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = pad })

        if (!prefill()) radioGroup.check(0)

        setContentView(ScrollView(this).apply { addView(content) })
    }



    private fun updateExtra(checkedId: Int, preset: String?) {
        val c = commands.getOrNull(checkedId)
        val extra = c?.extra
        if (c == null || extra == null) {
            extraLabel.visibility = View.GONE
            extraSpinner.visibility = View.GONE
            extraInput.visibility = View.GONE
            return
        }
        val options = when (c.source) {
            Source.NODES -> nodes
            Source.GROUPS -> groups
            Source.NONE -> emptyList()
        }

        extraLabel.text = L10n.str(this, R.string.automation_value_label, extra)
        extraLabel.visibility = View.VISIBLE
        if (options.isNotEmpty()) {

            extraSpinner.adapter = ArrayAdapter(
                this, android.R.layout.simple_spinner_dropdown_item, options,
            )
            preset?.let {
                val i = options.indexOf(it)
                if (i >= 0) extraSpinner.setSelection(i)
            }
            extraSpinner.visibility = View.VISIBLE
            extraInput.visibility = View.GONE
        } else {

            extraInput.setText(preset ?: "")
            extraInput.visibility = View.VISIBLE
            extraSpinner.visibility = View.GONE
        }
    }


    private fun currentExtraValue(): String =
        if (extraSpinner.visibility == View.VISIBLE) {
            extraSpinner.selectedItem?.toString() ?: ""
        } else {
            extraInput.text.toString().trim()
        }

    private fun prefill(): Boolean {
        val parsed = LocaleApi.parseSetting(
            intent.getBundleExtra(LocaleApi.EXTRA_BUNDLE),
        ) ?: return false
        val (cmd, args) = parsed
        val idx = commands.indexOfFirst { it.cmd == cmd }
        if (idx < 0) return false
        radioGroup.check(idx)
        val extraName = commands[idx].extra
        updateExtra(idx, if (extraName != null) args[extraName]?.toString() else null)
        return true
    }

    private fun onSave() {
        val checkedId = radioGroup.checkedRadioButtonId
        val idx = if (checkedId in commands.indices) checkedId else 0
        val c = commands[idx]
        val args = mutableMapOf<String, Any?>()

        val label = L10n.str(this, c.labelRes)
        var blurb = label
        if (c.extra != null) {
            val value = currentExtraValue()
            args[c.extra] = value
            if (value.isNotEmpty()) blurb = "$label → $value"
        }
        val data = Intent().apply {
            putExtra(LocaleApi.EXTRA_BUNDLE, LocaleApi.buildSettingBundle(c.cmd, args))
            putExtra(LocaleApi.EXTRA_STRING_BLURB, blurb)
        }
        setResult(RESULT_OK, data)
        finish()
    }
}
