import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../utils/format.dart';
import '../gopeed/gopeed_models.dart';

/// 下载通知：前台服务（后台保活 + 实时进度）+ 完成/失败提醒
class DownloadNotifier {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _init = false;
  static int _lastProgressTs = 0;
  static int _notifId = 1000;
  static final Map<String, GopeedStatus> _prevStatus = {};
  static int _doneCount = 0;

  static Future<void> init() async {
    if (_init) return;
    _init = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'quarklite_service',
        channelName: 'Quarklite 后台下载服务',
        channelImportance: NotificationChannelImportance.LOW,
        showWhen: true,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notifications'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// 每次轮询任务列表后调用：更新前台服务通知 + 发送完成/失败提醒
  static Future<void> update(List<GopeedTask> tasks) async {
    if (!_init) return;
    try {
      await _updateProgress(tasks);
      _checkCompletions(tasks);
    } catch (_) {
      // 通知失败不影响下载
    }
  }

  static Future<void> _updateProgress(List<GopeedTask> tasks) async {
    final active = tasks.where((t) => t.status.isActive).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    final isRunning = await FlutterForegroundTask.isRunningService;

    if (active.isNotEmpty) {
      final total = active.fold<int>(0, (s, t) => s + t.size);
      final done = active.fold<int>(0, (s, t) => s + t.downloaded);
      final speed = active.fold<int>(0, (s, t) => s + t.speed);
      final pct =
          total > 0 ? ((done / total) * 100).clamp(0, 100).toStringAsFixed(0) : '0';
      final title = '下载中 ${active.length} 个任务  ·  $pct%';
      final text = '${formatSpeed(speed)}  ·  已下载 ${formatBytes(done)}';

      if (isRunning) {
        if (now - _lastProgressTs >= 3000) {
          _lastProgressTs = now;
          await FlutterForegroundTask.updateService(
            notificationTitle: title,
            notificationText: text,
          );
        }
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } else {
      if (isRunning) {
        FlutterForegroundTask.stopService();
      }
    }
  }

  static void _checkCompletions(List<GopeedTask> tasks) {
    final activeIds = <String>{};
    for (final t in tasks) {
      activeIds.add(t.id);
      final prev = _prevStatus[t.id];
      if (prev != null &&
          prev != t.status &&
          (t.status == GopeedStatus.done || t.status == GopeedStatus.error)) {
        _doneCount++;
        _showCompletion(t, _doneCount);
      }
      _prevStatus[t.id] = t.status;
    }
    _prevStatus.removeWhere((id, _) => !activeIds.contains(id));
  }

  static Future<void> _showCompletion(GopeedTask t, int seq) async {
    final done = t.status == GopeedStatus.done;
    await _local.show(
      id: _notifId++,
      title: done ? '下载完成' : '下载失败',
      body: '${t.name}\n${done ? '已保存 ${formatBytes(t.size)}' : '任务出错，可删除后重试'}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'quarklite_downloads',
          '下载任务',
          channelDescription: '下载完成与失败提醒',
          importance: Importance.high,
          priority: Priority.high,
          category: done
              ? AndroidNotificationCategory.status
              : AndroidNotificationCategory.error,
        ),
      ),
    );
  }
}
