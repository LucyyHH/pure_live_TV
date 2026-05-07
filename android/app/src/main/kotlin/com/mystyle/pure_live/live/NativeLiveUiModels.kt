package com.mystyle.purelive.live

import android.graphics.Typeface
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.roundToInt

enum class NativePanel { NONE, SETTINGS, QUALITY, LINES, PLAYLIST, DIAGNOSTICS }

enum class BottomAction {
    FAVORITE, REFRESH, PLAY_PAUSE, DANMAKU, SETTINGS, QUALITY, LINE, BOX_FIT, DIAGNOSTICS
}

data class PlaylistItem(
    val title: String,
    val nick: String,
    val platform: String,
    var isFavorite: Boolean,
)

data class DanmakuState(
    var hidden: Boolean = false,
    var fontSize: Double = 16.0,
    var speed: Double = 8.0,
    var area: Double = 1.0,
    var topDistance: Double = 0.0,
    var bottomDistance: Double = 0.0,
    var opacity: Double = 1.0,
    var stroke: Double = 4.0,
)

data class BottomButtonViewHolder(
    val root: LinearLayout,
    val iconView: TextView,
    val labelView: TextView?,
)

data class BottomButtonPresentation(
    val icon: String,
    val iconTypeface: Typeface?,
    val label: String? = null,
)

data class VideoFitSize(val width: Int, val height: Int)

data class NativeRenderConfig(
    val viewType: Int,
    val preferSoftwareDecoder: Boolean,
    val compatMode: Boolean,
)

data class NativePlaybackPayload(
    val url: String,
    val headers: Map<String, String>,
    val title: String,
    val nick: String,
    val channelName: String,
    val qualities: List<String>,
    val qualityIndex: Int,
    val lines: List<String>,
    val lineIndex: Int,
    val currentQualityName: String,
    val playlist: List<PlaylistItem>,
    val currentPlaylistIndex: Int,
    val isFavoriteCurrent: Boolean,
    val fitLabels: List<String>,
    val fitIndex: Int,
    val danmakuState: DanmakuState,
    val renderConfig: NativeRenderConfig,
    val themeColorValue: Int,
)

fun buildBottomActions(diagnosticsEnabled: Boolean): List<BottomAction> = buildList {
    add(BottomAction.FAVORITE)
    add(BottomAction.REFRESH)
    add(BottomAction.PLAY_PAUSE)
    add(BottomAction.DANMAKU)
    add(BottomAction.SETTINGS)
    add(BottomAction.QUALITY)
    add(BottomAction.LINE)
    add(BottomAction.BOX_FIT)
    if (diagnosticsEnabled) add(BottomAction.DIAGNOSTICS)
}

fun defaultBottomActionIndex(actions: List<BottomAction>): Int {
    val refreshIndex = actions.indexOf(BottomAction.REFRESH)
    return if (refreshIndex >= 0) refreshIndex else 0
}

fun panelTitle(panel: NativePanel): String = when (panel) {
    NativePanel.SETTINGS -> "弹幕设置"
    NativePanel.QUALITY -> "清晰度设置"
    NativePanel.LINES -> "线路切换"
    NativePanel.PLAYLIST -> "播放列表"
    NativePanel.DIAGNOSTICS -> "播放器诊断"
    NativePanel.NONE -> ""
}

fun panelItemCount(
    panel: NativePanel,
    qualities: List<String>,
    lines: List<String>,
    lineIndex: Int,
    playlist: List<PlaylistItem>,
    diagnosticsCount: Int,
): Int = when (panel) {
    NativePanel.SETTINGS -> 8
    NativePanel.QUALITY -> qualities.size
    NativePanel.LINES -> max(lines.size, lineIndex + 1)
    NativePanel.PLAYLIST -> playlist.size
    NativePanel.DIAGNOSTICS -> diagnosticsCount
    NativePanel.NONE -> 0
}

fun buildPanelFingerprint(
    panel: NativePanel,
    danmakuState: DanmakuState,
    qualities: List<String>,
    lines: List<String>,
    lineIndex: Int,
    playlist: List<PlaylistItem>,
    diagnosticsSize: Int,
    lastDiagnosticHash: Int?,
    currentVideoDecoderName: String,
    totalDroppedVideoFrames: Int,
): String = when (panel) {
    NativePanel.SETTINGS -> "S:${danmakuState.hashCode()}"
    NativePanel.QUALITY -> "Q:${qualities.hashCode()}"
    NativePanel.LINES -> "L:${lines.hashCode()}:$lineIndex"
    NativePanel.PLAYLIST -> "P:${playlist.hashCode()}"
    NativePanel.DIAGNOSTICS -> {
        "D:$diagnosticsSize:$lastDiagnosticHash:${currentVideoDecoderName.hashCode()}:$totalDroppedVideoFrames"
    }
    NativePanel.NONE -> ""
}

fun playlistDisplayName(item: PlaylistItem): String {
    return if (item.platform == "iptv") item.title else item.nick.ifBlank { item.title }
}

fun activeOutputName(nativeRenderViewType: Int): String {
    return if (nativeRenderViewType == 1) "TextureView" else "SurfaceView"
}

fun parseNativePlaybackPayload(
    obj: JSONObject,
    currentUrl: String,
    currentHeaders: Map<String, String>,
    currentTitle: String,
    currentNick: String,
    currentChannelName: String,
    qualities: List<String>,
    qualityIndex: Int,
    lines: List<String>,
    lineIndex: Int,
    currentQualityName: String,
    playlist: List<PlaylistItem>,
    currentPlaylistIndex: Int,
    isFavoriteCurrent: Boolean,
    fitLabels: List<String>,
    fitIndex: Int,
    danmakuState: DanmakuState,
    nativeRenderViewType: Int,
    nativePreferSoftwareDecoder: Boolean,
    nativeCompatMode: Boolean,
    focusGlowColor: Int,
): NativePlaybackPayload {
    return NativePlaybackPayload(
        url = obj.optString("url", currentUrl),
        headers = obj.optJSONObject("headers")?.toStringMap() ?: currentHeaders,
        title = obj.optString("roomTitle", obj.optString("title", currentTitle)),
        nick = obj.optString("roomNick", currentNick),
        channelName = obj.optString("channelName", currentChannelName),
        qualities = obj.optJSONArray("qualities")?.toStringList() ?: qualities,
        qualityIndex = obj.optInt("qualityIndex", qualityIndex),
        lines = obj.optJSONArray("lines")?.toStringList() ?: lines,
        lineIndex = obj.optInt("lineIndex", lineIndex),
        currentQualityName = obj.optString("currentQualityName", currentQualityName),
        playlist = obj.optJSONArray("playlist")?.toPlaylistItems() ?: playlist,
        currentPlaylistIndex = obj.optInt("currentPlaylistIndex", currentPlaylistIndex),
        isFavoriteCurrent = obj.optBoolean("isFavoriteCurrent", isFavoriteCurrent),
        fitLabels = obj.optJSONArray("fitLabels")?.toStringList() ?: fitLabels,
        fitIndex = obj.optInt("fitIndex", fitIndex),
        danmakuState = obj.optJSONObject("danmaku")?.toDanmakuState(danmakuState) ?: danmakuState,
        renderConfig = NativeRenderConfig(
            viewType = obj.optInt("nativeRenderViewType", nativeRenderViewType).coerceIn(0, 1),
            preferSoftwareDecoder = obj.optBoolean(
                "nativePreferSoftwareDecoder",
                nativePreferSoftwareDecoder,
            ),
            compatMode = obj.optBoolean("nativeCompatMode", nativeCompatMode),
        ),
        themeColorValue = obj.optInt("themeColorValue", focusGlowColor),
    )
}

private fun org.json.JSONArray.toStringList(): List<String> {
    return List(length()) { optString(it, "") }
}

private fun org.json.JSONArray.toPlaylistItems(): List<PlaylistItem> {
    return List(length()) { index ->
        val item = optJSONObject(index) ?: JSONObject()
        PlaylistItem(
            title = item.optString("title", ""),
            nick = item.optString("nick", ""),
            platform = item.optString("platform", ""),
            isFavorite = item.optBoolean("isFavorite", false),
        )
    }
}

private fun JSONObject.toStringMap(): Map<String, String> {
    val map = mutableMapOf<String, String>()
    keys().forEach { key -> map[key] = optString(key, "") }
    return map
}

private fun JSONObject.toDanmakuState(current: DanmakuState): DanmakuState {
    return DanmakuState(
        hidden = optBoolean("hidden", current.hidden),
        fontSize = optDouble("fontSize", current.fontSize),
        speed = optDouble("speed", current.speed),
        area = optDouble("area", current.area),
        topDistance = optDouble("topDistance", current.topDistance),
        bottomDistance = optDouble("bottomDistance", current.bottomDistance),
        opacity = optDouble("opacity", current.opacity),
        stroke = optDouble("stroke", current.stroke),
    )
}

fun calculateVideoFitSize(
    containerWidth: Int,
    containerHeight: Int,
    videoAspectRatio: Float,
    videoContentWidth: Int,
    videoContentHeight: Int,
    fitIndex: Int,
): VideoFitSize {
    val aspect = videoAspectRatio.coerceAtLeast(0.1f)
    val containerAspect = containerWidth.toFloat() / containerHeight.toFloat()
    val naturalWidth = videoContentWidth.coerceAtLeast(1)
    val naturalHeight = videoContentHeight.coerceAtLeast(1)
    var targetWidth = containerWidth
    var targetHeight = containerHeight

    when (fitIndex) {
        0 -> {
            if (containerAspect > aspect) {
                targetHeight = containerHeight
                targetWidth = (containerHeight * aspect).roundToInt()
            } else {
                targetWidth = containerWidth
                targetHeight = (containerWidth / aspect).roundToInt()
            }
        }
        1 -> {
            targetWidth = containerWidth
            targetHeight = containerHeight
        }
        2 -> {
            if (containerAspect > aspect) {
                targetWidth = containerWidth
                targetHeight = (containerWidth / aspect).roundToInt()
            } else {
                targetHeight = containerHeight
                targetWidth = (containerHeight * aspect).roundToInt()
            }
        }
        3 -> {
            targetWidth = containerWidth
            targetHeight = (containerWidth / aspect).roundToInt()
        }
        4 -> {
            targetHeight = containerHeight
            targetWidth = (containerHeight * aspect).roundToInt()
        }
        5 -> {
            if (containerAspect > aspect) {
                targetHeight = containerHeight.coerceAtMost(naturalHeight)
                targetWidth = (targetHeight * aspect).roundToInt()
            } else {
                targetWidth = containerWidth.coerceAtMost(naturalWidth)
                targetHeight = (targetWidth / aspect).roundToInt()
            }
        }
    }
    return VideoFitSize(targetWidth, targetHeight)
}
