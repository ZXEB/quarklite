import "dart:async";
import "dart:io";
import "dart:math";

import "package:flutter/services.dart";

import "../../utils/app_logger.dart";
import "download_client.dart";
import "gopeed_models.dart";
import "ios_background_download_client.dart";

/// iOS 并行下载客户端：优先走原生 Swift 多分片，未满足条件时回退单线程 background_downloader
class IosParallelDownloadClient implements DownloadClient {
  static const _channelName = "quarklite.com/ios_parallel";
  static const _methodCreateParallel = "createParallel";
  static const _methodCancel = "cancel";

  final IosBackgroundDownloadClient _fallback;
  final MethodChannel _channel = const MethodChannel(_channelName);

  // parallel task bookkeeping
  final Map<String, _ParallelTask> _parallelTasks = {};
  final Map<String, GopeedStatus> _parallelStatus = {};
  final Map<String, double> _parallelProgress = {};
  final Map<String, int> _parallelSize = {};
  final Map<String, int> _parallelSpeed = {};
  final Map<String, int> _parallelCreatedAt = {};

  int _maxRunning;
  bool _started = false;
  StreamSubscription? _nativeSub;

  IosParallelDownloadClient({int maxRunning = 4, int iosConnections = 32})
      : _fallback = IosBackgroundDownloadClient(maxRunning: maxRunning),
        _maxRunning = maxRunning.clamp(1, 32).toInt() {
    _setupMethodHandler();
  }

  void _setupMethodHandler() {
    // Swift side calls back via MethodChannel invokeMethod on same channel
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "onProgress":
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final id = args["taskId"]?.toString() ?? "";
          final done = (args["done"] as num?)?.toInt() ?? 0;
          final total = (args["total"] as num?)?.toInt() ?? 0;
          final rec = _parallelTasks[id];
          if (rec != null) {
            rec.downloaded = done;
            rec.size = total;
            _parallelProgress[id] = total > 0 ? (done / total).clamp(0.0, 1.0) : 0;
            _parallelSize[id] = total;
            _parallelStatus[id] = GopeedStatus.running;
          }
          break;
        case "onComplete":
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final id = args["taskId"]?.toString() ?? "";
          _parallelStatus[id] = GopeedStatus.done;
          _parallelProgress[id] = 1.0;
          AppLogger.I.i("ios_parallel", "native complete id=$id");
          break;
        case "onError":
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final id = args["taskId"]?.toString() ?? "";
          final err = args["error"]?.toString() ?? "unknown";
          _parallelStatus[id] = GopeedStatus.error;
          AppLogger.I.w("ios_parallel", "native error id=$id err=$err");
          break;
      }
      return null;
    });
  }

  Future<void> start() async {
    if (_started) return;
    await _fallback.start();
    _started = true;
    AppLogger.I.i("ios_parallel", "parallel client started fallback ready");
  }

  @override
  Future<String> create({
    required String url,
    required String path,
    String? name,
    Map<String, String> headers = const {},
    int connections = 16,
  }) async {
    await start();
    final fileName = (name == null || name.isEmpty) ? "download" : name;
    final targetPath = _joinPath(path, fileName);
    // decision: small connections or iOS fallback single
    // Plan: <10MB 单线程 via fallback, but we don@"t know size yet; so we always try parallel when connections>1
    // Swift will decide to fallback internally after HEAD probe.
    final useParallel = connections > 1;
    if (!useParallel) {
      return _fallback.create(url: url, path: path, name: name, headers: headers, connections: connections);
    }
    final taskId = "pl-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}";
    final rec = _ParallelTask(
      id: taskId,
      name: fileName,
      targetPath: targetPath,
      url: url,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _parallelTasks[taskId] = rec;
    _parallelStatus[taskId] = GopeedStatus.running;
    _parallelProgress[taskId] = 0;
    _parallelSize[taskId] = 0;
    _parallelSpeed[taskId] = 0;
    _parallelCreatedAt[taskId] = rec.createdAt;

    // ensure dir exists
    try {
      final dir = File(targetPath).parent;
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (_) {}

    AppLogger.I.i("ios_parallel", "create parallel id=$taskId name=$fileName connections=$connections path=$targetPath");

    try {
      await _channel.invokeMethod(_methodCreateParallel, {
        "taskId": taskId,
        "url": url,
        "headers": headers,
        "targetPath": targetPath,
        "displayName": fileName,
        "connections": connections.clamp(1, 64).toInt(),
      });
    } catch (e) {
      AppLogger.I.w("ios_parallel", "native create failed $e, fallback to single");
      _parallelTasks.remove(taskId);
      _parallelStatus.remove(taskId);
      // fallback
      return _fallback.create(url: url, path: path, name: name, headers: headers, connections: connections);
    }
    return taskId;
  }

  @override
  Future<List<GopeedTask>> list({List<GopeedStatus>? statuses}) async {
    await start();
    final fallbackList = await _fallback.list(statuses: statuses);
    final parallelList = _parallelTasks.values.map((r) {
      final id = r.id;
      final status = _parallelStatus[id] ?? GopeedStatus.running;
      final size = _parallelSize[id] ?? r.size;
      final prog = _parallelProgress[id] ?? 0;
      final downloaded = size > 0 ? (size * prog).round() : r.downloaded;
      return GopeedTask(
        id: id,
        name: r.name,
        status: status,
        size: size,
        downloaded: downloaded,
        speed: _parallelSpeed[id] ?? 0,
        createdAt: _parallelCreatedAt[id] ?? r.createdAt,
      );
    }).where((t) {
      if (statuses == null || statuses.isEmpty) return true;
      return statuses.contains(t.status);
    }).toList();

    // If file already completed and exists, we could mark done; native callback already sets done.
    // For completed tasks that file exists, keep them; UI will show done.

    final merged = [...fallbackList, ...parallelList]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  @override
  Future<void> pause(String id) async {
    if (_parallelTasks.containsKey(id)) {
      // V1: parallel pause = cancel + cleanup
      try {
        await _channel.invokeMethod(_methodCancel, {"taskId": id});
      } catch (_) {}
      _parallelStatus[id] = GopeedStatus.pause;
      // keep record for UI but marked paused
      // optionally delete parts already done by native cancel
      return;
    }
    await _fallback.pause(id);
  }

  @override
  Future<void> resume(String id) async {
    if (_parallelTasks.containsKey(id)) {
      final status = _parallelStatus[id];
      if (status == GopeedStatus.pause) {
        // V1 resume = error, need recreate
        throw Exception("并行任务暂停后需重新下载（V1 不支持断点续传）");
      }
      // if running, no-op
      return;
    }
    await _fallback.resume(id);
  }

  @override
  Future<void> remove(String id, {bool force = true}) async {
    if (_parallelTasks.containsKey(id)) {
      try {
        await _channel.invokeMethod(_methodCancel, {"taskId": id});
      } catch (_) {}
      final rec = _parallelTasks[id];
      _parallelTasks.remove(id);
      _parallelStatus.remove(id);
      _parallelProgress.remove(id);
      _parallelSize.remove(id);
      _parallelSpeed.remove(id);
      _parallelCreatedAt.remove(id);
      if (force && rec != null) {
        try {
          final f = File(rec.targetPath);
          if (await f.exists()) await f.delete();
          // also clean .part files
          final dir = f.parent;
          final base = f.uri.pathSegments.last;
          if (await dir.exists()) {
            await for (final e in dir.list()) {
              if (e.path.contains("$base.part_")) {
                try { await e.delete(); } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
      return;
    }
    await _fallback.remove(id, force: force);
  }

  @override
  Future<void> removeAll({List<String>? ids, bool force = true}) async {
    if (ids == null) {
      final pIds = _parallelTasks.keys.toList();
      for (final id in pIds) {
        await remove(id, force: force);
      }
      await _fallback.removeAll(force: force);
      return;
    }
    for (final id in ids) {
      await remove(id, force: force);
    }
  }

  @override
  Future<void> pauseAll({List<String>? ids}) async {
    final pTargets = ids == null ? _parallelTasks.keys.toList() : ids.where((id) => _parallelTasks.containsKey(id)).toList();
    for (final id in pTargets) {
      await pause(id);
    }
    await _fallback.pauseAll(ids: ids);
  }

  @override
  Future<void> updateConfig({String? downloadDir, int? maxRunning, int? connections}) async {
    if (maxRunning != null) {
      _maxRunning = maxRunning.clamp(1, 32).toInt();
      await _fallback.updateConfig(maxRunning: maxRunning);
    }
    // connections is iosConnections, stored in AppState, used on next create via effectiveConnections
    // No native ongoing task needs update
  }

  @override
  Future<Map<String, dynamic>> getConfig() async {
    final base = await _fallback.getConfig();
    base["maxRunning"] = _maxRunning;
    base["protocolConfig"] = {
      "http": {"connections": 1}
    };
    return base;
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) return "$parent$child";
    return "$parent${Platform.pathSeparator}$child";
  }

  Future<void> dispose() async {
    await _fallback.dispose();
  }
}

class _ParallelTask {
  final String id;
  final String name;
  final String targetPath;
  final String url;
  final int createdAt;
  int size = 0;
  int downloaded = 0;
  _ParallelTask({required this.id, required this.name, required this.targetPath, required this.url, required this.createdAt});
}


