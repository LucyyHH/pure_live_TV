package com.mystyle.purelive.live

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.SurfaceView
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import com.mystyle.purelive.MainActivity
import com.mystyle.purelive.R
import org.json.JSONObject
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

@UnstableApi
class LivePlayActivity : Activity() {

    companion object {
        var instance: LivePlayActivity? = null
        private const val COLOR_WHITE10 = 0x1AFFFFFF.toInt()
        private const val COLOR_CARD_BG = 0xDD222222.toInt()
        private const val COLOR_FOCUS_GLOW = 0xFFDC143C.toInt()
        private const val DIAGNOSTICS_ENABLED = false
    }

    // ── Views ──
    private lateinit var videoContainer: FrameLayout
    private lateinit var surfaceView: SurfaceView
    private lateinit var texturePlayerView: PlayerView
    private lateinit var danmakuView: DanmakuView
    private lateinit var topBar: LinearLayout
    private lateinit var topTitleView: TextView
    private lateinit var topTimeView: TextView
    private lateinit var channelNameBar: LinearLayout
    private lateinit var channelNameText: TextView
    private lateinit var controllerBar: HorizontalScrollView
    private lateinit var controllerButtonsContainer: LinearLayout
    private lateinit var sidePanelRoot: FrameLayout
    private lateinit var sidePanelCard: LinearLayout
    private lateinit var sidePanelTitle: TextView
    private lateinit var sidePanelScroll: ScrollView
    private lateinit var sidePanelContent: LinearLayout
    private lateinit var loadingOverlay: FrameLayout
    private lateinit var loadingSpinner: ProgressBar
    private lateinit var loadingText: TextView

    // ── Pre-created bottom button views ──
    private val bottomButtonViews = mutableListOf<BottomButtonViewHolder>()

    private lateinit var playerController: NativeLivePlayerController
    private lateinit var danmakuController: NativeLiveDanmakuController
    private val handler = Handler(Looper.getMainLooper())

    // ── Data state ──
    private var currentUrl = ""
    private var currentHeaders = emptyMap<String, String>()
    private var currentTitle = ""
    private var currentNick = ""
    private var currentChannelName = ""
    private var qualities = emptyList<String>()
    private var qualityIndex = 0
    private var lines = emptyList<String>()
    private var lineIndex = 0
    private var currentQualityName = ""
    private var playlist = mutableListOf<PlaylistItem>()
    private var currentPlaylistIndex = 0
    private var isFavoriteCurrent = false
    private var fitLabels = listOf("等比适配", "拉伸填充", "等比覆盖", "适配宽度", "适配高度", "等比缩小")
    private var fitIndex = 0
    private var danmakuState = DanmakuState()
    private var videoAspectRatio = 16f / 9f
    private var videoContentWidth = 16
    private var videoContentHeight = 9
    private var nativeRenderViewType = 0
    private var nativePreferSoftwareDecoder = false
    private var nativeCompatMode = false
    private var focusGlowColor = COLOR_FOCUS_GLOW
    private var currentVideoDecoderName = "unknown"
    private var currentVideoMimeType = "unknown"
    private var currentVideoFormatLabel = "unknown"
    private var totalDroppedVideoFrames = 0
    private var pendingCloseRunnable: Runnable? = null
    private val materialIconTypeface: Typeface? by lazy(LazyThreadSafetyMode.NONE) {
        loadTypeface("flutter_assets/fonts/MaterialIcons-Regular.otf")
    }
    private val customIconTypeface: Typeface? by lazy(LazyThreadSafetyMode.NONE) {
        loadTypeface("flutter_assets/assets/icons/CustomIcons.ttf")
    }

    // ── UI state ──
    private var controllerVisible = false
    private var activePanel = NativePanel.NONE
    private val bottomActions = buildBottomActions(DIAGNOSTICS_ENABLED)
    private var selectedBottomIndex = defaultBottomActionIndex(bottomActions)
    private var selectedPanelIndex = 0
    private var lastBackTime = 0L
    private var lastKeyTime = 0L
    private var lastFavoriteTime = 0L
    private var lastPanelData: String? = null
    private val diagnostics = NativeLiveDiagnostics(DIAGNOSTICS_ENABLED, handler) {
        if (activePanel == NativePanel.DIAGNOSTICS) {
            lastPanelData = null
            renderSidePanel()
        }
    }

    private val hideControllerRunnable = Runnable { hideController() }
    private val hideChannelNameRunnable = Runnable { channelNameBar.visibility = View.GONE }
    private val clockRunnable = object : Runnable {
        override fun run() {
            updateClock()
            handler.postDelayed(this, 10_000)
        }
    }
    // ── Lifecycle ──

    override fun onCreate(savedInstanceState: Bundle?) {
        instance?.let { old ->
            old.handler.removeCallbacksAndMessages(null)
            old.danmakuView.clear()
            old.releasePlayer(resetVideoState = true)
            old.finish()
        }

        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_live_play)
        instance = this

        bindViews()
        playerController = buildNativePlayerController()
        danmakuController = NativeLiveDanmakuController(danmakuView, resources)
        applySidePanelCardStyle()
        preCreateBottomButtons()
        appendDiagnostic(
            "device",
            "manufacturer=${android.os.Build.MANUFACTURER}, model=${android.os.Build.MODEL}, sdk=${android.os.Build.VERSION.SDK_INT}"
        )

        videoContainer.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            applyVideoFit()
        }

        updateFromJson(intent.getStringExtra(NativeLiveContract.EXTRA_DATA), reloadPlayer = false)
        createPlayer()
        startPlayback()
        handler.post(clockRunnable)
        showChannelName()
    }

    private fun bindViews() {
        videoContainer = findViewById(R.id.video_container)
        surfaceView = findViewById(R.id.video_surface)
        texturePlayerView = findViewById(R.id.video_texture_player)
        danmakuView = findViewById(R.id.danmaku_view)
        topBar = findViewById(R.id.top_bar)
        topTitleView = findViewById(R.id.top_title)
        topTimeView = findViewById(R.id.top_time)
        channelNameBar = findViewById(R.id.channel_name)
        channelNameText = findViewById(R.id.channel_name_text)
        controllerBar = findViewById(R.id.controller_bar)
        controllerButtonsContainer = findViewById(R.id.controller_buttons_container)
        sidePanelRoot = findViewById(R.id.side_panel_root)
        sidePanelCard = findViewById(R.id.side_panel_card)
        sidePanelTitle = findViewById(R.id.side_panel_title)
        sidePanelScroll = findViewById(R.id.side_panel_scroll)
        sidePanelContent = findViewById(R.id.side_panel_content)
        loadingOverlay = findViewById(R.id.loading_overlay)
        loadingSpinner = findViewById(R.id.loading_spinner)
        loadingText = findViewById(R.id.loading_text)
    }

    private fun applySidePanelCardStyle() {
        applyThemeDecorations()
    }

    private fun preCreateBottomButtons() {
        controllerButtonsContainer.removeAllViews()
        bottomButtonViews.clear()
        for (action in bottomActions) {
            val hasLabel = bottomButtonHasLabel(action)
            val root = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                minimumHeight = 48.dp()
                minimumWidth = if (hasLabel) 0 else 48.dp()
                setPadding(
                    if (hasLabel) 20.dp() else 12.dp(),
                    10.dp(),
                    if (hasLabel) 20.dp() else 12.dp(),
                    10.dp()
                )
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { marginEnd = 10.dp() }
            }
            val iconView = TextView(this).apply {
                textSize = if (hasLabel) 19f else 24f
                gravity = Gravity.CENTER
                includeFontPadding = false
                minimumWidth = if (hasLabel) 0 else 24.dp()
            }
            root.addView(iconView)

            val labelView = if (hasLabel) {
                TextView(this).apply {
                    textSize = 16f
                    gravity = Gravity.CENTER
                    includeFontPadding = false
                    setPadding(8.dp(), 0, 0, 0)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    maxWidth = 160.dp()
                }.also(root::addView)
            } else {
                null
            }

            val holder = BottomButtonViewHolder(root = root, iconView = iconView, labelView = labelView)
            bottomButtonViews.add(holder)
            controllerButtonsContainer.addView(root)
        }
    }

    // ── Public API (called from Flutter) ──

    fun updatePlayUrl(json: String?) {
        runOnMain {
            cancelPendingClose()
            updateFromJson(json, reloadPlayer = true)
        }
    }

    fun syncUi(json: String?) {
        runOnMain {
            cancelPendingClose()
            updateFromJson(json, reloadPlayer = false)
        }
    }

    fun addDanmaku(text: String, color: Int) {
        runOnMain { danmakuView.addDanmaku(text, color) }
    }

    fun reopenWithPayload(json: String?) {
        runOnMain {
            cancelPendingClose()
            val hadPlayer = playerController.player != null
            updateFromJson(json, reloadPlayer = hadPlayer)
            if (!hadPlayer) {
                createPlayer()
                startPlayback()
                showChannelName()
            }
        }
    }

    fun closeActivity() {
        var closeRunnable: Runnable? = null
        closeRunnable = Runnable {
            if (pendingCloseRunnable !== closeRunnable) {
                return@Runnable
            }
            pendingCloseRunnable = null
            releasePlayer(resetVideoState = true)
            if (instance == this) {
                instance = null
            }
            finish()
        }
        pendingCloseRunnable?.let(handler::removeCallbacks)
        pendingCloseRunnable = closeRunnable
        if (Looper.myLooper() == Looper.getMainLooper()) {
            closeRunnable?.run()
        } else {
            closeRunnable?.let(handler::post)
        }
    }

    fun showNativeLoading() {
        runOnMain { loadingOverlay.visibility = View.VISIBLE }
    }

    fun hideNativeLoading() {
        runOnMain { loadingOverlay.visibility = View.GONE }
    }

    // ── JSON / Data ──

    private fun updateFromJson(json: String?, reloadPlayer: Boolean) {
        if (json.isNullOrBlank()) return
        val renderConfigChanged = applyPayload(json)
        refreshBottomControls()
        if (activePanel != NativePanel.NONE) renderSidePanel()
        updateTopBar()
        applyDanmakuConfig()
        applyVideoFit()
        val shouldRecreatePlayer = playerController.player != null && renderConfigChanged
        if (reloadPlayer || shouldRecreatePlayer) {
            danmakuView.clear()
            if (shouldRecreatePlayer) {
                createPlayer()
            }
            startPlayback(stopFirst = reloadPlayer && !shouldRecreatePlayer)
            showChannelName()
        }
    }

    private fun applyPayload(json: String): Boolean {
        val previousRenderConfig = currentRenderConfig()
        val payload = parseNativePlaybackPayload(
            obj = JSONObject(json),
            currentUrl = currentUrl,
            currentHeaders = currentHeaders,
            currentTitle = currentTitle,
            currentNick = currentNick,
            currentChannelName = currentChannelName,
            qualities = qualities,
            qualityIndex = qualityIndex,
            lines = lines,
            lineIndex = lineIndex,
            currentQualityName = currentQualityName,
            playlist = playlist,
            currentPlaylistIndex = currentPlaylistIndex,
            isFavoriteCurrent = isFavoriteCurrent,
            fitLabels = fitLabels,
            fitIndex = fitIndex,
            danmakuState = danmakuState,
            nativeRenderViewType = nativeRenderViewType,
            nativePreferSoftwareDecoder = nativePreferSoftwareDecoder,
            nativeCompatMode = nativeCompatMode,
            focusGlowColor = focusGlowColor,
        )
        applyParsedPayload(payload)
        applyThemeDecorations()
        updateVideoOutputView()
        normalizeParsedState()
        return previousRenderConfig != currentRenderConfig()
    }

    private fun applyParsedPayload(payload: NativePlaybackPayload) {
        currentUrl = payload.url
        currentHeaders = payload.headers
        currentTitle = payload.title
        currentNick = payload.nick
        currentChannelName = payload.channelName
        qualities = payload.qualities
        qualityIndex = payload.qualityIndex
        lines = payload.lines
        lineIndex = payload.lineIndex
        currentQualityName = payload.currentQualityName
        playlist = payload.playlist.toMutableList()
        currentPlaylistIndex = payload.currentPlaylistIndex
        isFavoriteCurrent = payload.isFavoriteCurrent
        fitLabels = payload.fitLabels
        fitIndex = payload.fitIndex
        danmakuState = payload.danmakuState
        nativeRenderViewType = payload.renderConfig.viewType
        nativePreferSoftwareDecoder = payload.renderConfig.preferSoftwareDecoder
        nativeCompatMode = payload.renderConfig.compatMode
        focusGlowColor = payload.themeColorValue
    }

    private fun normalizeParsedState() {
        if (qualities.indices.contains(qualityIndex)) {
            currentQualityName = qualities[qualityIndex]
        }
        fitIndex = fitIndex.coerceIn(0, max(0, fitLabels.lastIndex))
        currentPlaylistIndex = currentPlaylistIndex.coerceIn(0, max(0, playlist.lastIndex))
        selectedPanelIndex = selectedPanelIndex.coerceIn(0, max(0, panelItemCount() - 1))
    }

    private fun currentRenderConfig(): NativeRenderConfig {
        return NativeRenderConfig(
            viewType = nativeRenderViewType,
            preferSoftwareDecoder = nativePreferSoftwareDecoder,
            compatMode = nativeCompatMode,
        )
    }

    // ── Player ──

    private fun buildNativePlayerController(): NativeLivePlayerController {
        return NativeLivePlayerController(
            activity = this,
            surfaceView = surfaceView,
            texturePlayerView = texturePlayerView,
            renderConfigProvider = { currentRenderConfig() },
            currentUrlProvider = { currentUrl },
            currentHeadersProvider = { currentHeaders },
            appendDiagnostic = ::appendDiagnostic,
            onVideoSizeChanged = ::updateVideoMetrics,
            onPlaybackStateChanged = { playbackState ->
                logPlayerSnapshot("state=${playbackStateName(playbackState)}")
                if (playbackState == Player.STATE_READY) {
                    hideNativeLoading()
                }
            },
            onIsPlayingChanged = { isPlaying ->
                logPlayerSnapshot("isPlaying=$isPlaying")
            },
            onPlayWhenReadyChanged = { playWhenReady, reason ->
                logPlayerSnapshot("playWhenReady=$playWhenReady reason=$reason")
            },
            onPlayerError = { error ->
                appendDiagnostic(
                    "playerError",
                    "${error.errorCodeName}: ${error.message.orEmpty()}"
                )
                releasePlayer(resetVideoState = false)
                showToast("播放出错，请按确定键刷新")
                callFlutter(
                    NativeLiveContract.EVENT_PLAYBACK_ERROR,
                    mapOf("error" to error.message.orEmpty())
                )
            },
            onVideoInputFormatChanged = { format, decoderReuseEvaluation ->
                currentVideoMimeType = format.sampleMimeType ?: "unknown"
                currentVideoFormatLabel = buildVideoFormatLabel(format)
                appendDiagnostic(
                    "videoFormat",
                    "mime=$currentVideoMimeType, format=$currentVideoFormatLabel, bitrate=${format.bitrate}, reuse=${decoderReuseEvaluation?.result}"
                )
            },
            onVideoDecoderInitialized = { decoderName, initializedTimestampMs, initializationDurationMs ->
                currentVideoDecoderName = decoderName
                appendDiagnostic(
                    "decoderInit",
                    "decoder=$decoderName, initMs=$initializationDurationMs, ts=$initializedTimestampMs"
                )
            },
            onRenderedFirstFrame = { output, renderTimeMs ->
                appendDiagnostic(
                    "firstFrame",
                    "output=${output.javaClass.simpleName}, renderTimeMs=$renderTimeMs, view=${activeOutputName()}"
                )
                hideNativeLoading()
            },
            onDroppedVideoFrames = { droppedFrames, elapsedMs ->
                totalDroppedVideoFrames += droppedFrames
                appendDiagnostic(
                    "droppedFrames",
                    "count=$droppedFrames, total=$totalDroppedVideoFrames, elapsedMs=$elapsedMs"
                )
            },
            onVideoCodecError = { videoCodecError ->
                appendDiagnostic(
                    "codecError",
                    "${videoCodecError.javaClass.simpleName}: ${videoCodecError.message.orEmpty()}"
                )
            },
        )
    }

    private fun resetPlayerDiagnostics() {
        currentVideoDecoderName = "unknown"
        currentVideoMimeType = "unknown"
        currentVideoFormatLabel = "unknown"
        totalDroppedVideoFrames = 0
    }

    private fun createPlayer() {
        resetPlayerDiagnostics()
        playerController.createPlayer()
    }

    private fun updateVideoMetrics(videoSize: VideoSize) {
        if (videoSize.width <= 0 || videoSize.height <= 0) {
            return
        }
        val pixelRatio = videoSize.pixelWidthHeightRatio.takeIf { it > 0f } ?: 1f
        videoContentWidth = (videoSize.width * pixelRatio).roundToInt().coerceAtLeast(1)
        videoContentHeight = videoSize.height.coerceAtLeast(1)
        videoAspectRatio = ((videoSize.width * pixelRatio) / videoSize.height).coerceAtLeast(0.1f)
        appendDiagnostic(
            "videoSize",
            "width=${videoSize.width}, height=${videoSize.height}, pixelRatio=$pixelRatio"
        )
        applyVideoFit()
    }

    private fun startPlayback(stopFirst: Boolean = false) {
        playerController.startPlayback(stopFirst)
    }

    // ── Key Handling ──

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode != KeyEvent.KEYCODE_BACK) {
            val now = System.currentTimeMillis()
            if (now - lastKeyTime < 80) return true
            lastKeyTime = now
        }
        if (keyCode == KeyEvent.KEYCODE_MENU) { openPanel(NativePanel.SETTINGS); return true }
        if (activePanel != NativePanel.NONE) return handlePanelKey(keyCode)
        if (controllerVisible) return handleControllerKey(keyCode)
        return handleIdleKey(keyCode)
    }

    private fun handleIdleKey(keyCode: Int): Boolean = when (keyCode) {
        KeyEvent.KEYCODE_BACK -> {
            val now = System.currentTimeMillis()
            if (now - lastBackTime < 800) {
                callFlutter(NativeLiveContract.EVENT_ACTIVITY_FINISHED, emptyMap())
                finish()
            }
            else { lastBackTime = now; showToast("再按一次返回退出") }
            true
        }
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_SPACE -> { showController(); true }
        KeyEvent.KEYCODE_DPAD_UP -> { requestChannelSwitch(-1); true }
        KeyEvent.KEYCODE_DPAD_DOWN -> { requestChannelSwitch(1); true }
        KeyEvent.KEYCODE_DPAD_LEFT -> { handleDoubleFavoriteAction(); true }
        KeyEvent.KEYCODE_DPAD_RIGHT -> { openPanel(NativePanel.PLAYLIST); true }
        else -> super.onKeyDown(keyCode, null)
    }

    private fun handleControllerKey(keyCode: Int): Boolean = when (keyCode) {
        KeyEvent.KEYCODE_BACK -> { hideController(); true }
        KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_DOWN -> {
            selectedBottomIndex = (selectedBottomIndex + 1) % bottomActions.size
            updateBottomButtonHighlight(); scheduleControllerHide(); true
        }
        KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_UP -> {
            selectedBottomIndex = (selectedBottomIndex - 1 + bottomActions.size) % bottomActions.size
            updateBottomButtonHighlight(); scheduleControllerHide(); true
        }
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_SPACE -> {
            scheduleControllerHide(); performBottomAction(bottomActions[selectedBottomIndex]); true
        }
        else -> super.onKeyDown(keyCode, null)
    }

    private fun handlePanelKey(keyCode: Int): Boolean = when (keyCode) {
        KeyEvent.KEYCODE_BACK -> { closePanel(); true }
        KeyEvent.KEYCODE_DPAD_UP -> { movePanelSelection(-1); true }
        KeyEvent.KEYCODE_DPAD_DOWN -> { movePanelSelection(1); true }
        KeyEvent.KEYCODE_DPAD_LEFT -> { handlePanelHorizontal(-1); true }
        KeyEvent.KEYCODE_DPAD_RIGHT -> { handlePanelHorizontal(1); true }
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_SPACE -> { performPanelConfirm(); true }
        else -> super.onKeyDown(keyCode, null)
    }

    private fun movePanelSelection(delta: Int) {
        val count = panelItemCount()
        if (count <= 0) return
        selectedPanelIndex = (selectedPanelIndex + delta + count) % count
        updatePanelHighlight()
        scrollSidePanelToSelection()
    }

    private fun handlePanelHorizontal(delta: Int) {
        when (activePanel) {
            NativePanel.SETTINGS -> adjustDanmakuSetting(delta)
            NativePanel.PLAYLIST -> confirmTogglePlaylistFavorite(selectedPanelIndex)
            else -> Unit
        }
    }

    private fun performPanelConfirm() {
        when (activePanel) {
            NativePanel.QUALITY -> {
                if (!qualities.indices.contains(selectedPanelIndex)) return
                qualityIndex = selectedPanelIndex
                currentQualityName = qualities[selectedPanelIndex]
                showLoadingAndClosePanel()
                callFlutter(
                    NativeLiveContract.EVENT_REQUEST_QUALITY_CHANGE,
                    mapOf(NativeLiveContract.ARG_INDEX to selectedPanelIndex)
                )
            }
            NativePanel.LINES -> {
                if (!lines.indices.contains(selectedPanelIndex)) return
                lineIndex = selectedPanelIndex
                showLoadingAndClosePanel()
                callFlutter(
                    NativeLiveContract.EVENT_REQUEST_LINE_CHANGE,
                    mapOf(NativeLiveContract.ARG_INDEX to selectedPanelIndex)
                )
            }
            NativePanel.PLAYLIST -> {
                if (!playlist.indices.contains(selectedPanelIndex)) return
                currentPlaylistIndex = selectedPanelIndex
                isFavoriteCurrent = playlist[selectedPanelIndex].isFavorite
                showLoadingAndClosePanel()
                callFlutter(
                    NativeLiveContract.EVENT_SELECT_PLAYLIST,
                    mapOf(NativeLiveContract.ARG_INDEX to selectedPanelIndex)
                )
            }
            NativePanel.DIAGNOSTICS -> {
                val items = diagnosticPanelItems()
                if (!items.indices.contains(selectedPanelIndex)) return
                if (selectedPanelIndex == 0) {
                    copyDiagnosticsToClipboard()
                } else {
                    copyTextToClipboard("native_player_diag_line", items[selectedPanelIndex])
                    showToast("已复制当前诊断行")
                }
            }
            NativePanel.SETTINGS, NativePanel.NONE -> Unit
        }
    }

    private fun performBottomAction(action: BottomAction) {
        when (action) {
            BottomAction.FAVORITE -> {
                confirmToggleCurrentFavorite()
            }
            BottomAction.REFRESH -> {
                showNativeLoading(); hideController()
                callFlutter(NativeLiveContract.EVENT_REQUEST_REFRESH, emptyMap())
            }
            BottomAction.PLAY_PAUSE -> {
                playerController.togglePlayPause()
                refreshBottomControls()
            }
            BottomAction.DANMAKU -> {
                danmakuState.hidden = !danmakuState.hidden
                applyDanmakuConfig()
                refreshBottomControls()
                pushDanmakuSetting("hidden", danmakuState.hidden)
            }
            BottomAction.SETTINGS -> openPanel(NativePanel.SETTINGS)
            BottomAction.QUALITY -> openPanel(NativePanel.QUALITY)
            BottomAction.LINE -> openPanel(NativePanel.LINES)
            BottomAction.BOX_FIT -> cycleVideoFit()
            BottomAction.DIAGNOSTICS -> if (DIAGNOSTICS_ENABLED) openPanel(NativePanel.DIAGNOSTICS)
        }
    }

    // ── Controller show/hide ──

    private fun showController() {
        controllerVisible = true
        activePanel = NativePanel.NONE
        updateTopBar()
        refreshBottomControls()
        controllerBar.visibility = View.VISIBLE
        sidePanelRoot.visibility = View.GONE
        scheduleControllerHide()
    }

    private fun hideController() {
        controllerVisible = false
        topBar.visibility = View.GONE
        controllerBar.visibility = View.GONE
        handler.removeCallbacks(hideControllerRunnable)
    }

    private fun openPanel(panel: NativePanel) {
        activePanel = panel
        controllerVisible = false
        selectedPanelIndex = when (panel) {
            NativePanel.QUALITY -> qualityIndex
            NativePanel.LINES -> lineIndex
            NativePanel.PLAYLIST -> currentPlaylistIndex
            NativePanel.DIAGNOSTICS -> 0
            else -> 0
        }
        handler.removeCallbacks(hideControllerRunnable)
        topBar.visibility = View.GONE
        controllerBar.visibility = View.GONE
        lastPanelData = null
        renderSidePanel()
    }

    private fun closePanel() {
        activePanel = NativePanel.NONE
        sidePanelRoot.visibility = View.GONE
        lastPanelData = null
    }

    private fun scheduleControllerHide() {
        handler.removeCallbacks(hideControllerRunnable)
        handler.postDelayed(hideControllerRunnable, 5000)
    }

    // ── Bottom Bar Rendering (pre-created buttons, only update properties) ──

    private fun updateBottomButtonLabels() {
        if (!controllerVisible) {
            controllerBar.visibility = View.GONE
            return
        }
        controllerBar.visibility = View.VISIBLE
        for (i in bottomButtonViews.indices) {
            val holder = bottomButtonViews[i]
            val action = bottomActions.getOrNull(i) ?: continue
            val presentation = getBottomButtonPresentation(action)
            holder.iconView.text = presentation.icon
            holder.iconView.typeface = presentation.iconTypeface ?: Typeface.DEFAULT
            holder.labelView?.text = presentation.label.orEmpty()
            applyBottomButtonStyle(holder, i == selectedBottomIndex)
        }
    }

    private fun updateBottomButtonHighlight() {
        for (i in bottomButtonViews.indices) {
            applyBottomButtonStyle(bottomButtonViews[i], i == selectedBottomIndex)
        }
    }

    private fun applyBottomButtonStyle(holder: BottomButtonViewHolder, selected: Boolean) {
        applySelectableSurface(holder.root, selected, cornerRadiusDp = 32, elevationDp = 8, idleScale = 0.98f)
        val textColor = if (selected) Color.BLACK else Color.WHITE
        holder.iconView.setTextColor(textColor)
        holder.labelView?.setTextColor(textColor)
    }

    // ── Side Panel Rendering ──

    private fun renderSidePanel() {
        if (activePanel == NativePanel.NONE) {
            sidePanelRoot.visibility = View.GONE
            return
        }

        val width = when (activePanel) {
            NativePanel.PLAYLIST -> 450.dp()
            NativePanel.DIAGNOSTICS -> 720.dp()
            else -> 380.dp()
        }
        (sidePanelRoot.layoutParams as FrameLayout.LayoutParams).width = width
        sidePanelRoot.requestLayout()
        sidePanelRoot.visibility = View.VISIBLE
        sidePanelTitle.text = panelTitle(activePanel)

        val fingerprint = buildPanelFingerprint(
            panel = activePanel,
            danmakuState = danmakuState,
            qualities = qualities,
            lines = lines,
            lineIndex = lineIndex,
            playlist = playlist,
            diagnosticsSize = diagnostics.size,
            lastDiagnosticHash = diagnostics.lastHash,
            currentVideoDecoderName = currentVideoDecoderName,
            totalDroppedVideoFrames = totalDroppedVideoFrames,
        )
        if (fingerprint != lastPanelData) {
            lastPanelData = fingerprint
            sidePanelContent.removeAllViews()
            when (activePanel) {
                NativePanel.SETTINGS -> buildSettingsPanel()
                NativePanel.QUALITY -> buildSimplePanel(qualities)
                NativePanel.LINES -> buildSimplePanel(lines.ifEmpty {
                    List(max(lineIndex + 1, 1)) { "线路${it + 1}" }
                })
                NativePanel.PLAYLIST -> buildPlaylistPanel()
                NativePanel.DIAGNOSTICS -> buildDiagnosticsPanel()
                NativePanel.NONE -> Unit
            }
        } else {
            updatePanelHighlight()
        }
    }

    private fun buildSettingsPanel() {
        val rows = getSettingsRows()
        selectedPanelIndex = selectedPanelIndex.coerceIn(0, max(0, rows.lastIndex))
        rows.forEachIndexed { i, (label, value) ->
            val sel = i == selectedPanelIndex
            sidePanelContent.addView(createSettingsRow(label, value, sel), panelRowLayoutParams())
        }
    }

    private fun buildSimplePanel(items: List<String>) {
        selectedPanelIndex = selectedPanelIndex.coerceIn(0, max(0, items.lastIndex))
        items.forEachIndexed { i, text ->
            sidePanelContent.addView(createHighlightRow(text, i == selectedPanelIndex), panelRowLayoutParams())
        }
    }

    private fun buildPlaylistPanel() {
        selectedPanelIndex = selectedPanelIndex.coerceIn(0, max(0, playlist.lastIndex))
        playlist.forEachIndexed { i, item ->
            sidePanelContent.addView(createPlaylistRow(i, item, i == selectedPanelIndex), panelRowLayoutParams())
        }
    }

    private fun buildDiagnosticsPanel() {
        val items = diagnosticPanelItems()
        selectedPanelIndex = selectedPanelIndex.coerceIn(0, max(0, items.lastIndex))
        items.forEachIndexed { i, text ->
            sidePanelContent.addView(
                createDiagnosticRow(text, i == selectedPanelIndex, isAction = i == 0),
                panelRowLayoutParams()
            )
        }
    }

    private fun updatePanelHighlight() {
        val count = sidePanelContent.childCount
        for (i in 0 until count) {
            val child = sidePanelContent.getChildAt(i)
            val sel = i == selectedPanelIndex
            when (activePanel) {
                NativePanel.SETTINGS -> updateSettingsRowStyle(child, sel)
                NativePanel.PLAYLIST -> updatePlaylistRowStyle(child, sel)
                else -> updateHighlightRowStyle(child as? TextView, sel)
            }
        }
    }

    // ── Settings Row: [Title] [Spacer] [<] [Value] [>] ──

    private fun getSettingsRows(): List<Pair<String, String>> = listOf(
        "弹幕开关" to if (danmakuState.hidden) "关" else "开",
        "弹幕大小" to danmakuState.fontSize.formatValue(),
        "弹幕速度" to danmakuState.speed.formatValue(),
        "显示区域" to "${(danmakuState.area * 100).roundToInt()}%",
        "距离顶部" to danmakuState.topDistance.formatValue(),
        "距离底部" to danmakuState.bottomDistance.formatValue(),
        "不透明度" to "${(danmakuState.opacity * 100).roundToInt()}%",
        "描边宽度" to danmakuState.stroke.formatValue()
    )

    private fun createSettingsRow(label: String, value: String, selected: Boolean): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(20.dp(), 14.dp(), 20.dp(), 14.dp())
        }
        row.addView(TextView(this).apply {
            text = label
            textSize = 18f
            tag = "label"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        row.addView(TextView(this).apply {
            text = "◀"
            textSize = 16f
            tag = "arrowL"
            setPadding(8.dp(), 0, 4.dp(), 0)
        })
        row.addView(TextView(this).apply {
            text = value
            textSize = 18f
            tag = "value"
            gravity = Gravity.CENTER
            minimumWidth = 80.dp()
        })
        row.addView(TextView(this).apply {
            text = "▶"
            textSize = 16f
            tag = "arrowR"
            setPadding(4.dp(), 0, 8.dp(), 0)
        })
        applyRowRoundBg(row, selected)
        applySettingsTextColors(row, selected)
        return row
    }

    private fun updateSettingsRowStyle(view: View?, selected: Boolean) {
        if (view !is LinearLayout) return
        applyRowRoundBg(view, selected)
        applySettingsTextColors(view, selected)
    }

    private fun applySettingsTextColors(row: LinearLayout, selected: Boolean) {
        val color = if (selected) Color.BLACK else Color.WHITE
        for (i in 0 until row.childCount) {
            (row.getChildAt(i) as? TextView)?.setTextColor(color)
        }
    }

    // ── Highlight Row (quality / line) ──

    private fun createHighlightRow(text: String, selected: Boolean): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(20.dp(), 14.dp(), 20.dp(), 14.dp())
            applyRowRoundBg(this, selected)
            setTextColor(if (selected) Color.BLACK else Color.WHITE)
        }
    }

    private fun createDiagnosticRow(text: String, selected: Boolean, isAction: Boolean): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = if (isAction) 16f else 13f
            gravity = if (isAction) Gravity.CENTER else Gravity.START or Gravity.CENTER_VERTICAL
            setPadding(18.dp(), 14.dp(), 18.dp(), 14.dp())
            typeface = if (isAction) Typeface.DEFAULT_BOLD else Typeface.MONOSPACE
            setLineSpacing(0f, 1.1f)
            applyRowRoundBg(this, selected)
            setTextColor(if (selected) Color.BLACK else Color.WHITE)
        }
    }

    private fun updateHighlightRowStyle(tv: TextView?, selected: Boolean) {
        tv ?: return
        applyRowRoundBg(tv, selected)
        tv.setTextColor(if (selected) Color.BLACK else Color.WHITE)
    }

    // ── Playlist Row ──

    private fun createPlaylistRow(index: Int, item: PlaylistItem, selected: Boolean): LinearLayout {
        val displayName = playlistDisplayName(item)

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(20.dp(), 12.dp(), 20.dp(), 12.dp())
            minimumHeight = 70.dp()
        }

        val textContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        textContainer.addView(TextView(this).apply {
            text = "${index + 1}. ${displayName.ifBlank { item.title.ifBlank { "未命名频道" } }}"
            textSize = 18f
            tag = "title"
            maxLines = 1
        })
        textContainer.addView(TextView(this).apply {
            text = item.title.ifBlank { displayName }
            textSize = 14f
            tag = "subtitle"
            maxLines = 1
        })
        row.addView(textContainer)

        row.addView(TextView(this).apply {
            text = if (item.isFavorite) "已关注" else "未关注"
            textSize = 14f
            tag = "fav"
            setPadding(12.dp(), 4.dp(), 12.dp(), 4.dp())
        })

        applyRowRoundBg(row, selected)
        applyPlaylistTextColors(row, selected)
        return row
    }

    private fun updatePlaylistRowStyle(view: View?, selected: Boolean) {
        if (view !is LinearLayout) return
        applyRowRoundBg(view, selected)
        applyPlaylistTextColors(view, selected)
    }

    private fun applyPlaylistTextColors(row: LinearLayout, selected: Boolean) {
        val primary = if (selected) Color.BLACK else Color.WHITE
        val secondary = if (selected) Color.DKGRAY else Color.parseColor("#B3FFFFFF")
        for (i in 0 until row.childCount) {
            val child = row.getChildAt(i)
            if (child is TextView) {
                child.setTextColor(if (child.tag == "fav") secondary else primary)
            } else if (child is LinearLayout) {
                for (j in 0 until child.childCount) {
                    val tv = child.getChildAt(j) as? TextView ?: continue
                    tv.setTextColor(if (tv.tag == "subtitle") secondary else primary)
                }
            }
        }
    }

    // ── Shared styling helpers ──

    private fun applyRowRoundBg(view: View, selected: Boolean) {
        applySelectableSurface(view, selected, cornerRadiusDp = 16, elevationDp = 6, idleScale = 0.992f)
    }

    private fun panelRowLayoutParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 8.dp() }
    }

    private fun applySelectableSurface(
        view: View,
        selected: Boolean,
        cornerRadiusDp: Int,
        elevationDp: Int,
        idleScale: Float,
    ) {
        applyNativeLiveSelectableSurface(
            view = view,
            selected = selected,
            focusGlowColor = focusGlowColor,
            cornerRadiusPx = cornerRadiusDp.dp(),
            selectedStrokePx = 2.dp(),
            elevationPx = elevationDp.dp(),
            selectedTranslationYPx = 1.dp(),
            idleScale = idleScale,
            idleColor = COLOR_WHITE10,
        )
    }

    private fun applyThemeDecorations() {
        if (!::sidePanelCard.isInitialized) return
        sidePanelCard.background = GradientDrawable().apply {
            setColor(COLOR_CARD_BG)
            cornerRadius = 10.dp().toFloat()
            setStroke(1.dp(), focusGlowColor)
        }
        sidePanelTitle.setTextColor(focusGlowColor)
        if (::loadingText.isInitialized) {
            loadingText.setTextColor(focusGlowColor)
        }
        if (::loadingSpinner.isInitialized) {
            loadingSpinner.indeterminateTintList = ColorStateList.valueOf(focusGlowColor)
            loadingSpinner.indeterminateTintMode = PorterDuff.Mode.SRC_IN
        }
        if (controllerVisible) {
            updateBottomButtonHighlight()
        }
        if (activePanel != NativePanel.NONE) {
            updatePanelHighlight()
        }
    }

    // ── Top Bar / Channel Name ──

    private fun updateTopBar() {
        topBar.visibility = if (controllerVisible) View.VISIBLE else View.GONE
        topTitleView.text = currentTitle.ifBlank { "正在读取直播信息..." }
        updateClock()
    }

    private fun updateClock() {
        val now = java.util.Calendar.getInstance()
        val h = now.get(java.util.Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
        val m = now.get(java.util.Calendar.MINUTE).toString().padStart(2, '0')
        topTimeView.text = "$h:$m"
    }

    private fun showChannelName() {
        val text = currentChannelName.ifBlank {
            if (playlist.indices.contains(currentPlaylistIndex)) {
                val item = playlist[currentPlaylistIndex]
                val name = playlistDisplayName(item)
                "${currentPlaylistIndex + 1}. $name"
            } else {
                currentTitle.ifBlank { currentNick }
            }
        }
        channelNameText.text = text
        channelNameBar.visibility = View.VISIBLE
        handler.removeCallbacks(hideChannelNameRunnable)
        handler.postDelayed(hideChannelNameRunnable, 2000)
    }

    // ── Channel / Favorite actions ──

    private fun requestChannelSwitch(direction: Int) {
        showNativeLoading()
        callFlutter(
            NativeLiveContract.EVENT_REQUEST_CHANNEL_SWITCH,
            mapOf(NativeLiveContract.ARG_DIRECTION to direction)
        )
    }

    private fun handleDoubleFavoriteAction() {
        val now = System.currentTimeMillis()
        if (now - lastFavoriteTime < 500) {
            lastFavoriteTime = 0L
            confirmToggleCurrentFavorite()
            return
        }
        lastFavoriteTime = now
        showToast(if (isFavoriteCurrent) "双击取消关注" else "双击关注")
    }

    private fun confirmToggleCurrentFavorite() {
        showFavoriteConfirmDialog(isFavoriteCurrent) { toggleCurrentFavorite() }
    }

    private fun confirmTogglePlaylistFavorite(index: Int) {
        if (!playlist.indices.contains(index)) return
        showFavoriteConfirmDialog(playlist[index].isFavorite) { togglePlaylistFavorite(index) }
    }

    private fun showFavoriteConfirmDialog(isFavorite: Boolean, onConfirm: () -> Unit) {
        handler.removeCallbacks(hideControllerRunnable)
        AlertDialog.Builder(this)
            .setTitle(if (isFavorite) "取消关注" else "关注主播")
            .setMessage(if (isFavorite) "是否去掉关注主播？" else "是否关注主播？")
            .setNegativeButton("取消", null)
            .setPositiveButton("确定") { _, _ -> onConfirm() }
            .setOnDismissListener {
                if (controllerVisible && activePanel == NativePanel.NONE) {
                    scheduleControllerHide()
                }
            }
            .show()
    }

    private fun toggleCurrentFavorite() {
        isFavoriteCurrent = !isFavoriteCurrent
        if (playlist.indices.contains(currentPlaylistIndex)) {
            playlist[currentPlaylistIndex].isFavorite = isFavoriteCurrent
        }
        refreshBottomControls()
        if (activePanel == NativePanel.PLAYLIST) {
            invalidateSidePanel()
        }
        callFlutter(NativeLiveContract.EVENT_TOGGLE_FAVORITE, emptyMap())
    }

    private fun togglePlaylistFavorite(index: Int) {
        if (!playlist.indices.contains(index)) return
        playlist[index].isFavorite = !playlist[index].isFavorite
        if (index == currentPlaylistIndex) {
            isFavoriteCurrent = playlist[index].isFavorite
            refreshBottomControls()
        }
        invalidateSidePanel()
        callFlutter(
            NativeLiveContract.EVENT_TOGGLE_PLAYLIST_FAVORITE,
            mapOf(NativeLiveContract.ARG_INDEX to index)
        )
    }

    private fun cycleVideoFit() {
        fitIndex = (fitIndex + 1) % max(fitLabels.size, 1)
        applyVideoFit()
        refreshBottomControls()
        callFlutter(
            NativeLiveContract.EVENT_CYCLE_VIDEO_FIT,
            mapOf(NativeLiveContract.ARG_INDEX to fitIndex)
        )
    }

    // ── Danmaku Settings ──

    private fun adjustDanmakuSetting(delta: Int) {
        when (selectedPanelIndex) {
            0 -> { danmakuState.hidden = !danmakuState.hidden; pushDanmakuSetting("hidden", danmakuState.hidden) }
            1 -> { danmakuState.fontSize = danmakuController.stepSize(danmakuState.fontSize, delta); pushDanmakuSetting("fontSize", danmakuState.fontSize) }
            2 -> { danmakuState.speed = danmakuController.stepSpeed(danmakuState.speed, delta); pushDanmakuSetting("speed", danmakuState.speed) }
            3 -> { danmakuState.area = danmakuController.stepArea(danmakuState.area, delta); pushDanmakuSetting("area", danmakuState.area) }
            4 -> { danmakuState.topDistance = danmakuController.stepDistance(danmakuState.topDistance, delta); pushDanmakuSetting("topDistance", danmakuState.topDistance) }
            5 -> { danmakuState.bottomDistance = danmakuController.stepDistance(danmakuState.bottomDistance, delta); pushDanmakuSetting("bottomDistance", danmakuState.bottomDistance) }
            6 -> { danmakuState.opacity = danmakuController.stepArea(danmakuState.opacity, delta); pushDanmakuSetting("opacity", danmakuState.opacity) }
            7 -> { danmakuState.stroke = danmakuController.stepStroke(danmakuState.stroke, delta); pushDanmakuSetting("stroke", danmakuState.stroke) }
        }
        applyDanmakuConfig()
        invalidateSidePanel()
    }

    private fun refreshBottomControls() {
        updateBottomButtonLabels()
    }

    private fun invalidateSidePanel() {
        lastPanelData = null
        renderSidePanel()
    }

    private fun showLoadingAndClosePanel() {
        showNativeLoading()
        closePanel()
    }

    private fun pushDanmakuSetting(key: String, value: Any) {
        callFlutter(
            NativeLiveContract.EVENT_DANMAKU_SETTING_CHANGE,
            mapOf(
                NativeLiveContract.ARG_KEY to key,
                NativeLiveContract.ARG_VALUE to value
            )
        )
    }

    private fun applyDanmakuConfig() {
        danmakuController.applyConfig(danmakuState)
    }

    // ── Video Fit ──

    private fun applyVideoFit() {
        val containerWidth = videoContainer.width
        val containerHeight = videoContainer.height
        if (containerWidth == 0 || containerHeight == 0) return
        val targetSize = calculateVideoFitSize(
            containerWidth = containerWidth,
            containerHeight = containerHeight,
            videoAspectRatio = videoAspectRatio,
            videoContentWidth = videoContentWidth,
            videoContentHeight = videoContentHeight,
            fitIndex = fitIndex,
        )
        activeVideoView().layoutParams = FrameLayout.LayoutParams(
            targetSize.width,
            targetSize.height,
            Gravity.CENTER
        )
    }

    // ── Helpers ──

    private fun panelItemCount(): Int = panelItemCount(
        panel = activePanel,
        qualities = qualities,
        lines = lines,
        lineIndex = lineIndex,
        playlist = playlist,
        diagnosticsCount = diagnosticPanelItems().size,
    )

    private fun scrollSidePanelToSelection() {
        if (sidePanelContent.childCount == 0) return
        val row = sidePanelContent.getChildAt(selectedPanelIndex) ?: return
        sidePanelScroll.post { sidePanelScroll.smoothScrollTo(0, row.top - 24.dp()) }
    }

    private fun callFlutter(method: String, args: Map<String, Any?>) {
        MainActivity.dispatchFlutter(method, args)
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            handler.post { action() }
        }
    }

    private fun cancelPendingClose() {
        pendingCloseRunnable?.let(handler::removeCallbacks)
        pendingCloseRunnable = null
    }

    private fun diagnosticPanelItems(): List<String> {
        val summary = buildString {
            append("输出=${activeOutputName()}")
            append(" | 解码偏好=${if (nativePreferSoftwareDecoder) "软解优先" else "硬解优先"}")
            append(" | 兼容模式=${if (nativeCompatMode) "开" else "关"}")
            append(" | decoder=$currentVideoDecoderName")
            append(" | mime=$currentVideoMimeType")
            append(" | format=$currentVideoFormatLabel")
            append(" | dropped=$totalDroppedVideoFrames")
        }
        return diagnostics.panelItems(summary)
    }

    private fun buildVideoFormatLabel(format: Format): String {
        val width = format.width.takeIf { it > 0 }?.toString() ?: "?"
        val height = format.height.takeIf { it > 0 }?.toString() ?: "?"
        val fps = format.frameRate.takeIf { it > 0f }?.let { String.format(Locale.US, "%.2f", it) } ?: "?"
        return "${width}x${height}@${fps}"
    }

    private fun playbackStateName(state: Int): String = when (state) {
        Player.STATE_IDLE -> "IDLE"
        Player.STATE_BUFFERING -> "BUFFERING"
        Player.STATE_READY -> "READY"
        Player.STATE_ENDED -> "ENDED"
        else -> "UNKNOWN($state)"
    }

    private fun activeOutputName(): String = activeOutputName(nativeRenderViewType)

    private fun getBottomButtonPresentation(action: BottomAction): BottomButtonPresentation {
        return buildBottomButtonPresentation(
            action = action,
            isPlaying = playerController.isPlaying,
            isFavoriteCurrent = isFavoriteCurrent,
            danmakuHidden = danmakuState.hidden,
            currentQualityName = currentQualityName,
            lineIndex = lineIndex,
            fitLabels = fitLabels,
            fitIndex = fitIndex,
            materialIconTypeface = materialIconTypeface,
            customIconTypeface = customIconTypeface,
        )
    }

    private fun loadTypeface(assetPath: String): Typeface? {
        return loadNativeLiveTypeface(assetPath)
    }

    private fun logPlayerSnapshot(reason: String) {
        val exo = playerController.player
        if (exo == null) {
            appendDiagnostic(reason, "player=null")
            return
        }
        appendDiagnostic(
            reason,
            "state=${playbackStateName(exo.playbackState)}, isPlaying=${exo.isPlaying}, playWhenReady=${exo.playWhenReady}, pos=${exo.currentPosition}, buffered=${exo.bufferedPosition}, bufferedPct=${exo.bufferedPercentage}, decoder=$currentVideoDecoderName, mime=$currentVideoMimeType, dropped=$totalDroppedVideoFrames, output=${activeOutputName()}"
        )
    }

    private fun appendDiagnostic(tag: String, message: String) {
        diagnostics.append(tag, message)
    }

    private fun copyDiagnosticsToClipboard() {
        val text = diagnosticPanelItems().joinToString(separator = "\n")
        copyTextToClipboard("native_player_diagnostics", text)
        showToast("已复制最近诊断信息")
    }

    private fun copyTextToClipboard(label: String, text: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager
        if (clipboard == null) {
            showToast("当前设备不支持剪贴板")
            return
        }
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
    }

    private fun activeVideoView(): View = if (nativeRenderViewType == 1) texturePlayerView else surfaceView

    private fun updateVideoOutputView() {
        if (!::playerController.isInitialized) return
        playerController.updateVideoOutputView()
    }

    private fun releasePlayer(resetVideoState: Boolean) {
        if (::playerController.isInitialized) {
            playerController.releasePlayer(resetVideoState)
        }
        if (resetVideoState) {
            videoAspectRatio = 16f / 9f
            videoContentWidth = 16
            videoContentHeight = 9
            applyVideoFit()
        }
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun Int.dp(): Int = nativeLiveDp(this)
    private fun Double.formatValue(): String {
        return formatNativeLiveValue()
    }

    override fun onStop() {
        if (isFinishing) {
            releasePlayer(resetVideoState = true)
            if (instance == this) {
                instance = null
            }
        }
        super.onStop()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        pendingCloseRunnable = null
        releasePlayer(resetVideoState = true)
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }
}
