import 'dart:io' show Directory, FileSystemEntityType, Platform;

import 'package:path_provider/path_provider.dart';

/// 播放磁盘缓存（mpv cache-on-disk 写入的 demuxer 缓存目录）的统计与清理。
class PlaybackCache {
  PlaybackCache._();

  static const _dirName = 'quarklite_playback_cache';

  static Future<Directory?> _cacheDir() async {
    try {
      final tmp = await getTemporaryDirectory();
      return Directory('${tmp.path}${Platform.pathSeparator}$_dirName');
    } catch (_) {
      return null;
    }
  }

  /// 当前缓存大小（字节）；目录不存在或失败返回 0。
  static Future<int> sizeBytes() async {
    final dir = await _cacheDir();
    if (dir == null || !dir.existsSync()) return 0;
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        final stat = await e.stat();
        if (stat.type == FileSystemEntityType.file) total += stat.size;
      }
    } catch (_) {}
    return total;
  }

  /// 清理缓存，返回释放的字节数。
  static Future<int> clear() async {
    final freed = await sizeBytes();
    final dir = await _cacheDir();
    if (dir != null && dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // 播放中文件被占用时尽力而为
      }
    }
    return freed;
  }
}
