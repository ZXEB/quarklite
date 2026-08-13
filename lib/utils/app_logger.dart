import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 轻量应用日志：追加写入 <文档目录>/quarklite/logs/app.log（Windows 可直接访问），
/// 超过 1MB 环形截断保留尾部，供排查下载引擎问题（我的 → 日志 → 复制）。
class AppLogger {
  AppLogger._();

  static final AppLogger I = AppLogger._();

  static const int _maxBytes = 1024 * 1024; // 日志文件上限 1MB
  static const int _keepBytes = 512 * 1024; // 截断后保留的尾部大小

  File? _file;
  bool _ready = false;
  bool _initDone = false;

  /// 初始化日志文件（失败时仅控制台输出，不影响主流程）
  Future<void> init() async {
    if (_initDone) return;
    _initDone = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/quarklite/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/app.log');
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final bytes = f.readAsBytesSync();
        f.writeAsBytesSync(bytes.sublist(bytes.length - _keepBytes));
      }
      _file = f;
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void i(String tag, String msg) => _log('INFO', tag, msg);
  void w(String tag, String msg) => _log('WARN', tag, msg);
  void e(String tag, String msg) => _log('ERROR', tag, msg);

  void _log(String level, String tag, String msg) {
    final line = '[${_ts()}] [$level] [$tag] $msg';
    // ignore: avoid_print
    print(line);
    if (!_ready) return;
    try {
      _file!.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // 日志写入失败不影响主流程
    }
  }

  static String _ts() {
    final n = DateTime.now();
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)} '
        '${p(n.hour)}:${p(n.minute)}:${p(n.second)}.${p(n.millisecond, 3)}';
  }

  /// 读取最近 [maxLines] 行日志（供界面复制/展示）
  Future<String> readLog({int maxLines = 500}) async {
    final f = _file;
    if (f == null || !f.existsSync()) return '（暂无日志）';
    try {
      final lines = f.readAsLinesSync();
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (_) {
      return '（日志读取失败）';
    }
  }

  /// 日志文件完整路径
  Future<String> logPath() async {
    final f = _file;
    if (f != null) return f.path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/quarklite/logs/app.log';
    } catch (_) {
      return '（未知）';
    }
  }
}
