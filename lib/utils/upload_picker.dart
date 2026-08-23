import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../state/app_state.dart';

/// 上传源文件（本地路径 + 网盘目标信息）
class UploadSource {
  final String path;
  final String name;
  final int size;
  final int modified;

  /// 文件夹上传时的相对目录（'' 表示根目录；普通文件上传恒为空）
  final String relDir;

  const UploadSource({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    this.relDir = '',
  });
}

/// 文件夹选择结果
class FolderPickResult {
  final bool canceled;
  final bool needPermission;

  /// 错误信息（非权限类）
  final String? error;
  final String rootName;
  final List<UploadSource> files;

  /// 空目录的相对路径列表（保持目录结构）
  final List<String> emptyDirs;

  const FolderPickResult({
    this.canceled = false,
    this.needPermission = false,
    this.error,
    this.rootName = '',
    this.files = const [],
    this.emptyDirs = const [],
  });
}

/// 本地文件/文件夹选择（Android 走 SAF；Windows 走原生对话框）
class UploadPicker {
  /// 文件夹遍历限制：避免超大目录卡死
  static const maxDepth = 20;
  static const maxFiles = 2000;

  /// 多选文件。返回空列表表示用户取消。
  static Future<List<UploadSource>> pickFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
    );
    if (result == null) return const [];
    final sources = <UploadSource>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null || path.isEmpty) continue;
      var modified = 0;
      try {
        final st = await File(path).stat();
        modified = st.modified.millisecondsSinceEpoch;
      } catch (_) {
        // 文件已被移动等异常：保留默认时间戳
      }
      sources.add(UploadSource(
        path: path,
        name: f.name,
        size: f.size,
        modified: modified,
      ));
    }
    return sources;
  }

  /// 选择文件夹并递归收集（保持目录结构）。
  /// Android 上路径不可读（未授予所有文件访问）时返回 needPermission。
  static Future<FolderPickResult> pickFolder() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null || dirPath.isEmpty) {
      return const FolderPickResult(canceled: true);
    }
    // Android 部分受保护目录会返回 "/"，无法遍历
    if (dirPath == '/' || dirPath == '\\') {
      return const FolderPickResult(
          error: '无法访问该目录，请选择手机内部存储中的文件夹');
    }
    final rootName = _basename(dirPath);
    final root = Directory(dirPath);
    if (!await root.exists()) {
      return FolderPickResult(error: '无法访问所选目录「$rootName」');
    }
    if (!kIsWeb && Platform.isAndroid && !await AppState.I.canWriteDownload()) {
      return FolderPickResult(
        needPermission: true,
        rootName: rootName,
      );
    }
    final files = <UploadSource>[];
    final emptyDirs = <String>[];
    String? walkError;
    try {
      await _walk(root, '', files, emptyDirs, depth: 0);
    } on FileSystemException catch (e) {
      walkError = '读取目录失败: ${e.message}';
    }
    return FolderPickResult(
      rootName: rootName,
      files: files,
      emptyDirs: emptyDirs,
      error: walkError,
    );
  }

  static Future<void> _walk(
    Directory dir,
    String rel,
    List<UploadSource> files,
    List<String> emptyDirs, {
    required int depth,
  }) async {
    if (depth > maxDepth || files.length >= maxFiles) return;
    final children = <FileSystemEntity>[];
    await for (final e in dir.list(followLinks: false)) {
      children.add(e);
    }
    if (children.isEmpty) {
      if (rel.isNotEmpty) emptyDirs.add(rel);
      return;
    }
    for (final e in children) {
      if (files.length >= maxFiles) break;
      final name = _basename(e.path);
      if (e is Directory) {
        final childRel = rel.isEmpty ? name : '$rel/$name';
        await _walk(e, childRel, files, emptyDirs, depth: depth + 1);
      } else if (e is File) {
        try {
          final st = await e.stat();
          files.add(UploadSource(
            path: e.path,
            name: name,
            size: st.size,
            modified: st.modified.millisecondsSinceEpoch,
            relDir: rel,
          ));
        } catch (_) {
          // 单个文件读取失败跳过，不中断整个目录
        }
      }
    }
  }

  static String _basename(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx < 0 ? norm : norm.substring(idx + 1);
  }
}
