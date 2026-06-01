package com.mystyle.purelive.live

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.roundToInt

class DanmakuView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    data class Item(
        val text: String,
        var x: Float,
        val y: Float,
        val color: Int,
        val width: Float,
    )

    private val items = ArrayList<Item>(128)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFakeBoldText = true
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f
        color = Color.BLACK
        isFakeBoldText = true
    }

    private var running = false
    private var lastFrameNs = 0L

    var fontSize = 28f
        set(value) {
            field = value
            textPaint.textSize = value
            strokePaint.textSize = value
            trackHeight = value * 1.6f
        }

    private var trackHeight = fontSize * 1.6f
    private var durationMs = 8000f
    private var alphaValue = 255
    private var areaRatio = 1f
    private var topPaddingPx = 0f
    private var bottomPaddingPx = 0f
    private var danmakuEnabled = true

    private val trackTail = HashMap<Int, Item>()

    init {
        textPaint.textSize = fontSize
        strokePaint.textSize = fontSize
    }

    fun setDuration(seconds: Int) {
        durationMs = seconds * 1000f
    }

    fun setDanmakuEnabled(enabled: Boolean) {
        danmakuEnabled = enabled
        visibility = if (enabled) VISIBLE else GONE
        if (!enabled) {
            clear()
        }
    }

    fun setOpacity(value: Float) {
        alphaValue = (value.coerceIn(0f, 1f) * 255f).roundToInt().coerceIn(0, 255)
        invalidate()
    }

    fun setStrokeWidth(value: Float) {
        strokePaint.strokeWidth = value.coerceAtLeast(0f)
        invalidate()
    }

    fun setAreaRatio(value: Float) {
        areaRatio = value.coerceIn(0.1f, 1f)
        invalidate()
    }

    fun setVerticalPadding(top: Float, bottom: Float) {
        topPaddingPx = top.coerceAtLeast(0f)
        bottomPaddingPx = bottom.coerceAtLeast(0f)
        invalidate()
    }

    fun addDanmaku(text: String, color: Int, retries: Int = 5) {
        if (!danmakuEnabled) return
        val w = width.toFloat()
        if (w <= 0f) {
            if (retries > 0 && isAttachedToWindow) {
                postDelayed({ addDanmaku(text, color, retries - 1) }, 200)
            }
            return
        }
        val tw = textPaint.measureText(text)
        val track = findTrack(tw, w)
        val y = topPaddingPx + track * trackHeight + trackHeight
        val item = Item(text, w, y, color or 0xFF000000.toInt(), tw)
        items.add(item)
        trackTail[track] = item
        if (!running) {
            running = true
            lastFrameNs = System.nanoTime()
            postInvalidateOnAnimation()
        }
    }

    fun clear() {
        items.clear()
        trackTail.clear()
        running = false
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        clear()
    }

    private fun findTrack(newWidth: Float, screenWidth: Float): Int {
        val availableHeight = (height.toFloat() - topPaddingPx - bottomPaddingPx).coerceAtLeast(trackHeight)
        val maxTracks = (((availableHeight / trackHeight) * areaRatio) - 1f).toInt().coerceAtLeast(1)
        for (i in 0 until maxTracks) {
            val last = trackTail[i] ?: return i
            if (last.x + last.width < screenWidth * 0.7f) return i
        }
        return (System.nanoTime() % maxTracks).toInt().coerceIn(0, maxTracks - 1)
    }

    override fun onDraw(canvas: Canvas) {
        if (!running || !danmakuEnabled) return
        val now = System.nanoTime()
        val dtMs = (now - lastFrameNs) / 1_000_000f
        lastFrameNs = now
        val screenW = width.toFloat()

        val it = items.iterator()
        while (it.hasNext()) {
            val item = it.next()
            val speed = (screenW + item.width) / durationMs
            item.x -= speed * dtMs
            if (item.x + item.width < 0) {
                it.remove()
                continue
            }
            strokePaint.textSize = fontSize
            strokePaint.alpha = alphaValue
            canvas.drawText(item.text, item.x, item.y, strokePaint)
            textPaint.textSize = fontSize
            textPaint.color = item.color
            textPaint.alpha = alphaValue
            canvas.drawText(item.text, item.x, item.y, textPaint)
        }
        if (items.isEmpty()) {
            running = false
            trackTail.clear()
            return
        }
        postInvalidateOnAnimation()
    }
}
