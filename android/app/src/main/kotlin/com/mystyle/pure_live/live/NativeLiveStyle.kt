package com.mystyle.purelive.live

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.View
import kotlin.math.roundToInt

internal fun Context.nativeLiveDp(value: Int): Int {
    return (value * resources.displayMetrics.density).roundToInt()
}

internal fun Context.loadNativeLiveTypeface(assetPath: String): Typeface? {
    return kotlin.runCatching { Typeface.createFromAsset(assets, assetPath) }.getOrNull()
}

internal fun nativeLiveIconString(codePoint: Int): String {
    return String(Character.toChars(codePoint))
}

internal fun Double.formatNativeLiveValue(): String {
    val intValue = toInt()
    return if (this == intValue.toDouble()) intValue.toString() else String.format("%.1f", this)
}

internal fun applyNativeLiveSelectableSurface(
    view: View,
    selected: Boolean,
    focusGlowColor: Int,
    cornerRadiusPx: Int,
    selectedStrokePx: Int,
    elevationPx: Int,
    selectedTranslationYPx: Int,
    idleScale: Float,
    idleColor: Int,
) {
    view.background = GradientDrawable().apply {
        cornerRadius = cornerRadiusPx.toFloat()
        setColor(if (selected) Color.WHITE else idleColor)
        setStroke(if (selected) selectedStrokePx else 0, if (selected) focusGlowColor else Color.TRANSPARENT)
    }
    view.scaleX = if (selected) 1f else idleScale
    view.scaleY = if (selected) 1f else idleScale
    view.alpha = if (selected) 1f else 0.96f
    view.elevation = if (selected) elevationPx.toFloat() else 0f
    view.translationY = if (selected) -selectedTranslationYPx.toFloat() else 0f
}
