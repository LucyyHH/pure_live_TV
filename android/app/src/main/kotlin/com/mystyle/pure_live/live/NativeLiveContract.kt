package com.mystyle.purelive.live

object NativeLiveContract {
    const val CHANNEL = "pure_live/native_live"
    const val EXTRA_DATA = "data"
    const val ARG_TEXT = "text"
    const val ARG_COLOR = "color"
    const val ARG_INDEX = "index"
    const val ARG_DIRECTION = "direction"
    const val ARG_KEY = "key"
    const val ARG_VALUE = "value"

    const val METHOD_START = "startNativeLive"
    const val METHOD_UPDATE = "updateNativeLive"
    const val METHOD_SYNC_UI = "syncNativeLiveUi"
    const val METHOD_SEND_DANMAKU = "sendDanmaku"
    const val METHOD_SHOW_LOADING = "showLoading"
    const val METHOD_HIDE_LOADING = "hideLoading"
    const val METHOD_CLOSE = "closeNativeLive"

    const val EVENT_REQUEST_REFRESH = "onRequestRefresh"
    const val EVENT_REQUEST_QUALITY_CHANGE = "onRequestQualityChange"
    const val EVENT_REQUEST_LINE_CHANGE = "onRequestLineChange"
    const val EVENT_REQUEST_CHANNEL_SWITCH = "onRequestChannelSwitch"
    const val EVENT_TOGGLE_FAVORITE = "onToggleFavorite"
    const val EVENT_TOGGLE_PLAYLIST_FAVORITE = "onTogglePlaylistFavorite"
    const val EVENT_SELECT_PLAYLIST = "onSelectPlaylist"
    const val EVENT_CYCLE_VIDEO_FIT = "onCycleVideoFit"
    const val EVENT_DANMAKU_SETTING_CHANGE = "onDanmakuSettingChange"
    const val EVENT_PLAYBACK_ERROR = "onPlaybackError"
    const val EVENT_ACTIVITY_FINISHED = "onActivityFinished"
}
