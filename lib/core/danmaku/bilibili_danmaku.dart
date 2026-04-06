import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:brotli/brotli.dart';
import '../common/binary_writer.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

/// Isolate-safe: decompress + decode + extract chat/superchat from a Bilibili
/// WebSocket frame.  Returns lightweight maps so we never send non-sendable
/// objects across the isolate boundary.
List<Map<String, dynamic>> _parseBiliMessages(List<int> data) {
  final results = <Map<String, dynamic>>[];
  try {
    final protocolVersion = _readInt(data, 6, 2);
    var body = data.sublist(16);

    if (protocolVersion == 2) {
      body = zlib.decode(body);
    } else if (protocolVersion == 3) {
      body = brotli.decode(body);
    }

    final text = utf8.decode(body, allowMalformed: true);
    final group = text.split(RegExp(r"[\x00-\x1f]+", unicode: true, multiLine: true));

    for (final item in group) {
      if (item.length <= 2 || !item.startsWith('{')) continue;
      try {
        final obj = json.decode(item);
        final cmd = obj["cmd"]?.toString() ?? '';
        if (cmd.contains("DANMU_MSG")) {
          final info = obj["info"];
          if (info != null && (info as List).isNotEmpty) {
            final message = info[1].toString();
            final color = (info[0][3] is int) ? info[0][3] as int : 0;
            if (info[2] != null && (info[2] as List).isNotEmpty) {
              results.add({
                't': 'c',
                'u': info[2][1].toString(),
                'm': message,
                'clr': color,
              });
            }
          }
        } else if (cmd == "SUPER_CHAT_MESSAGE" && obj["data"] != null) {
          final d = obj["data"];
          results.add({
            't': 'sc',
            'bgBtm': d["background_bottom_color"].toString(),
            'bg': d["background_color"].toString(),
            'end': d["end_time"] as int,
            'face': "${d["user_info"]["face"]}@200w.jpg",
            'msg': d["message"].toString(),
            'price': d["price"] as int,
            'start': d["start_time"] as int,
            'uname': d["user_info"]["uname"].toString(),
          });
        }
      } catch (_) {}
    }
  } catch (_) {}
  return results;
}

int _readInt(List<int> buffer, int start, int len) {
  final bytes = Uint8List.fromList(buffer.sublist(start, start + len));
  final data = ByteData.view(bytes.buffer);
  if (len == 1) return data.getUint8(0);
  if (len == 2) return data.getInt16(0, Endian.big);
  if (len == 4) return data.getInt32(0, Endian.big);
  if (len == 8) return data.getInt64(0, Endian.big);
  return 0;
}

class BiliBiliDanmakuArgs {
  final int roomId;
  final String token;
  final String buvid;
  final String serverHost;
  final int uid;
  final String cookie;
  BiliBiliDanmakuArgs({
    required this.roomId,
    required this.token,
    required this.serverHost,
    required this.buvid,
    required this.uid,
    required this.cookie,
  });
  @override
  String toString() {
    return json.encode({
      "roomId": roomId,
      "token": token,
      "serverHost": serverHost,
      "buvid": buvid,
      "uid": uid,
      "cookie": cookie,
    });
  }
}

class BiliBiliDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 60 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  WebScoketUtils? webScoketUtils;
  late BiliBiliDanmakuArgs danmakuArgs;
  @override
  Future start(dynamic args) async {
    danmakuArgs = args as BiliBiliDanmakuArgs;
    webScoketUtils = WebScoketUtils(
      url: "wss://${args.serverHost}/sub",
      headers: args.cookie.isEmpty ? null : {"cookie": args.cookie},
      heartBeatTime: heartbeatTime,
      onMessage: (e) {
        decodeMessage(e);
      },
      onReady: () {
        onReady?.call();
        joinRoom(danmakuArgs);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        onClose?.call("服务器连接失败$e");
      },
    );
    webScoketUtils?.connect();
  }

  void joinRoom(BiliBiliDanmakuArgs args) {
    var joinData = encodeData(
      json.encode({
        "uid": args.uid,
        "roomid": args.roomId,
        "protover": 3,
        "buvid": args.buvid,
        "platform": "web",
        "type": 2,
        "key": args.token,
      }),
      7,
    );
    webScoketUtils?.sendMessage(joinData);
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage(encodeData("", 2));
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
  }

  List<int> encodeData(String msg, int action) {
    var data = utf8.encode(msg);
    var length = data.length + 16;
    var buffer = Uint8List(length);

    var writer = BinaryWriter([]);

    writer.writeInt(buffer.length, 4);
    writer.writeInt(16, 2);
    writer.writeInt(0, 2);
    writer.writeInt(action, 4);
    writer.writeInt(1, 4);
    writer.writeBytes(data);

    return writer.buffer;
  }

  void decodeMessage(List<int> data) async {
    try {
      final operation = _readInt(data, 8, 4);

      if (operation == 3) {
        final online = _readInt(data, 16, 4);
        onMessage?.call(
          LiveMessage(
            type: LiveMessageType.online,
            data: online,
            color: LiveMessageColor.white,
            message: "",
            userName: "",
          ),
        );
        return;
      }

      if (operation != 5) return;

      final parsed = await Isolate.run(() => _parseBiliMessages(data));

      for (final msg in parsed) {
        final type = msg['t'];
        if (type == 'c') {
          final color = msg['clr'] as int;
          onMessage?.call(LiveMessage(
            type: LiveMessageType.chat,
            userName: msg['u'] as String,
            message: msg['m'] as String,
            color: color == 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
          ));
        } else if (type == 'sc') {
          onMessage?.call(LiveMessage(
            type: LiveMessageType.superChat,
            userName: "SUPER_CHAT_MESSAGE",
            message: "SUPER_CHAT_MESSAGE",
            color: LiveMessageColor.white,
            data: LiveSuperChatMessage(
              backgroundBottomColor: msg['bgBtm'] as String,
              backgroundColor: msg['bg'] as String,
              endTime: DateTime.fromMillisecondsSinceEpoch((msg['end'] as int) * 1000),
              face: msg['face'] as String,
              message: msg['msg'] as String,
              price: msg['price'] as int,
              startTime: DateTime.fromMillisecondsSinceEpoch((msg['start'] as int) * 1000),
              userName: msg['uname'] as String,
            ),
          ));
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }
}
