import 'dart:io' show Directory, File, FileSystemEntityType, Platform;

import 'package:path_provider/path_provider.dart';

/// 播放磁盘缓存（mpv cache-on-disk 写入的 demuxer 缓存目录）的统计与清理。
///
/// 目录由 [AppState.playbackCacheDir] 决定（优先下载目录、避开系统盘），
/// 各方法都显式接收目录路径；旧版本写在系统临时目录的缓存由
/// [removeLegacyTempCache] 尽力清理。
class PlaybackCache {
  PlaybackCache._();

  static const _dirName = 'quarklite_playback_cache';

  /// 旧版本把 mpv 缓存写在系统临时目录（C 盘），升级后清理一次。
  static Future<void> removeLegacyTempCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      final legacy = Directory('${tmp.path}${Platform.pathSeparator}$_dirName');
      if (legacy.existsSync()) {
        await legacy.delete(recursive: true);
      }
    } catch (_) {
      // 播放中文件被占用等场景尽力而为
    }
  }

  /// 当前缓存大小（字节）；目录不存在或失败返回 0。
  static Future<int> sizeBytes(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
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
  static Future<int> clear(String dirPath) async {
    final freed = await sizeBytes(dirPath);
    final dir = Directory(dirPath);
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // 播放中文件被占用时尽力而为
      }
    }
    return freed;
  }

  /// 把缓存目录清到不超过 [maxBytes]：按修改时间从旧到新删除，
  /// 直到总大小达标（跨会话残留也一并纳入）。
  /// 返回释放的字节数；播放中的文件被占用时尽力跳过。
  static Future<int> enforceLimit(int maxBytes, String dirPath) async {
    if (maxBytes <= 0) return 0;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    final files = <File>[];
    var total = 0;
    try {
      await for (final e
          in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          final stat = await e.stat();
          if (stat.type == FileSystemEntityType.file) {
            files.add(e);
            total += stat.size;
          }
        } catch (_) {}
      }
    } catch (_) {
      return 0;
    }
    if (total <= maxBytes) return 0;
    // mpv 的缓存文件名不含时间信息，用修改时间近似 LRU
    final stats = <(File, DateTime)>[];
    for (final f in files) {
      try {
        stats.add((f, (await f.stat()).modified));
      } catch (_) {}
    }
    stats.sort((a, b) => a.$2.compareTo(b.$2));
    var freed = 0;
    for (final (f, _) in stats) {
      if (total - freed <= maxBytes) break;
      try {
        final size = (await f.stat()).size;
        await f.delete();
        freed += size;
      } catch (_) {
        // 播放中占用等场景：跳过该文件继续
      }
    }
    return freed;
  }
}
