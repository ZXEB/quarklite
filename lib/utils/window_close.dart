import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows 窗口关闭行为管理：
/// 关闭窗口时按用户设置决定「最小化到任务栏（后台继续下载）」还是「退出」。
/// 默认首次关闭时询问并记住选择，之后不再打扰；设置页可随时更改。
class WindowCloseHandler {
  static const _channel = MethodChannel('quarklite.com/window');
  static const kCloseActionKey = 'window_close_action';

  /// 关闭行为：ask_once（首次询问后记住，默认）/ minimize / exit / ask（每次询问）
  static const actions = ['ask_once', 'minimize', 'exit', 'ask'];

  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> init(GlobalKey<NavigatorState> key) async {
    navigatorKey = key;
    // 注册原生 WM_CLOSE 回调（仅 Windows）
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCloseRequested') {
        await handleCloseRequest();
      }
    });
  }

  static Future<String> loadAction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kCloseActionKey) ?? 'ask_once';
    } catch (_) {
      return 'ask_once';
    }
  }

  static Future<void> saveAction(String action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kCloseActionKey, action);
    } catch (_) {}
  }

  /// 处理窗口关闭请求
  static Future<void> handleCloseRequest() async {
    final action = await loadAction();
    switch (action) {
      case 'minimize':
        await minimize();
        return;
      case 'exit':
        await exitApp();
        return;
      case 'ask':
        await _askAndRun(remember: false);
        return;
      default: // ask_once：首次询问并记住
        await _askAndRun(remember: true);
    }
  }

  static Future<void> _askAndRun({required bool remember}) async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) {
      // 界面未就绪时兜底最小化
      await minimize();
      return;
    }
    final choice = await showDialog<String>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭 Quarklite'),
        content: const Text('关闭窗口后要继续在后台下载吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'exit'),
            child: const Text('退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'minimize'),
            child: const Text('最小化'),
          ),
        ],
      ),
    );
    final action = choice ?? 'minimize';
    if (remember) {
      // 首次选择后记住，下次直接按此行为执行
      await saveAction(action);
    }
    if (action == 'minimize') {
      await minimize();
    } else {
      await exitApp();
    }
  }

  static Future<void> minimize() async {
    try {
      await _channel.invokeMethod('minimize');
    } catch (_) {}
  }

  static Future<void> exitApp() async {
    try {
      await _channel.invokeMethod('exit');
    } catch (_) {}
  }
}
