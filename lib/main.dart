import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'utils/single_instance.dart';

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
  runApp(const QuarkLiteApp());
}
