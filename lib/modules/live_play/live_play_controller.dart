import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/app/app_focus_node.dart';
import 'package:pure_live/core/site/huya_site.dart';
import 'package:pure_live/plugins/emoji_manager.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/modules/live_play/widgets/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/controller/video_danmaku.dart';

class LivePlayController extends StateController {
  LivePlayController({required this.room, required this.site});
  final String site;

  late Site currentSite;

  LiveDanmaku? liveDanmaku;
  int _playGeneration = 0;
  LiveRoom? _requestedRoom;
  bool _closing = false;
  Future<void>? _disposeFuture;
  // The native player is shared even between separate live-room routes.
  static Future<void> _pendingPlayerCleanup = Future<void>.value();
  bool _isCurrent(int generation) =>
      !_closing &&
      generation == _playGeneration &&
      _requestedRoom == currentPlayRoom.value;

  final settings = Get.find<SettingsService>();

  // 控制唯一子组件
  VideoController? videoController;

  final playerKey = GlobalKey();

  final danmakuViewKey = GlobalKey();

  final LiveRoom room;

  Rx<LiveRoom?> detail = Rx<LiveRoom?>(LiveRoom());

  final success = false.obs;

  var liveStatus = false.obs;

  Map<String, List<String>> liveStream = {};

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  final currentQuality = 0.obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  /// 当前线路
  final currentLineIndex = 0.obs;

  int lastExitTime = 0;

  final FocusNode focusNode = AppFocusNode()..isFoucsed.value = true;

  /// 双击退出Flag
  bool doubleClickExit = false;

  /// 双击退出Timer
  Timer? doubleClickTimer;
  // 0 代表向上 1 代表向下
  int isNextOrPrev = 0;

  int _currentTimeStamp = 0;
  // 当前直播间信息 下一个频道或者上一个
  var currentPlayRoom = LiveRoom().obs;

  var currentChannelIndex = 0.obs;

  var lastChannelIndex = 0.obs;

  Timer? channelTimer;

  Timer? loadRefreshRoomTimer;
  // 切换线路会添加到这个数组里面
  var isLastLine = false.obs;

  var isFirstLoad = true.obs;

  @override
  void onClose() {
    _closing = true;
    loadRefreshRoomTimer?.cancel();
    channelTimer?.cancel();
    doubleClickTimer?.cancel();
    focusNode.dispose();
    unawaited(
      disPoserPlayer().catchError((Object error) {
        log(error.toString(), name: "disPoserPlayer");
      }),
    );
    super.onClose();
  }

  @override
  void dispose() {
    channelTimer?.cancel();
    doubleClickTimer?.cancel();
    super.dispose();
  }

  Future<bool> onBackPressed() async {
    final vc = videoController;
    if (vc == null) {
      _closing = true;
      await disPoserPlayer().catchError((Object error) {
        log(error.toString(), name: "disPoserPlayer");
      });
      return true;
    }
    // 1. 识别当前哪个面板处于打开状态

    final simplePanels = [
      vc.showSettting,
      vc.showQualityPanel,
      vc.showPlayListPanel,
      vc.showLinePanel,
      vc.showQrCodePanel,
    ];

    // 2. 检查普通面板
    for (var panel in simplePanels) {
      if (panel.value) {
        panel.value = false;
        vc.focusNode.requestFocus();
        return false;
      }
    }

    // 3. 检查特殊逻辑面板：控制器面板通常涉及计时器
    if (vc.showController.value) {
      vc.disableController();
      vc.focusNode.requestFocus();
      return false;
    }

    // 4. 没有任何面板，执行销毁并退出
    _closing = true;
    channelTimer?.cancel();
    await disPoserPlayer().catchError((Object error) {
      log(error.toString(), name: "disPoserPlayer");
    });
    return true;
  }

  @override
  void onInit() {
    currentPlayRoom.value = room;
    onInitPlayerState(
      reloadDataType: detail.value!.platform == Sites.bilibiliSite
          ? ReloadDataType.changeLine
          : ReloadDataType.refreash,
    );
    _preloadEmoji();
    super.onInit();
  }

  Future<LiveRoom> onInitPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    int currentQuality = 0,
    bool isReCalculate = true,
  }) async {
    final generation = ++_playGeneration;
    final requestedRoom = currentPlayRoom.value;
    _requestedRoom = requestedRoom;
    try {
      await _disposeCurrentPlayer();
      await _pendingPlayerCleanup;
      if (!_isCurrent(generation)) return requestedRoom;
      _disposeFuture = null;
      currentSite = Sites.of(currentPlayRoom.value.platform!);
      liveDanmaku = currentSite.liveSite.getDanmaku();
      var liveRoom = await currentSite.liveSite.getRoomDetail(
        roomId: currentPlayRoom.value.roomId!,
        platform: currentPlayRoom.value.platform!,
      );
      if (!_isCurrent(generation)) return liveRoom;
      bool isIptv = currentSite.id == Sites.iptvSite;
      if (isIptv) {
        liveRoom = liveRoom.copyWith(
          title: requestedRoom.title,
          nick: requestedRoom.nick,
        );
        resetGlobalListState();
        settings.addRoomToHistory(requestedRoom);
        detail.value = null;
        detail.value = liveRoom;
        await _initIptvPlayer(generation);
        return detail.value!;
      }

      handleCurrentLineAndQuality(
        reloadDataType: reloadDataType,
        line: line,
        quality: currentQuality,
        isReCalculate: isReCalculate,
      );
      detail.value = liveRoom;
      resetGlobalListState();
      if (liveRoom.liveStatus == LiveStatus.unknown) {
        ToastUtil.show("获取直播间信息失败,请按确定建重新获取");
        return liveRoom;
      }

      liveStatus.value = liveRoom.status! || liveRoom.isRecord!;
      if (liveStatus.value) {
        await getPlayQualites(generation);
        if (!_isCurrent(generation)) return liveRoom;
        if (currentPlayRoom.value.platform == Sites.iptvSite) {
          settings.addRoomToHistory(currentPlayRoom.value);
        } else {
          settings.addRoomToHistory(liveRoom);
        }
        // start danmaku server
        List<String> except = ['kuaishou', 'iptv', 'cc'];
        if (except.indexWhere((element) => element == liveRoom.platform!) ==
            -1) {
          initDanmau(); // 仅初始化一次
          liveDanmaku?.start(liveRoom.danmakuData);
        }
      } else {
        success.value = false;
        ToastUtil.show("当前主播未开播或主播已下播");
        restoryQualityAndLines();
      }

      return liveRoom;
    } catch (error, stack) {
      if (_isCurrent(generation)) {
        _disposeFuture = null;
        success.value = false;
        log("Unable to load live room", error: error, stackTrace: stack);
        ToastUtil.show("无法读取直播间信息，请重试");
      }
      return requestedRoom;
    }
  }

  // ================= IPTV =================
  Future<void> _initIptvPlayer(int generation) async {
    final link = detail.value?.link;
    log(' IPTV link: ${detail.value?.link}');
    if (link == null || link.isEmpty) {
      ToastUtil.show('IPTV link为空,请重新获取');
      return;
    }
    qualites = RxList([LivePlayQuality(quality: '原画')]);
    currentQuality.value = 0;
    currentLineIndex.value = 0;
    playUrls.value = [link];
    await setPlayer(generation);
    if (_isCurrent(generation)) await liveDanmaku?.stop();
  }

  void resetGlobalListState() {
    var index = settings.currentPlayList.indexWhere(
      (element) =>
          element.roomId == currentPlayRoom.value.roomId &&
          element.platform == currentPlayRoom.value.platform,
    );
    currentChannelIndex.value = index > -1 ? index : 0;
    settings.currentPlayListNodeIndex.value = currentChannelIndex.value;
  }

  bool calcIsLastLine(ReloadDataType reloadDataType, int line) {
    var lastLine = line + 1;
    if (playUrls.isEmpty) {
      return true;
    }
    if (playUrls.length == 1) {
      return true;
    }
    if (lastLine == playUrls.length - 1) {
      return true;
    }
    return false;
  }

  Future<void> disPoserPlayer() {
    _playGeneration++;
    return _disposeCurrentPlayer();
  }

  Future<void> _disposeCurrentPlayer() {
    if (_disposeFuture != null) return _disposeFuture!;
    final oldController = videoController;
    final oldDanmaku = liveDanmaku;
    videoController = null;
    liveDanmaku = null;
    success.value = false;
    // Keep quality selection on line/quality reloads; channel changes reset it.
    oldDanmaku?.onMessage = null;
    oldDanmaku?.onClose = null;
    oldDanmaku?.onReady = null;
    if (oldController == null && oldDanmaku == null) {
      return _pendingPlayerCleanup;
    }
    final cleanup = _pendingPlayerCleanup.then((_) async {
      await Future.wait<void>([
        if (oldDanmaku != null)
          oldDanmaku
              .stop()
              .then<void>((_) {})
              .timeout(const Duration(seconds: 2)),
        if (oldController != null) oldController.destroy(),
        if (oldController != null)
          GlobalPlayerService.instance.playerManager.close(),
      ]);
    });
    _disposeFuture = cleanup;
    // Retain a handled barrier so a later route cannot race this cleanup.
    _pendingPlayerCleanup = cleanup.catchError((
      Object error,
      StackTrace stack,
    ) {
      log('Player cleanup failed', error: error, stackTrace: stack);
    });
    return cleanup;
  }

  void handleCurrentLineAndQuality({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    bool isReCalculate = true,
    int quality = 0,
  }) {
    if (reloadDataType == ReloadDataType.changeLine && isReCalculate) {
      currentLineIndex.value = line;
    } else if (reloadDataType == ReloadDataType.changeQuality) {
      currentQuality.value = quality;
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku?.onMessage = null;
    liveDanmaku?.onClose = null;
    liveDanmaku?.onReady = null;
    // 移除系统消息添加逻辑（原messages相关）
    liveDanmaku?.onMessage = (msg) {
      if (msg.type == LiveMessageType.chat) {
        if (settings.shieldList.every(
          (element) => !msg.message.contains(element),
        )) {
          // 保留弹幕发送到播放器的核心功能，移除messages添加
          if (videoController != null) {
            videoController?.sendDanmakuMessage(msg);
          }
        }
      }
    };
    liveDanmaku?.onClose = (msg) {};
    liveDanmaku?.onReady = () {};
  }

  Future<void> _preloadEmoji() async {
    EmojiManager().clearCache();
    await EmojiManager().preload(site);
  }

  /// 初始化播放器
  Future<void> getPlayQualites(int generation) async {
    try {
      var playQualites = await currentSite.liveSite.getPlayQualites(
        detail: detail.value!,
      );
      if (!_isCurrent(generation)) return;
      if (playQualites.isEmpty) {
        ToastUtil.show("无法读取视频信息,请按确定键重新获取");
        success.value = false;
        return;
      }
      qualites.value = playQualites;
      // 第一次加载 使用系统默认线路
      if (isFirstLoad.value) {
        String userPrefer = settings.preferResolution.value;
        List<String> availableQualities = playQualites
            .map((e) => e.quality)
            .toList();
        int matchedIndex = availableQualities.indexOf(userPrefer);
        // 尝试直接匹配用户偏好的分辨率
        if (matchedIndex != -1) {
          currentQuality.value = matchedIndex;
          isFirstLoad.value = false;
          await getPlayUrl(generation);
          return;
        }
        // 未匹配到，根据用户偏好的"级别"选择最接近的清晰度
        List<String> systemResolutions = settings.resolutionsList;
        int preferLevel = systemResolutions.indexOf(userPrefer);
        double preferRatio = preferLevel / (systemResolutions.length - 1);
        int targetIndex = (preferRatio * (availableQualities.length - 1))
            .round();
        // 确保索引在有效范围内
        targetIndex = targetIndex.clamp(0, availableQualities.length - 1);
        currentQuality.value = targetIndex;
        isFirstLoad.value = false;
      }

      await getPlayUrl(generation);
    } catch (e) {
      if (!_isCurrent(generation)) return;
      ToastUtil.show("无法读取视频信息,请按确定键重新获取");
      success.value = false;
    }
  }

  void restoryQualityAndLines() {
    playUrls.value = [];
    currentLineIndex.value = 0;
    qualites.value = [];
    currentQuality.value = 0;
  }

  Future<void> getPlayUrl(int generation) async {
    var playUrl = await currentSite.liveSite.getPlayUrls(
      detail: detail.value!,
      quality: qualites[currentQuality.value],
    );
    if (!_isCurrent(generation)) return;
    if (playUrl.isEmpty) {
      ToastUtil.show("无法读取播放地址,请按确定键重新获取");
      success.value = false;
      return;
    }
    playUrls.value = playUrl;
    await setPlayer(generation);
  }

  Future<void> setPlayer(int generation) async {
    Map<String, String> headers = {};
    if (currentSite.id == 'bilibili') {
      headers = {
        "cookie": settings.bilibiliCookie.value,
        "authority": "api.bilibili.com",
        "accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "accept-language": "zh-CN,zh;q=0.9",
        "cache-control": "no-cache",
        "dnt": "1",
        "pragma": "no-cache",
        "sec-ch-ua":
            '"Not A(Brand";v="99", "Google Chrome";v="121", "Chromium";v="121"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"macOS"',
        "sec-fetch-dest": "document",
        "sec-fetch-mode": "navigate",
        "sec-fetch-site": "none",
        "sec-fetch-user": "?1",
        "upgrade-insecure-requests": "1",
        "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "referer": "https://live.bilibili.com",
      };
    } else if (currentSite.id == 'huya') {
      var ua = await HuyaSite().getHuYaUA();
      headers = {
        "user-agent": ua,
        "origin": "https://www.huya.com",
        "cookie": settings.huyaCookie.value,
      };
    } else if (currentSite.id == Sites.iptvSite) {
      if (settings.customIptvUserAgent.value.isNotEmpty) {
        headers = {"user-agent": settings.customIptvUserAgent.value};
      }
    }
    if (!_isCurrent(generation)) return;
    videoController = VideoController(
      playerKey: playerKey,
      room: detail.value!,
      playUrls: playUrls.value,
      datasourceType: 'network',
      datasource: playUrls.value[currentLineIndex.value],
      autoPlay: true,
      headers: headers,
      qualiteName: qualites[currentQuality.value].quality,
      qualites: qualites.value,
      currentLineIndex: currentLineIndex.value,
      currentQuality: currentQuality.value,
    );
    success.value = true;
  }

  void nextChannel() {
    //读取正在直播的频道
    var liveChannels = settings.currentPlayList;
    log(liveChannels.length.toString());
    if (liveChannels.isEmpty) {
      ToastUtil.show("没有正在直播的频道");
      return;
    }
    var index = settings.currentPlayListNodeIndex.value;
    index += 1;
    if (index >= liveChannels.length) {
      index = 0;
    }
    var nextChannel = liveChannels[index];
    settings.currentPlayListNodeIndex.value = index;
    currentChannelIndex.value = index;
    isFirstLoad.value = true;
    currentPlayRoom.value = nextChannel;
    isNextOrPrev = 1;
    channelTimer?.cancel();
    channelTimer = Timer(const Duration(seconds: 1), () {
      lastChannelIndex.value = currentChannelIndex.value;
      EmojiManager().preload(Sites.of(nextChannel.platform!).id);
      resetRoom();
    });
  }

  void prevChannel() {
    //读取正在直播的频道
    _currentTimeStamp = DateTime.now().millisecondsSinceEpoch;
    var liveChannels = settings.currentPlayList;
    isFirstLoad.value = true;
    if (liveChannels.isEmpty) {
      ToastUtil.show("没有正在直播的频道");
      return;
    }
    var index = settings.currentPlayListNodeIndex.value;
    index -= 1;
    if (index < 0) {
      index = liveChannels.length - 1;
    }
    settings.currentPlayListNodeIndex.value = index;
    currentChannelIndex.value = index;

    var nextChannel = liveChannels[index];
    currentPlayRoom.value = nextChannel;
    isNextOrPrev = 0;
    channelTimer?.cancel();
    channelTimer = Timer(const Duration(seconds: 1), () {
      lastChannelIndex.value = currentChannelIndex.value;
      EmojiManager().preload(Sites.of(nextChannel.platform!).id);
      resetRoom();
    });
  }

  void playFavoriteChannel() {
    //读取正在直播的频道
    _currentTimeStamp = DateTime.now().millisecondsSinceEpoch;
    var liveChannels = settings.currentPlayList;
    if (liveChannels.isEmpty) {
      ToastUtil.show("没有正在直播的频道");
      return;
    }
    var index = settings.currentPlayListNodeIndex.value;
    currentChannelIndex.value = index;
    var nextChannel = liveChannels[index];
    currentPlayRoom.value = nextChannel;
    isNextOrPrev = 0;
    isFirstLoad.value = true;
    channelTimer?.cancel();
    channelTimer = Timer(const Duration(seconds: 1), () {
      lastChannelIndex.value = currentChannelIndex.value;
      EmojiManager().preload(Sites.of(nextChannel.platform!).id);
      resetRoom();
    });
  }

  Future<void> resetRoom() async {
    if (_closing) return;
    isFirstLoad.value = true;
    restoryQualityAndLines();
    await onInitPlayerState();
  }

  void onKeyEvent(KeyEvent key) {
    if (key is KeyUpEvent) {
      return;
    }
    throttle(() {
      handleKeyEvent(key);
    }, 100);
  }

  void handleKeyEvent(KeyEvent key) {
    // 点击上下键切换播放线路
    if (key.logicalKey == LogicalKeyboardKey.arrowUp) {
      prevChannel();
    } else if (key.logicalKey == LogicalKeyboardKey.arrowDown) {
      nextChannel();
    }
    // 点击左右键切换播放线路
    if (key.logicalKey == LogicalKeyboardKey.arrowLeft) {
      prevChannel();
    } else if (key.logicalKey == LogicalKeyboardKey.arrowRight) {
      nextChannel();
    }
    // 点击OK、Enter、Select键时刷新直播间
    if (key.logicalKey == LogicalKeyboardKey.select ||
        key.logicalKey == LogicalKeyboardKey.enter ||
        key.logicalKey == LogicalKeyboardKey.space ||
        key.logicalKey == LogicalKeyboardKey.controlRight ||
        key.logicalKey == LogicalKeyboardKey.controlLeft) {
      restoryQualityAndLines();
      resetRoom();
    }
  }

  void throttle(Function func, [int delay = 1000]) {
    var now = DateTime.now().millisecondsSinceEpoch;
    if (now - _currentTimeStamp > delay) {
      _currentTimeStamp = now;
      func.call();
    }
  }
}
