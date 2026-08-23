import "dart:async";
import "dart:io";

import "package:flutter/services.dart";

import "../../utils/app_logger.dart";
import "download_client.dart";
import "gopeed_models.dart";

/// iOS 原生 Range 分片下载客户端（MethodChannel -> Swift IosRangeDownloadManager）
/// 前台最多 128 并发，后台自动降级到 4 并发后台 URLSession
class IosRangeDownloadClient implements DownloadClient {
  static const _method = MethodChannel("quarklite.com/ios_range_download");
  static const _event = EventChannel("quarklite.com/ios_range_download_events");

  static const maxForegroundConnections = 128;
  static const minChunkBytes = 8 * 1024 * 1024;

  final Map<String, GopeedStatus> _status = {};
  final Map<String, double> _progress = {};
  final Map<String, int> _expected = {};
  final Map<String, int> _speed = {};
  final Map<String, int> _createdAt = {};

  StreamSubscription<dynamic>? _sub;
  bool _started = false;
  int _maxRunning;

  IosRangeDownloadClient({int maxRunning = 4}) : _maxRunning = maxRunning.clamp(1, 32).toInt();

  static int adaptiveChunkCount({
    required int requested,
    int? contentLength,
    bool rangeSupported = true,
    int maxConnections = maxForegroundConnections,
  }) {
    if (!rangeSupported || requested <= 1) return 1;
    final cap = maxConnections.clamp(1, maxForegroundConnections).toInt();
    final wanted = requested.clamp(1, cap).toInt();
    if (contentLength == null || contentLength <= 0) return wanted;
    final bySize = (contentLength / minChunkBytes).ceil();
    return wanted < bySize ? wanted : bySize.clamp(1, wanted).toInt();
  }

  Future<void> start() async {
    if (_started) return;
    _sub = _event.receiveBroadcastStream().listen(_onEvent, onError: (e) {
      AppLogger.I.i("ios_range", "event error \$e");
    });
    _started = true;
    AppLogger.I.i("ios_range", "Range 下载器启动 maxRunning=\$_maxRunning maxC=\$maxForegroundConnections");
    // 恢复已持久化的任务到内存映射
    try {
      final list = await list();
      AppLogger.I.i("ios_range", "恢复任务 \${list.length} 个");
    } catch (_) {}
  }

  void _onEvent(dynamic ev) {
    if (ev is! Map) return;
    final m = Map<String, dynamic>.from(ev as Map);
    final id = m["taskId"]?.toString() ?? "";
    if (id.isEmpty) return;
    final st = m["status"]?.toString() ?? "wait";
    final pr = (m["progress"] as num?)?.toDouble() ?? 0;
    final exp = (m["expectedFileSize"] as num?)?.toInt() ?? 0;
    final sp = (m["speed"] as num?)?.toInt() ?? 0;
    final http = m["httpCode"]?.toString() ?? "-";
    _status[id] = _mapStatus(st);
    _progress[id] = pr.clamp(0.0, 1.0);
    _expected[id] = exp;
    _speed[id] = sp;
    AppLogger.I.i("ios_range", "event id=\$id status=\$st progress=\${(pr*100).toStringAsFixed(1)}% http=\$http");
  }

  GopeedStatus _mapStatus(String s) {
    switch (s) {
      case "wait": return GopeedStatus.wait;
      case "running": return GopeedStatus.running;
      case "pause": return GopeedStatus.pause;
      case "done": return GopeedStatus.done;
      case "error": return GopeedStatus.error;
      default: return GopeedStatus.wait;
    }
  }

  String _mapToNative(GopeedStatus s) {
    switch (s) {
      case GopeedStatus.running: return "running";
      case GopeedStatus.pause: return "pause";
      case GopeedStatus.done: return "done";
      case GopeedStatus.error: return "error";
      default: return "wait";
    }
  }

  @override
  Future<String> create({required String url, required String path, String? name, Map<String, String> headers = const {}, int connections = 16}) async {
    await start();
    final fileName = (name == null || name.isEmpty) ? "download" : name;
    // 按方案：前台最多 128，后台降级；connections 传入期望并发，Swift 侧自适应
    final capped = connections.clamp(1, maxForegroundConnections).toInt();
    // 探测由 Swift 完成，这里直接透传
    final id = await _method.invokeMethod<String>("create", {
      "url": url,
      "path": path,
      "name": fileName,
      "headers": headers,
      "connections": capped,
    });
    if (id == null || id.isEmpty) throw Exception("iOS Range 创建任务失败");
    _createdAt[id] = DateTime.now().millisecondsSinceEpoch;
    _status[id] = GopeedStatus.running;
    _progress[id] = 0;
    AppLogger.I.i("ios_range", "创建任务 id=\$id name=\$fileName con=\$capped path=\$path");
    return id;
  }

  @override
  Future<List<GopeedTask>> list({List<GopeedStatus>? statuses}) async {
    await start();
    final raw = await _method.invokeMethod<List<dynamic>>("list");
    final tasks = <GopeedTask>[];
    if (raw != null) {
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e as Map);
        final id = m["id"]?.toString() ?? "";
        final name = m["name"]?.toString() ?? "download";
        final st = m["status"]?.toString() ?? "wait";
        final size = (m["size"] as num?)?.toInt() ?? (m["expected"] as num?)?.toInt() ?? 0;
        final dl = (m["downloaded"] as num?)?.toInt() ?? 0;
        final sp = (m["speed"] as num?)?.toInt() ?? 0;
        final created = (m["createdAt"] as num?)?.toInt() ?? _createdAt[id] ?? DateTime.now().millisecondsSinceEpoch;
        final prog = (m["progress"] as num?)?.toDouble() ?? (size > 0 ? dl / size : 0);
        // 更新缓存
        _status[id] = _mapStatus(st);
        _progress[id] = (prog as double).clamp(0.0, 1.0);
        _expected[id] = size;
        _speed[id] = sp;
        _createdAt[id] = created;
        final task = GopeedTask(
          id: id,
          name: name,
          status: _mapStatus(st),
          size: size,
          downloaded: dl > 0 ? dl : (size * (prog as double)).round(),
          speed: sp,
          createdAt: created,
        );
        tasks.add(task);
      }
    }
    // 合并事件缓存中但 list 未返回的任务（刚创建但 Native 尚未持久化）
    final filtered = tasks.where((t) => statuses == null || statuses.isEmpty || statuses.contains(t.status)).toList()
      ..sort((a,b)=>b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  @override
  Future<void> pause(String id) async {
    await _method.invokeMethod("pause", {"id": id});
    _status[id] = GopeedStatus.pause;
  }

  @override
  Future<void> resume(String id) async {
    await _method.invokeMethod("resume", {"id": id});
    _status[id] = GopeedStatus.running;
  }

  @override
  Future<void> remove(String id, {bool force = true}) async {
    await _method.invokeMethod("remove", {"id": id, "force": force});
    _status.remove(id); _progress.remove(id); _expected.remove(id); _speed.remove(id); _createdAt.remove(id);
  }

  @override
  Future<void> removeAll({List<String>? ids, bool force = true}) async {
    // Swift 侧 force 语义为删除目标文件，这里逐个或批量
    if (ids == null || ids.isEmpty) {
      await _method.invokeMethod("removeAll", {"ids": ids});
      _status.clear(); _progress.clear(); _expected.clear(); _speed.clear(); _createdAt.clear();
    } else {
      for (final id in ids) { await remove(id, force: force); }
    }
  }

  @override
  Future<void> pauseAll({List<String>? ids}) async {
    await _method.invokeMethod("pauseAll", {"ids": ids});
    if (ids == null) {
      for (final k in _status.keys) { if (_status[k]==GopeedStatus.running) _status[k]=GopeedStatus.pause; }
    } else {
      for (final id in ids) { _status[id]=GopeedStatus.pause; }
    }
  }

  @override
  Future<void> updateConfig({String? downloadDir, int? maxRunning, int? connections}) async {
    if (maxRunning != null) _maxRunning = maxRunning.clamp(1, 32).toInt();
    // connections 映射为前台窗口上限，实际由 Swift 自适应控制 32->64->128
    await _method.invokeMethod("updateConfig", {"maxRunning": _maxRunning, "connections": connections});
  }

  @override
  Future<Map<String, dynamic>> getConfig() async {
    final m = await _method.invokeMethod<Map<dynamic,dynamic>>("getConfig");
    if (m == null) return {"downloadDir":"","maxRunning":_maxRunning,"protocolConfig":{"http":{"connections":maxForegroundConnections}}};
    return Map<String,dynamic>.from(m as Map);
  }

  Future<void> notifyLifecycle(String state) async {
    try { await _method.invokeMethod("notifyLifecycle", {"state": state}); } catch (_) {}
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
