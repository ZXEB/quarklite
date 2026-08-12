import 'dart:convert';
import 'dart:io';

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

  /// 确保引擎已启动（未启动时自动拉起），供添加下载任务前调用
  static Future<GopeedClient> ensureStarted() async {
    if (!_started) {
      await start();
    }
    return client;
  }

  /// 启动引擎。带自愈重试：
  /// 1. 先停掉可能残留的旧实例（Dart 隔离区重建后旧引擎仍持有数据库锁）
  /// 2. 失败时清理可能损坏的数据库目录再重试
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
    String lastError = '';
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        try {
          await _channel.invokeMethod('stop');
        } catch (_) {
          // 无残留实例时忽略
        }
        await Future.delayed(const Duration(milliseconds: 200));
        final port = await _channel.invokeMethod<int>('start', {
          'cfg': jsonEncode(cfg),
        });
        if (port == null || port <= 0) {
          throw Exception('引擎返回无效端口');
        }
        _client = GopeedClient('http://127.0.0.1:$port');
        _started = true;
        return;
      } catch (e) {
        lastError = e.toString();
        // 前两次失败后清理损坏的任务数据库再重试（会丢失任务记录但保证引擎可用）
        if (attempt == 1) {
          try {
            final dir = Directory(storageDir);
            if (dir.existsSync()) {
              dir.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
    }
    _client = null;
    _started = false;
    throw Exception('下载引擎启动失败: $lastError');
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
