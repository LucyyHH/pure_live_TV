import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';

typedef NativeLiveMethodHandler =
    Future<void> Function(String method, Map<dynamic, dynamic> arguments);

abstract final class NativeLiveChannel {
  static const name = 'pure_live/native_live';
}

abstract final class NativeLiveMethod {
  static const start = 'startNativeLive';
  static const update = 'updateNativeLive';
  static const syncUi = 'syncNativeLiveUi';
  static const sendDanmaku = 'sendDanmaku';
  static const showLoading = 'showLoading';
  static const hideLoading = 'hideLoading';
  static const close = 'closeNativeLive';
  static const requestRefresh = 'onRequestRefresh';
  static const requestQualityChange = 'onRequestQualityChange';
  static const requestLineChange = 'onRequestLineChange';
  static const requestChannelSwitch = 'onRequestChannelSwitch';
  static const toggleFavorite = 'onToggleFavorite';
  static const togglePlaylistFavorite = 'onTogglePlaylistFavorite';
  static const selectPlaylist = 'onSelectPlaylist';
  static const cycleVideoFit = 'onCycleVideoFit';
  static const danmakuSettingChange = 'onDanmakuSettingChange';
  static const playbackError = 'onPlaybackError';
  static const activityFinished = 'onActivityFinished';
}

class NativeLiveBridge {
  NativeLiveBridge._();

  static final NativeLiveBridge instance = NativeLiveBridge._();
  static const MethodChannel _channel = MethodChannel(NativeLiveChannel.name);

  void bindHandler(NativeLiveMethodHandler handler) {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map
          ? call.arguments as Map<dynamic, dynamic>
          : const <dynamic, dynamic>{};
      await handler(call.method, args);
    });
  }

  void unbindHandler() {
    _channel.setMethodCallHandler(null);
  }

  Future<void> start(Map<String, dynamic> payload) =>
      _invokePayload(NativeLiveMethod.start, payload);

  Future<void> update(Map<String, dynamic> payload) =>
      _invokePayload(NativeLiveMethod.update, payload);

  Future<void> syncUi(Map<String, dynamic> payload) =>
      _invokePayload(NativeLiveMethod.syncUi, payload);

  Future<void> sendDanmaku(LiveMessage msg) async {
    final color = msg.color;
    await _channel.invokeMethod(NativeLiveMethod.sendDanmaku, {
      'text': msg.message,
      'color': 0xFF000000 | (color.r << 16) | (color.g << 8) | color.b,
    });
  }

  Future<void> showLoading() =>
      _channel.invokeMethod(NativeLiveMethod.showLoading);

  Future<void> hideLoading() =>
      _channel.invokeMethod(NativeLiveMethod.hideLoading);

  Future<void> close() => _channel.invokeMethod(NativeLiveMethod.close);

  Future<void> _invokePayload(String method, Map<String, dynamic> payload) {
    return _channel.invokeMethod(method, {'data': jsonEncode(payload)});
  }
}
