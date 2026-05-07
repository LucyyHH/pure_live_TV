package com.mystyle.purelive.live

import android.content.res.Resources
import kotlin.math.roundToInt

class NativeLiveDanmakuController(
    private val danmakuView: DanmakuView,
    private val resources: Resources,
) {
    fun applyConfig(state: DanmakuState) {
        val density = resources.displayMetrics.density
        danmakuView.setDanmakuEnabled(!state.hidden)
        danmakuView.fontSize = (state.fontSize * density).toFloat()
        danmakuView.setDuration(state.speed.roundToInt())
        danmakuView.setOpacity(state.opacity.toFloat())
        danmakuView.setAreaRatio(state.area.toFloat())
        danmakuView.setVerticalPadding(
            (state.topDistance * density).toFloat(),
            (state.bottomDistance * density).toFloat()
        )
        danmakuView.setStrokeWidth((2f + state.stroke.toFloat()).coerceAtLeast(1f))
    }

    fun stepSize(current: Double, delta: Int): Double = stepValue(SIZE_OPTIONS, current, delta)

    fun stepSpeed(current: Double, delta: Int): Double = stepValue(SPEED_OPTIONS, current, delta)

    fun stepArea(current: Double, delta: Int): Double = stepValue(AREA_OPTIONS, current, delta)

    fun stepDistance(current: Double, delta: Int): Double = stepValue(DISTANCE_OPTIONS, current, delta)

    fun stepStroke(current: Double, delta: Int): Double = stepValue(STROKE_OPTIONS, current, delta)

    private fun stepValue(options: List<Double>, current: Double, delta: Int): Double {
        if (options.isEmpty()) return current
        val index = options.indexOfFirst { it == current }.let { if (it >= 0) it else 0 }
        return options[(index + delta + options.size) % options.size]
    }

    companion object {
        private val SIZE_OPTIONS = listOf(10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 28.0, 32.0, 40.0, 48.0, 64.0, 72.0)
        private val SPEED_OPTIONS = listOf(4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0, 30.0, 32.0)
        private val AREA_OPTIONS = listOf(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0)
        private val DISTANCE_OPTIONS = listOf(0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 50.0, 70.0, 100.0)
        private val STROKE_OPTIONS = listOf(0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0)
    }
}
