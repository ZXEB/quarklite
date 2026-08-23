import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import 'download_client.dart';
import '../../utils/app_logger.dart';
import 'gopeed_models.dart';

/// iOS 原生 URLSession 后台下载客户端。
///
/// 对外维持与 Gopeed 相同的任务操作接口，使下载页面和业务入口无需分平台。
class IosBackgroundDownloadClient implements DownloadClient {
  static const group = 'quarklite';

  final FileDownloader _downloader = FileDownloader();
  final Map<String, TaskStatus> _latestStatus = {};
  final Map<String, double> _latestProgress = {};
  final Map<String, int> _expectedSize = {};
  final Map<String, int> _speedBytes = {};
  final Map<String, int> _lastProgressLogAt = {};

  StreamSubscription<TaskUpdate>? _updatesSubscription;
  int _maxRunning;
  bool _started = false;

  IosBackgroundDownloadClient({int maxRunning = 4})
      : _maxRunning = maxRunning.clamp(1, 32).toInt();

  Future<void> start() async {
    if (_started) return;

    // 必须先监听，再 start；start 会补发应用挂起期间收到的原生更新。
    _updatesSubscription = _downloader.updates.listen(_handleUpdate);
    _downloader.configureNotificationForGroup(
      group,
      running: const TaskNotification('Quarklite 下载中', '{displayName}'),
      complete: const TaskNotification('下载完成', '{displayName} 已保存'),
      error: const TaskNotification('下载失败', '{displayName} 下载失败'),
      paused: const TaskNotification('下载已暂停', '{displayName}'),
      canceled: const TaskNotification('下载已取消', '{displayName}'),
      tapOpensFile: true,
    );
    await _applyHoldingQueue();
    await _downloader.start(
      doTrackTasks: true,
      markDownloadedComplete: true,
      doRescheduleKilledTasks: true,
      autoCleanDatabase: false,
    );
    _started = true;
    final restored = await _downloader.database.allRecords(group: group);
    AppLogger.I.i('ios_download',
        'URLSession 下载器启动成功，恢复任务 ${restored.length} 个 maxRunning=$_maxRunning');
  }

  void _handleUpdate(TaskUpdate update) {
    if (update.task.group != group) return;
    final id = update.task.taskId;
    final name = update.task.displayName.isNotEmpty
        ? update.task.displayName
        : update.task.filename;
    switch (update) {
      case TaskStatusUpdate():
        _latestStatus[id] = update.status;
        final detail = update.exception == null ? '' : ' error=${update.exception}';
        AppLogger.I.i('ios_download',
            '状态 id=$id name=$name status=${update.status.name} http=${update.responseStatusCode ?? '-'}$detail');
      case TaskProgressUpdate():
        _latestProgress[id] = update.progress;
        if (update.hasExpectedFileSize) {
          _expectedSize[id] = update.expectedFileSize;
        }
        _speedBytes[id] = update.hasNetworkSpeed
            ? (update.networkSpeed * 1000 * 1000).round()
            : 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - (_lastProgressLogAt[id] ?? 0) >= 5000 ||
            update.progress >= 1 ||
            update.progress < 0) {
          _lastProgressLogAt[id] = now;
          AppLogger.I.i('ios_download',
              '进度 id=$id name=$name progress=${(update.progress * 100).toStringAsFixed(1)}% size=${update.expectedFileSize} speed=${_speedBytes[id]}');
        }
    }
  }

  Future<void> _applyHoldingQueue() async {
    await _downloader.configure(
      iOSConfig: [
        (Config.holdingQueue, (_maxRunning, null, null)),
      ],
    );
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
    final fileName = (name == null || name.isEmpty) ? 'download' : name;
    final targetPath = _joinPath(path, fileName);
    final (baseDirectory, directory, resolvedName) =
        await Task.split(filePath: targetPath);
    // iOS 使用单个原生 URLSessionDownloadTask。ParallelDownloadTask 会先发起
    // 额外请求探测文件长度，对夸克短时效签名 CDN 链接容易卡在排队阶段。
    final task = DownloadTask(
      url: url,
      filename: resolvedName,
      headers: headers,
      directory: directory,
      baseDirectory: baseDirectory,
      group: group,
      updates: Updates.statusAndProgress,
      retries: 2,
      allowPause: true,
      displayName: fileName,
    );
    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) throw Exception('iOS 后台下载任务加入队列失败');
    _latestStatus[task.taskId] = TaskStatus.enqueued;
    _latestProgress[task.taskId] = 0;
    AppLogger.I.i('ios_download',
        '任务入队 id=${task.taskId} name=$fileName dir=$directory base=${baseDirectory.name} headers=${headers.keys.join(',')}');
    return task.taskId;
  }

  @override
  Future<List<GopeedTask>> list({List<GopeedStatus>? statuses}) async {
    await start();
    final records = await _downloader.database.allRecords(group: group);
    final result = records.map(_toGopeedTask).where((task) {
      return statuses == null || statuses.isEmpty || statuses.contains(task.status);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  GopeedTask _toGopeedTask(TaskRecord record) {
    final id = record.taskId;
    final status = _latestStatus[id] ?? record.status;
    final progress = (_latestProgress[id] ?? record.progress).clamp(0.0, 1.0);
    final expected = _expectedSize[id] ?? record.expectedFileSize;
    final size = expected > 0 ? expected : 0;
    final name = record.task.displayName.isNotEmpty
        ? record.task.displayName
        : record.task.filename;
    return GopeedTask(
      id: id,
      name: name,
      status: mapStatus(status),
      size: size,
      downloaded: size > 0 ? (size * progress).round() : 0,
      speed: _speedBytes[id] ?? 0,
      createdAt: record.task.creationTime.millisecondsSinceEpoch,
    );
  }

  static GopeedStatus mapStatus(TaskStatus status) => switch (status) {
        TaskStatus.enqueued => GopeedStatus.wait,
        TaskStatus.waitingToRetry => GopeedStatus.wait,
        TaskStatus.running => GopeedStatus.running,
        TaskStatus.paused => GopeedStatus.pause,
        TaskStatus.complete => GopeedStatus.done,
        TaskStatus.notFound => GopeedStatus.error,
        TaskStatus.failed => GopeedStatus.error,
        TaskStatus.canceled => GopeedStatus.error,
      };

  Future<DownloadTask> _downloadTask(String id) async {
    final record = await _downloader.database.recordForId(id);
    final task = record?.task;
    if (task is DownloadTask) return task;
    final queued = await _downloader.taskForId(id);
    if (queued is DownloadTask) return queued;
    throw Exception('未找到 iOS 下载任务: $id');
  }

  @override
  Future<void> pause(String id) async {
    final task = await _downloadTask(id);
    if (!await _downloader.pause(task)) {
      throw Exception('该任务暂时无法暂停');
    }
  }

  @override
  Future<void> resume(String id) async {
    final task = await _downloadTask(id);
    if (!await _downloader.resume(task)) {
      throw Exception('该任务无法恢复，可能需要重新下载');
    }
  }

  @override
  Future<void> remove(String id, {bool force = true}) async {
    final record = await _downloader.database.recordForId(id);
    final task = record?.task;
    await _downloader.cancelTaskWithId(id);
    if (force && task != null) {
      try {
        final file = File(await task.filePath());
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _downloader.database.deleteRecordWithId(id);
    _latestStatus.remove(id);
    _latestProgress.remove(id);
    _expectedSize.remove(id);
    _speedBytes.remove(id);
    _lastProgressLogAt.remove(id);
  }

  @override
  Future<void> removeAll({List<String>? ids, bool force = true}) async {
    final targets = ids ??
        (await _downloader.database.allRecords(group: group))
            .map((record) => record.taskId)
            .toList();
    for (final id in targets) {
      await remove(id, force: force);
    }
  }

  @override
  Future<void> pauseAll({List<String>? ids}) async {
    final records = ids == null
        ? await _downloader.database.allRecords(group: group)
        : await _downloader.database.recordsForIds(ids);
    final tasks = records
        .where((record) {
          final status = _latestStatus[record.taskId] ?? record.status;
          return status == TaskStatus.enqueued ||
              status == TaskStatus.running ||
              status == TaskStatus.waitingToRetry;
        })
        .map((record) => record.task)
        .whereType<DownloadTask>()
        .toList();
    if (tasks.isNotEmpty) await _downloader.pauseAll(tasks: tasks);
  }

  @override
  Future<void> updateConfig({
    String? downloadDir,
    int? maxRunning,
    int? connections,
  }) async {
    if (maxRunning != null) {
      _maxRunning = maxRunning.clamp(1, 32).toInt();
      await _applyHoldingQueue();
    }
  }

  @override
  Future<Map<String, dynamic>> getConfig() async => {
        'downloadDir': '',
        'maxRunning': _maxRunning,
        'protocolConfig': {
          'http': {'connections': 1},
        },
      };

  String _joinPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
    return '$parent${Platform.pathSeparator}$child';
  }

  Future<void> dispose() async {
    await _updatesSubscription?.cancel();
  }
}
