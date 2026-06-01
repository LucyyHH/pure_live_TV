package com.mystyle.purelive

import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.mystyle.purelive.live.LivePlayActivity
import com.mystyle.purelive.live.NativeLiveContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private val mainHandler = Handler(Looper.getMainLooper())
        private var methodChannel: MethodChannel? = null

        fun dispatchFlutter(method: String, arguments: Map<String, Any?> = emptyMap()) {
            mainHandler.post {
                methodChannel?.invokeMethod(method, HashMap(arguments))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeLiveContract.CHANNEL
        )
        methodChannel?.setMethodCallHandler(::handleMethodCall)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            NativeLiveContract.METHOD_START -> handlePayloadMethod(call, result, ::startNativeLive)
            NativeLiveContract.METHOD_UPDATE -> handlePayloadMethod(call, result) { data ->
                withLiveActivity(
                    onUnavailable = { startNativeLive(data) },
                    onAvailable = { updatePlayUrl(data) }
                )
            }
            NativeLiveContract.METHOD_SYNC_UI -> handlePayloadMethod(call, result) { data ->
                withLiveActivity(onAvailable = { syncUi(data) })
            }
            NativeLiveContract.METHOD_SEND_DANMAKU -> {
                val text = call.argument<String>(NativeLiveContract.ARG_TEXT).orEmpty()
                val color = (call.argument<Number>(NativeLiveContract.ARG_COLOR))?.toInt()
                    ?: 0xFFFFFF
                withLiveActivity(onAvailable = { addDanmaku(text, color) })
                result.success(null)
            }
            NativeLiveContract.METHOD_SHOW_LOADING -> {
                withLiveActivity(onAvailable = { showNativeLoading() })
                result.success(null)
            }
            NativeLiveContract.METHOD_HIDE_LOADING -> {
                withLiveActivity(onAvailable = { hideNativeLoading() })
                result.success(null)
            }
            NativeLiveContract.METHOD_CLOSE -> {
                withLiveActivity(onAvailable = { closeActivity() })
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handlePayloadMethod(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (String) -> Unit,
    ) {
        val data = call.argument<String>(NativeLiveContract.EXTRA_DATA)
        if (data.isNullOrBlank()) {
            result.error("invalid_args", "Missing live payload", null)
            return
        }
        action(data)
        result.success(null)
    }

    private fun withLiveActivity(
        onUnavailable: (() -> Unit)? = null,
        onAvailable: LivePlayActivity.() -> Unit,
    ) {
        val activity = LivePlayActivity.instance
        if (activity == null || activity.isFinishing || activity.isDestroyed) {
            onUnavailable?.invoke()
            return
        }
        activity.onAvailable()
    }

    private fun startNativeLive(data: String) {
        withLiveActivity(
            onUnavailable = {
                val intent = Intent(this, LivePlayActivity::class.java).apply {
                    putExtra(NativeLiveContract.EXTRA_DATA, data)
                }
                startActivity(intent)
            },
            onAvailable = { reopenWithPayload(data) }
        )
    }
}
