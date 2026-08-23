import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/gopeed/gopeed_boot.dart';
import '../core/gopeed/gopeed_models.dart';
import '../core/notify/download_notifier.dart';
import '../utils/app_logger.dart';

class DownloadManager extends ChangeNotifier {
  static DownloadManager? _instance;
  static DownloadManager get I => _instance ??= DownloadManager._();

  final List<GopeedTask> tasks = [];
  Timer? _timer;
  bool _polling = false;
  bool _failed = false;
  DateTime? _lastStartAttempt;

  /// 最近一次引擎错误详情（供界面展示）
  String? engineError;

  DownloadManager._();

  void startPolling() {
    if (_polling) return;
    _polling = true;
    _failed = false;
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    _poll();
  }

  void stopPolling() {
    _polling = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 立即刷新一次任务列表（引擎重启后调用）
  Future<void> refresh() => _poll();

  bool get hasEngineError => _failed;

  Future<void> _poll() async {
    if (!GopeedEngine.started) {
      final now = DateTime.now();
      if (_lastStartAttempt != null &&
          now.difference(_lastStartAttempt!) < const Duration(seconds: 10)) {
        return;
      }
      _lastStartAttempt = now;
      try {
        await GopeedEngine.start();
      } catch (e) {
        _failed = true;
        engineError = GopeedEngine.lastError ?? e.toString();
        AppLogger.I.e('download', '轮询启动引擎失败: $engineError');
        notifyListeners();
        return;
      }
    }
    try {
      final list = await GopeedEngine.client.list();
      tasks
        ..clear()
        ..addAll(list);
      _failed = false;
      engineError = null;
      notifyListeners();
      DownloadNotifier.update(list);
    } catch (e) {
      _failed = true;
      engineError = e.toString();
      AppLogger.I.e('download', '轮询任务列表失败: $e');
    }
  }

  List<GopeedTask> byStatus(GopeedStatus status) {
    return tasks.where((t) => t.status == status).toList();
  }

  List<GopeedTask> activeTasks() =>
      tasks.where((t) => t.status.isActive).toList();

  int countOf(GopeedStatus status) => byStatus(status).length;

  Future<void> pauseTask(GopeedTask task) async {
    try {
      await GopeedEngine.client.pause(task.id);
    } catch (e) {
      rethrow;
    } finally {
      await _poll();
    }
  }

  Future<void> resumeTask(GopeedTask task) async {
    try {
      await GopeedEngine.client.resume(task.id);
    } catch (e) {
      rethrow;
    } finally {
      await _poll();
    }
  }

  Future<void> removeTask(GopeedTask task, {bool deleteFile = false}) async {
    try {
      await GopeedEngine.client.remove(task.id, force: deleteFile);
    } finally {
      await _poll();
    }
  }

  Future<void> clearDone() async {
    final doneIds = byStatus(GopeedStatus.done).map((t) => t.id).toList();
    if (doneIds.isEmpty) return;
    try {
      await GopeedEngine.client.removeAll(ids: doneIds, force: false);
    } finally {
      await _poll();
    }
  }

  Future<void> pauseAllActive() async {
    final ids = activeTasks().map((t) => t.id).toList();
    if (ids.isEmpty) return;
    try {
      await GopeedEngine.client.pauseAll(ids: ids);
    } finally {
      await _poll();
    }
  }
}
