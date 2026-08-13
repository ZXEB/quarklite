import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';
import 'gopeed_client.dart';

class GopeedEngine {
  static const _channel = MethodChannel('quarklite.com/gopeed');

  static GopeedClient? _client;
  static bool _started = false;
  static Process? _winProcess;
  static bool _winServerReady = false;
  static String _winDiag = '';

  /// 进行中的启动流程（并发调用共享同一次启动，避免互相杀掉对方刚拉起的引擎进程）
  static Future<void>? _startInFlight;
  /// 引擎进程意外退出后的自动重启防抖标志
  static bool _autoRestarting = false;

  /// 最近一次引擎启动失败的详细原因（供界面展示）
  static String? lastError;

  static GopeedClient get client {
    final c = _client;
    if (c == null) {
      throw Exception('下载引擎尚未启动');
    }
    return c;
  }

  static bool get started => _started;

  /// 确保引擎已启动（未启动时自动拉起），供添加下载任务前调用
  /// [wait] 为 true 时等待一次完整启动尝试（最多约 16 秒），失败立即报错；
  /// 为 false 时交给后台重试逻辑，调用方不等待
  static Future<GopeedClient> ensureStarted({bool wait = true}) async {
    if (!_started) {
      await start(retry: !wait);
    }
    return client;
  }

  /// 启动引擎。带自愈重试：
  /// 1. 先停掉可能残留的旧实例（Dart 隔离区重建后旧引擎仍持有数据库锁）
  /// 2. 失败时清理可能损坏的数据库目录再重试
  /// [retry] 为 false 时只尝试一次（保证快速失败，用于交互等待场景）
  /// 并发调用共享同一次启动，避免多个启动流程互相 taskkill 对方刚拉起的引擎进程。
  static Future<void> start({bool retry = true}) async {
    AppLogger.I.i('engine',
        'start 请求 retry=$retry started=$_started inFlight=${_startInFlight != null}');
    if (_started) return;
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final future = _doStart(retry: retry);
    _startInFlight = future;
    try {
      await future;
    } finally {
      _startInFlight = null;
    }
  }

  static Future<void> _doStart({required bool retry}) async {
    if (_started) return;
    if (!kIsWeb && Platform.isWindows) {
      await _startWindows(retry: retry);
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
    String lastError_ = '';
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
        lastError_ = e.toString();
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
    lastError = '下载引擎启动失败: $lastError_';
    throw Exception(lastError!);
  }

  // ---------------- Windows：gopeed.exe 子进程 + REST API ----------------

  static Future<void> _startWindows({bool retry = true}) async {
    if (_winProcess != null && _winServerReady) {
      _started = true;
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final storageDir = '${docs.path}/gopeed';
    final exe = _findGopeedExe();
    if (exe == null) {
      lastError = '未找到 gopeed.exe，请确认程序目录完整';
      AppLogger.I.e('engine', 'Windows 启动失败: $lastError');
      throw Exception(lastError!);
    }
    AppLogger.I.i('engine', 'Windows 引擎启动 exe=$exe storage=$storageDir retry=$retry');
    _winDiag = '';
    String lastError_ = '';
    final attempts = retry ? 3 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      Process? process;
      try {
        await _stopWindowsProcess();
        // 清掉所有残留 gopeed 实例：残留进程持有 bolt 数据库文件锁，
        // 会让新引擎卡在初始化阶段（打印 banner 后无输出）
        await _killAllGopeed();
        await Future.delayed(const Duration(milliseconds: 200));
        // 端口 0 表示随机分配，解析 stdout 中的监听地址
        process = await Process.start(exe, [
          '-A', '127.0.0.1',
          '-P', '0',
          '-T', '',
          '-d', storageDir,
        ]);
        _winProcess = process;
        AppLogger.I.i('engine', '引擎进程已拉起 pid=${process.pid} attempt=${attempt + 1}/$attempts');
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
        AppLogger.I.i('engine', '引擎启动成功 port=$port pid=${process.pid}');
        // 进程异常退出时标记引擎失效并自动重启；只清理当前进程的引用，避免误清新实例
        process.exitCode.then((code) {
          _winDiag = '引擎进程退出 code=$code';
          AppLogger.I.w('engine', '引擎进程退出 code=$code pid=${process.pid}');
          if (!identical(process, _winProcess)) return;
          _winProcess = null;
          _winServerReady = false;
          _started = false;
          _client = null;
          // 引擎被杀软终止/崩溃后立即自愈，避免用户操作踩中引擎失效窗口
          unawaited(_autoRestart());
        });
        // 注意：stdout/stderr 已由 _readServerPort 的监听器持续消费
        // （防止缓冲填满导致进程阻塞），这里绝不能再次 listen——
        // 单订阅流重复监听会抛 "Bad state: Stream has already been listened to."
        return;
      } catch (e) {
        lastError_ = e.toString();
        AppLogger.I.e('engine', '引擎启动尝试失败 attempt=${attempt + 1}/$attempts: $e');
        // 失败时立即杀掉本次启动的进程，避免残留实例堆积
        try {
          process?.kill();
        } catch (_) {}
        if (identical(process, _winProcess)) {
          _winProcess = null;
          _winServerReady = false;
        }
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
    lastError = '下载引擎启动失败: $lastError_$_winDiag';
    AppLogger.I.e('engine', 'Windows 引擎启动最终失败: $lastError');
    throw Exception(lastError!);
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
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
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
    }, onError: (Object _) {});
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
      stderrBuf.write(chunk);
      if (stderrBuf.length > 4096) {
        final tail = stderrBuf.toString().substring(stderrBuf.length - 2048);
        stderrBuf.clear();
        stderrBuf.write(tail);
      }
    }, onError: (Object _) {});
    // 首次启动被杀毒软件深度扫描会明显变慢，超时放宽到 30 秒
    // （引擎为后台异步启动，不阻塞界面）
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        final lines = buffer.toString().trim().split('\n');
        final tail = lines.length > 3
            ? lines.sublist(lines.length - 3).join(' | ')
            : lines.join(' | ');
        final err = stderrBuf.toString().trim();
        _winDiag = tail.isNotEmpty ? '输出: $tail' : '';
        if (err.isNotEmpty) {
          _winDiag = '$_winDiag 错误输出: ${err.split('\n').last}';
        }
        completer.complete(null);
      }
    });
    return completer.future;
  }

  /// 杀掉所有 gopeed.exe 进程（含其他实例残留，释放数据库文件锁）
  static Future<void> _killAllGopeed() async {
    try {
      await Process.run('taskkill', ['/IM', 'gopeed.exe', '/F']);
    } catch (_) {
      // 无残留实例时 taskkill 会报错，忽略
    }
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
    await _killAllGopeed();
  }

  static Future<void> stop() async {
    AppLogger.I.i('engine', 'stop 请求 started=$_started');
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

  /// 引擎进程意外退出后的自动重启（防抖；失败时留给 DownloadManager 周期重试）
  static Future<void> _autoRestart() async {
    AppLogger.I.i('engine', '引擎退出触发自动重启 _autoRestarting=$_autoRestarting');
    if (_autoRestarting) return;
    _autoRestarting = true;
    try {
      // 先等系统清理完退出的进程，再拉起新实例
      await Future.delayed(const Duration(milliseconds: 800));
      if (_started) return;
      try {
        await start();
      } catch (e) {
        AppLogger.I.e('engine', '自动重启失败: $e');
        // 自动重启失败不抛给调用方，界面由 DownloadManager 呈现引擎错误
      }
    } finally {
      _autoRestarting = false;
    }
  }
}
