package com.mystyle.purelive.live

import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale

class NativeLiveDiagnostics(
    private val enabled: Boolean,
    private val handler: Handler,
    private val onChanged: () -> Unit,
) {
    private val items = ArrayDeque<String>()
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)

    val size: Int
        get() = items.size

    val lastHash: Int?
        get() = items.peekLast()?.hashCode()

    fun append(tag: String, message: String) {
        if (!enabled) return
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { append(tag, message) }
            return
        }
        val line = "${timeFormat.format(Date())} [$tag] $message"
        if (items.size >= MAX_ITEMS) {
            items.removeFirst()
        }
        items.addLast(line)
        onChanged()
    }

    fun panelItems(summary: String): List<String> {
        return buildList {
            add("复制最近诊断信息（按确定）")
            add(summary)
            addAll(items.toList().asReversed())
        }
    }

    companion object {
        private const val MAX_ITEMS = 120
    }
}
