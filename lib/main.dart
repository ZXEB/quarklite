import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'utils/single_instance.dart';
import 'utils/window_close.dart';

/// 全局导航 key：供窗口关闭弹窗等在任意位置弹对话框
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }
  // Windows 单实例锁：防止多开导致两个实例的引擎进程互相 taskkill 死循环
  if (!SingleInstance.acquire()) {
    SingleInstance.showAlreadyRunning();
    exit(0);
  }
  // Windows 关闭窗口行为（最小化/退出）回调
  if (!kIsWeb && Platform.isWindows) {
    WindowCloseHandler.init(appNavigatorKey);
  }
  runApp(QuarkLiteApp(navigatorKey: appNavigatorKey));
}
