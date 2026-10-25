package com.goldenfalcons.sailinggps

import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.TextWatcher
import android.widget.*
import androidx.appcompat.app.AlertDialog

object WaypointAppearanceDialog {
    fun show(context: Context, mark: String, color: String, save: (String, String) -> Unit) {
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 8, 24, 8) }
        val preview = TextView(context).apply { textSize = 36f; gravity = android.view.Gravity.CENTER }
        column.addView(preview)
        val input = EditText(context).apply { setText(mark); hint = "マーク・絵文字・文字"; setSingleLine(true); filters = arrayOf(android.text.InputFilter.LengthFilter(8)) }
        column.addView(input)
        val grid = GridLayout(context).apply { columnCount = 4 }
        for (symbol in MarineMarks.names + listOf("●", "▲", "■", "◆", "★", "⚑", "⚓", "⛵", "🏠", "☀", "🐟", "!")) {
            grid.addView(Button(context).apply {
                text = symbol; textSize = if (symbol in MarineMarks.names) 13f else 20f
                if (symbol in MarineMarks.names) {
                    val side = (28 * resources.displayMetrics.density).toInt()
                    val image = android.graphics.Bitmap.createBitmap(side, side, android.graphics.Bitmap.Config.ARGB_8888)
                    MarineMarks.draw(android.graphics.Canvas(image), symbol, side/2f, side/2f, side.toFloat(), Color.BLACK)
                    setCompoundDrawablesWithIntrinsicBounds(null, android.graphics.drawable.BitmapDrawable(resources, image), null, null)
                }
                layoutParams = GridLayout.LayoutParams().apply { width = 0; columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f) }
                setOnClickListener { input.setText(symbol) }
            })
        }
        column.addView(grid)
        val hex = EditText(context).apply { hint = "色 #RRGGBB"; setSingleLine(true); setText(color); contentDescription = "自由な色 HEX" }
        column.addView(hex)
        var selected = runCatching { Color.parseColor(color) }.getOrDefault(Color.rgb(255, 170, 0))
        var syncing = false
        val sliders = (0..2).map { index ->
            val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
            row.addView(TextView(context).apply { text = listOf("R", "G", "B")[index]; setPadding(4, 10, 8, 0) })
            val slider = SeekBar(context).apply { max = 255; contentDescription = listOf("赤", "緑", "青")[index] }
            row.addView(slider, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)); column.addView(row)
            slider
        }
        fun redraw() { preview.text = input.text.toString().ifBlank { "●" }; preview.setTextColor(selected) }
        fun syncSliders() { sliders[0].progress=Color.red(selected);sliders[1].progress=Color.green(selected);sliders[2].progress=Color.blue(selected) }
        fun updateSliders() {
            sliders[0].progress = Color.red(selected); sliders[1].progress = Color.green(selected); sliders[2].progress = Color.blue(selected)
        }
        fun watch(action: () -> Unit) = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) { action() }
        }
        val palette=GridLayout(context).apply{columnCount=4}
        WaypointFolderColors.palette.forEach{(name,hexColor)->palette.addView(Button(context).apply{text=name;contentDescription="$name を選択";setOnClickListener{selected=Color.parseColor(hexColor);hex.setText(hexColor);syncSliders();redraw()}})}
        column.addView(TextView(context).apply{text="色を選択";setPadding(4,12,4,2)})
        column.addView(palette)
        updateSliders(); redraw()
        sliders.forEach { slider -> slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, value: Int, fromUser: Boolean) {
                if (!fromUser || syncing) return
                selected = Color.rgb(sliders[0].progress, sliders[1].progress, sliders[2].progress)
                syncing = true; hex.setText(String.format("#%06X", selected and 0xFFFFFF)); syncing = false; redraw()
            }
            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) {}
        }) }
        input.addTextChangedListener(watch { redraw() })
        hex.addTextChangedListener(watch {
            if (!syncing) {
                val value = hex.text.toString()
                if (value.matches(Regex("#[0-9a-fA-F]{6}"))) {
                    selected = Color.parseColor(value); syncing = true; updateSliders(); syncing = false; hex.error = null; redraw()
                }
            }
        })
        val dialog = AlertDialog.Builder(context).setTitle("ウェイポイントのマーク・色")
            .setView(ScrollView(context).apply { addView(column) }).setNegativeButton("キャンセル", null).setPositiveButton("保存", null).create()
        dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            if (!hex.text.toString().matches(Regex("#[0-9a-fA-F]{6}"))) { hex.error = "#RRGGBBで入力してください"; return@setOnClickListener }
            save(input.text.toString().trim().ifEmpty { "●" }, String.format("#%06X", selected and 0xFFFFFF)); dialog.dismiss()
        } }
        dialog.show()
        if (BuildConfig.DEBUG) dialog.window?.decorView?.viewTreeObserver?.addOnGlobalLayoutListener {
            val button = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
            val xy = IntArray(2); button.getLocationOnScreen(xy)
            android.util.Log.d("SailingUiBounds", "APPEARANCE save=${xy[0]},${xy[1]},${xy[0] + button.width},${xy[1] + button.height}")
        }
    }
}

