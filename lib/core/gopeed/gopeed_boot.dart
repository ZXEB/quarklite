import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'gopeed_client.dart';

class GopeedEngine {
  static const _channel = MethodChannel('quarklite.com/gopeed');

  static GopeedClient? _client;
  static bool _started = false;
  static Process? _winProcess;
  static bool _winServerReady = false;
  static String _winDiag = '';

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
    if (!kIsWeb && Platform.isWindows) {
      await _startWindows();
      return;
    }
    await _startAndroid();
  }

  // ---------------- Android：原生 Libgopeed（MethodChannel） ----------------

  static Future<void> _startAndroid() async {
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

  // ---------------- Windows：gopeed.exe 子进程 + REST API ----------------

  static Future<void> _startWindows() async {
    if (_winProcess != null && _winServerReady) {
      _started = true;
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final storageDir = '${docs.path}/gopeed';
    final exe = _findGopeedExe();
    if (exe == null) {
      throw Exception('未找到 gopeed.exe，请确认程序目录完整');
    }
    _winDiag = '';
    String lastError = '';
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _stopWindowsProcess();
        await Future.delayed(const Duration(milliseconds: 200));
        // 端口 0 表示随机分配，解析 stdout 中的监听地址
        final process = await Process.start(exe, [
          '-A', '127.0.0.1',
          '-P', '0',
          '-T', '',
          '-d', storageDir,
        ]);
        _winProcess = process;
        // 确认进程存活：部分环境（杀软扫描等）进程启动后立即退出
        final exited = await Future.any([
          process.exitCode.then((code) {
            _winDiag = '引擎进程退出 code=$code';
            return true;
          }),
          Future.delayed(const Duration(milliseconds: 300), () => false),
        ]);
        if (exited) {
          throw Exception('引擎启动后立即退出');
        }
        final port = await _readServerPort(process);
        if (port == null || port <= 0) {
          throw Exception('引擎未正常启动: $_winDiag');
        }
        _client = GopeedClient('http://127.0.0.1:$port');
        _started = true;
        _winServerReady = true;
        // 进程异常退出时标记引擎失效；只清理当前进程的引用，避免误清新实例
        process.exitCode.then((code) {
          _winDiag = '引擎进程退出 code=$code';
          if (!identical(process, _winProcess)) return;
          _winServerReady = false;
          _started = false;
          _client = null;
        });
        // 持续消费输出，防止缓冲填满导致进程阻塞
        process.stdout.listen((_) {});
        process.stderr.listen((_) {});
        return;
      } catch (e) {
        lastError = e.toString();
        // 前两次失败后清理损坏的任务数据库再重试
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
    throw Exception('下载引擎启动失败: $lastError$_winDiag');
  }

  /// 查找 gopeed.exe：优先程序目录（打包产物目录），其次应用文档目录
  static String? _findGopeedExe() {
    final candidates = <String>[];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir/gopeed.exe');
    } catch (_) {}
    try {
      candidates.add('gopeed.exe');
    } catch (_) {}
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// 读取子进程 stdout 中的 "Server start success on http://127.0.0.1:port"
  static Future<int?> _readServerPort(Process process) async {
    final buffer = StringBuffer();
    final stderrBuf = StringBuffer();
    final completer = Completer<int?>();
    process.stdout.transform(utf8.decoder).listen((chunk) {
      buffer.write(chunk);
      if (buffer.length > 4096) {
        final tail = buffer.toString().substring(buffer.length - 2048);
        buffer.clear();
        buffer.write(tail);
      }
      final text = buffer.toString();
      final match =
          RegExp(r'Server start success on http://[^:]+:(\d+)').firstMatch(text);
      if (match != null && !completer.isCompleted) {
        completer.complete(int.tryParse(match.group(1)!));
      }
    });
    process.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBuf.write(chunk);
      if (stderrBuf.length > 4096) {
        final tail = stderrBuf.toString().substring(stderrBuf.length - 2048);
        stderrBuf.clear();
        stderrBuf.write(tail);
      }
    });
    // 首次启动可能被杀毒软件扫描，超时放宽到 30 秒
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        final tail = buffer.toString().trim();
        final err = stderrBuf.toString().trim();
        _winDiag = tail.isNotEmpty ? '输出: ${tail.split('\n').last}' : '';
        if (err.isNotEmpty) {
          _winDiag = '$_winDiag 错误输出: ${err.split('\n').last}';
        }
        completer.complete(null);
      }
    });
    return completer.future;
  }

  static Future<void> _stopWindowsProcess() async {
    final p = _winProcess;
    _winProcess = null;
    _winServerReady = false;
    if (p != null) {
      try {
        p.kill();
        await p.exitCode.timeout(const Duration(seconds: 2),
            onTimeout: () => -1);
      } catch (_) {
        // 忽略停止失败
      }
    }
  }

  static Future<void> stop() async {
    if (!_started) return;
    if (!kIsWeb && Platform.isWindows) {
      await _stopWindowsProcess();
    } else {
      try {
        await _channel.invokeMethod('stop');
      } catch (_) {
        // 忽略停止失败
      }
    }
    _client = null;
    _started = false;
  }
}
