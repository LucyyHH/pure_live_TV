package com.mystyle.purelive.live

import android.app.Activity
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerView

@UnstableApi
class NativeLivePlayerController(
    private val activity: Activity,
    private val surfaceView: SurfaceView,
    private val texturePlayerView: PlayerView,
    private val renderConfigProvider: () -> NativeRenderConfig,
    private val currentUrlProvider: () -> String,
    private val currentHeadersProvider: () -> Map<String, String>,
    private val appendDiagnostic: (String, String) -> Unit,
    private val onVideoSizeChanged: (VideoSize) -> Unit,
    private val onPlaybackStateChanged: (Int) -> Unit,
    private val onIsPlayingChanged: (Boolean) -> Unit,
    private val onPlayWhenReadyChanged: (Boolean, Int) -> Unit,
    private val onPlayerError: (PlaybackException) -> Unit,
    private val onVideoInputFormatChanged: (Format, DecoderReuseEvaluation?) -> Unit,
    private val onVideoDecoderInitialized: (String, Long, Long) -> Unit,
    private val onRenderedFirstFrame: (Any, Long) -> Unit,
    private val onDroppedVideoFrames: (Int, Long) -> Unit,
    private val onVideoCodecError: (Exception) -> Unit,
) {
    var player: ExoPlayer? = null
        private set

    val isPlaying: Boolean
        get() = player?.isPlaying == true

    fun createPlayer() {
        releasePlayer(resetVideoState = false)
        updateVideoOutputView()
        val renderersFactory = buildRenderersFactory()
        val trackSelector = DefaultTrackSelector(activity)
        player = ExoPlayer.Builder(activity, renderersFactory)
            .setLoadControl(buildLoadControl())
            .setTrackSelector(trackSelector)
            .build().also { exo ->
                val config = renderConfigProvider()
                exo.setAudioAttributes(buildAudioAttributes(), true)
                appendDiagnostic(
                    "playerCreate",
                    "output=${activeOutputName(config.viewType)}, preferSoftware=${config.preferSoftwareDecoder}, compat=${config.compatMode}"
                )
                attachVideoOutput(exo)
                exo.addListener(buildPlayerListener())
                exo.addAnalyticsListener(buildAnalyticsListener())
            }
    }

    fun startPlayback(stopFirst: Boolean = false) {
        val currentUrl = currentUrlProvider()
        if (currentUrl.isBlank()) return
        if (player == null) {
            createPlayer()
        }
        val currentHeaders = currentHeadersProvider()
        val httpFactory = DefaultHttpDataSource.Factory().apply {
            setConnectTimeoutMs(15000)
            setReadTimeoutMs(15000)
            if (currentHeaders.isNotEmpty()) setDefaultRequestProperties(currentHeaders)
        }
        player?.run {
            if (stopFirst) stop()
            setMediaSource(DefaultMediaSourceFactory(httpFactory).createMediaSource(MediaItem.fromUri(currentUrl)))
            appendDiagnostic(
                "startPlayback",
                "stopFirst=$stopFirst, url=${currentUrl.take(160)}, headers=${currentHeaders.keys.joinToString(",")}"
            )
            prepare()
            play()
        }
    }

    fun togglePlayPause() {
        player?.let { if (it.isPlaying) it.pause() else it.play() }
    }

    fun updateVideoOutputView() {
        val viewType = renderConfigProvider().viewType
        surfaceView.visibility = if (viewType == 0) View.VISIBLE else View.GONE
        texturePlayerView.visibility = if (viewType == 1) View.VISIBLE else View.GONE
    }

    fun releasePlayer(resetVideoState: Boolean) {
        texturePlayerView.player = null
        player?.let { exo ->
            kotlin.runCatching {
                exo.clearVideoSurfaceView(surfaceView)
                exo.stop()
                exo.clearMediaItems()
                exo.release()
            }
        }
        appendDiagnostic("releasePlayer", "resetVideoState=$resetVideoState")
        player = null
    }

    private fun buildLoadControl(): DefaultLoadControl {
        return DefaultLoadControl.Builder()
            .setBufferDurationsMs(5000, 15000, 1000, 2000)
            .setTargetBufferBytes(DefaultLoadControl.DEFAULT_TARGET_BUFFER_BYTES)
            .setBackBuffer(0, true)
            .build()
    }

    private fun buildRenderersFactory(): DefaultRenderersFactory {
        return DefaultRenderersFactory(activity)
            .setEnableDecoderFallback(renderConfigProvider().compatMode)
            .apply {
                setMediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
                    val decoderInfos = MediaCodecSelector.DEFAULT.getDecoderInfos(
                        mimeType,
                        requiresSecureDecoder,
                        requiresTunnelingDecoder
                    )
                    selectPreferredDecoderInfos(decoderInfos)
                }
            }
    }

    private fun buildAudioAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
    }

    private fun attachVideoOutput(exo: ExoPlayer) {
        if (renderConfigProvider().viewType == 1) {
            texturePlayerView.player = exo
        } else {
            texturePlayerView.player = null
            exo.setVideoSurfaceView(surfaceView)
        }
    }

    private fun buildPlayerListener(): Player.Listener {
        return object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                onVideoSizeChanged.invoke(videoSize)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                onPlaybackStateChanged.invoke(playbackState)
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                onIsPlayingChanged.invoke(isPlaying)
            }

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                onPlayWhenReadyChanged.invoke(playWhenReady, reason)
            }

            override fun onPlayerError(error: PlaybackException) {
                onPlayerError.invoke(error)
            }
        }
    }

    private fun buildAnalyticsListener(): AnalyticsListener {
        return object : AnalyticsListener {
            override fun onVideoInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: DecoderReuseEvaluation?,
            ) {
                onVideoInputFormatChanged.invoke(format, decoderReuseEvaluation)
            }

            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderName: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                onVideoDecoderInitialized.invoke(
                    decoderName,
                    initializedTimestampMs,
                    initializationDurationMs,
                )
            }

            override fun onRenderedFirstFrame(
                eventTime: AnalyticsListener.EventTime,
                output: Any,
                renderTimeMs: Long,
            ) {
                onRenderedFirstFrame.invoke(output, renderTimeMs)
            }

            override fun onDroppedVideoFrames(
                eventTime: AnalyticsListener.EventTime,
                droppedFrames: Int,
                elapsedMs: Long,
            ) {
                onDroppedVideoFrames.invoke(droppedFrames, elapsedMs)
            }

            override fun onVideoCodecError(
                eventTime: AnalyticsListener.EventTime,
                videoCodecError: Exception,
            ) {
                onVideoCodecError.invoke(videoCodecError)
            }
        }
    }

    private fun selectPreferredDecoderInfos(
        decoderInfos: List<MediaCodecInfo>,
    ): List<MediaCodecInfo> {
        if (decoderInfos.isEmpty()) {
            return decoderInfos
        }
        if (renderConfigProvider().preferSoftwareDecoder) {
            val softwareDecoders = decoderInfos.filter { it.softwareOnly }
            return if (softwareDecoders.isNotEmpty()) softwareDecoders else decoderInfos
        }
        return decoderInfos
    }
}
