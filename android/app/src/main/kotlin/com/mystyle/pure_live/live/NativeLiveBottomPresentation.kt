package com.mystyle.purelive.live

import android.graphics.Typeface

fun bottomButtonHasLabel(action: BottomAction): Boolean = when (action) {
    BottomAction.FAVORITE,
    BottomAction.QUALITY,
    BottomAction.LINE,
    BottomAction.BOX_FIT,
    BottomAction.DIAGNOSTICS -> true
    BottomAction.REFRESH,
    BottomAction.PLAY_PAUSE,
    BottomAction.DANMAKU,
    BottomAction.SETTINGS -> false
}

fun buildBottomButtonPresentation(
    action: BottomAction,
    isPlaying: Boolean,
    isFavoriteCurrent: Boolean,
    danmakuHidden: Boolean,
    currentQualityName: String,
    lineIndex: Int,
    fitLabels: List<String>,
    fitIndex: Int,
    materialIconTypeface: Typeface?,
    customIconTypeface: Typeface?,
): BottomButtonPresentation = when (action) {
    BottomAction.REFRESH -> materialBottomIcon(materialIconTypeface, 0xF00E9, "R")
    BottomAction.PLAY_PAUSE -> {
        if (isPlaying) materialBottomIcon(materialIconTypeface, 0xF0056, "||")
        else materialBottomIcon(materialIconTypeface, 0xF00A0, ">")
    }
    BottomAction.FAVORITE -> {
        val icon = if (isFavoriteCurrent) {
            materialBottomIcon(materialIconTypeface, 0xF539, "+")
        } else {
            materialBottomIcon(materialIconTypeface, 0xF0FE, "-")
        }
        icon.copy(label = if (isFavoriteCurrent) "已关注" else "未关注")
    }
    BottomAction.DANMAKU -> {
        if (danmakuHidden) customBottomIcon(customIconTypeface, 0xE800, "弹")
        else customBottomIcon(customIconTypeface, 0xE801, "弹")
    }
    BottomAction.SETTINGS -> customBottomIcon(customIconTypeface, 0xE802, "设")
    BottomAction.QUALITY -> materialBottomIcon(materialIconTypeface, 0xF40B, "Q").copy(
        label = currentQualityName.ifBlank { "清晰度" }
    )
    BottomAction.LINE -> materialBottomIcon(materialIconTypeface, 0xF0304, "=").copy(
        label = "线路${lineIndex + 1}"
    )
    BottomAction.BOX_FIT -> materialBottomIcon(materialIconTypeface, 0xF489, "[]").copy(
        label = fitLabels.getOrElse(fitIndex) { "等比适配" }
    )
    BottomAction.DIAGNOSTICS -> BottomButtonPresentation(
        icon = "诊",
        iconTypeface = null,
        label = "播放器诊断"
    )
}

private fun materialBottomIcon(
    typeface: Typeface?,
    codePoint: Int,
    fallback: String,
): BottomButtonPresentation {
    return BottomButtonPresentation(
        icon = if (typeface != null) nativeLiveIconString(codePoint) else fallback,
        iconTypeface = typeface
    )
}

private fun customBottomIcon(
    typeface: Typeface?,
    codePoint: Int,
    fallback: String,
): BottomButtonPresentation {
    return BottomButtonPresentation(
        icon = if (typeface != null) nativeLiveIconString(codePoint) else fallback,
        iconTypeface = typeface
    )
}
