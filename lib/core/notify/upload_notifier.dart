import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 上传完成/失败系统通知（Android 常驻渠道 + Windows 弹窗提醒）。
/// 与 DownloadNotifier 各自初始化互不冲突（插件为单例）。
class UploadNotifier {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _init = false;
  static int _notifId = 3000;

  static Future<void> init() async {
    if (_init) return;
    _init = true;
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notifications'),
          iOS: DarwinInitializationSettings(),
          windows: WindowsInitializationSettings(
            appName: 'Quarklite',
            appUserModelId: 'com.quarklite.quarklite',
            guid: 'com.quarklite.quarklite',
          ),
        ),
      );
      await _local
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // 通知初始化失败不影响上传
    }
  }

  static Future<void> showDone(String fileName) async {
    await init();
    try {
      await _local.show(
        id: _notifId++,
        title: '上传完成',
        body: '$fileName 已上传到夸克网盘',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'quarklite_uploads',
            '上传任务',
            channelDescription: '上传完成与失败提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
          windows: const WindowsNotificationDetails(
            duration: WindowsNotificationDuration.long,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> showFailed(String fileName, String error) async {
    await init();
    try {
      await _local.show(
        id: _notifId++,
        title: '上传失败',
        body: '$fileName\n$error',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'quarklite_uploads',
            '上传任务',
            channelDescription: '上传完成与失败提醒',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.error,
          ),
          iOS: const DarwinNotificationDetails(),
          windows: const WindowsNotificationDetails(
            duration: WindowsNotificationDuration.long,
          ),
        ),
      );
    } catch (_) {}
  }
}
