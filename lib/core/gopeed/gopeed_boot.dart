import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'gopeed_client.dart';

class GopeedEngine {
  static const _channel = MethodChannel('quarklite.com/gopeed');

  static GopeedClient? _client;
  static bool _started = false;

  static GopeedClient get client {
    final c = _client;
    if (c == null) {
      throw Exception('下载引擎尚未启动');
    }
    return c;
  }

  static bool get started => _started;

  static Future<void> start() async {
    if (_started) return;
    final docs = await getApplicationDocumentsDirectory();
    final storageDir = '${docs.path}/gopeed';
    final cfg = {
      'network': 'tcp',
      'address': '127.0.0.1:0',
      'storage': 'bolt',
      'storageDir': storageDir,
      'refreshInterval': 350,
      'apiToken': '',
    };
    final port = await _channel.invokeMethod<int>('start', {
      'cfg': jsonEncode(cfg),
    });
    _client = GopeedClient('http://127.0.0.1:$port');
    _started = true;
  }

  static Future<void> stop() async {
    if (!_started) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {
      // 忽略停止失败
    }
    _client = null;
    _started = false;
  }
}
