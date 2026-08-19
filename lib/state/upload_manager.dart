import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/quark_client.dart';
import '../api/quark_models.dart';
import '../core/notify/upload_notifier.dart';
import '../state/app_state.dart';
import '../utils/app_logger.dart';
import '../utils/mime.dart';
import '../utils/upload_picker.dart';

enum UploadStatus { pending, uploading, done, failed, canceled }

enum UploadStage { queued, hashing, uploading, merging }

class UploadTask {
  final String id;
  final String fileName;
  final String localPath;
  int size;

  /// 文件夹上传时的相对目录（'' 为根；普通文件上传恒为空）
  final String relDir;

  /// 仅创建空文件夹的任务
  final bool isDirOnly;

  UploadStatus status;
  UploadStage stage;
  int uploadedBytes;
  double speed;
  String? error;
  final DateTime createdAt;
  bool cancelRequested = false;
  CancelToken? cancelToken;

  // 速度采样用（仅管理器中读写）
  int lastSampleBytes = 0;
  DateTime lastSampleTs = DateTime.now();

  UploadTask({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.size,
    this.relDir = '',
    this.isDirOnly = false,
    this.status = UploadStatus.pending,
    this.stage = UploadStage.queued,
    this.uploadedBytes = 0,
    this.speed = 0,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress =>
      size <= 0 ? 0 : (uploadedBytes / size).clamp(0.0, 1.0);

  bool get isActive =>
      status == UploadStatus.pending || status == UploadStatus.uploading;
}

/// 夸克网盘上传管理器：单例队列 + 顺序 worker。
/// 每次同时上传 1 个文件（队列清晰、进度明确、避免打爆接口限流），
/// 单个文件内部按服务端分片大小顺序直传 OSS。
class UploadManager extends ChangeNotifier {
  static UploadManager? _instance;
  static UploadManager get I => _instance ??= UploadManager._();

  UploadManager._();

  final List<UploadTask> tasks = [];
  bool _running = false;
  Timer? _speedTimer;
  int _seq = 0;

  // ---------------- 文件夹上传的目录 fid 缓存（一次批内有效） ----------------
  String _baseDirFid = '0';
  String? _rootFolderName;
  bool _folderBatch = false;
  final Map<String, String> _dirFidCache = {};

  static const _hashChunkSize = 4 * 1024 * 1024;
  static const _defaultPartSize = 10 * 1024 * 1024;

  // ---------------- 统计 ----------------

  int get activeCount => tasks.where((t) => t.isActive).length;
  int get doneCount =>
      tasks.where((t) => t.status == UploadStatus.done).length;
  int get failedCount =>
      tasks.where((t) => t.status == UploadStatus.failed).length;
  bool get hasActive => activeCount > 0;

  /// 进行中任务的总进度（0..1），无进行中任务时返回 0
  double get overallProgress {
    final active = tasks.where((t) => t.isActive).toList();
    if (active.isEmpty) return 0;
    final total = active.fold<int>(0, (s, t) => s + t.size);
    final done = active.fold<int>(0, (s, t) => s + t.uploadedBytes);
    return total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
  }

  // ---------------- 入队 ----------------

  /// 添加多个文件上传任务（目标为当前网盘目录）
  void addFiles(List<UploadSource> sources, String targetDirFid) {
    if (sources.isEmpty) return;
    _beginBatch(targetDirFid, null);
    for (final s in sources) {
      tasks.add(UploadTask(
        id: _nextId(),
        fileName: s.name,
        localPath: s.path,
        size: s.size,
      ));
    }
    notifyListeners();
    _kick();
  }

  /// 添加文件夹上传批次（文件 + 空目录，保持目录结构）
  void addFolderBatch({
    required List<UploadSource> files,
    required List<String> emptyDirs,
    required String targetDirFid,
    required String rootFolderName,
  }) {
    if (files.isEmpty && emptyDirs.isEmpty) return;
    _beginBatch(targetDirFid, rootFolderName);
    for (final s in files) {
      tasks.add(UploadTask(
        id: _nextId(),
        fileName: s.name,
        localPath: s.path,
        size: s.size,
        relDir: s.relDir,
      ));
    }
    for (final rel in emptyDirs) {
      tasks.add(UploadTask(
        id: _nextId(),
        fileName: _basename(rel),
        localPath: '',
        size: 0,
        relDir: rel,
        isDirOnly: true,
      ));
    }
    notifyListeners();
    _kick();
  }

  void _beginBatch(String targetDirFid, String? rootFolderName) {
    _baseDirFid = targetDirFid;
    _folderBatch = rootFolderName != null && rootFolderName.isNotEmpty;
    _rootFolderName = _folderBatch ? rootFolderName : null;
    _dirFidCache.clear();
  }

  String _nextId() =>
      'u${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  // ---------------- 控制 ----------------

  void cancel(UploadTask task) {
    task.cancelRequested = true;
    task.cancelToken?.cancel();
    notifyListeners();
  }

  void retry(UploadTask task) {
    task
      ..status = UploadStatus.pending
      ..stage = UploadStage.queued
      ..error = null
      ..uploadedBytes = 0
      ..speed = 0
      ..cancelRequested = false
      ..cancelToken = null;
    notifyListeners();
    _kick();
  }

  void remove(UploadTask task) {
    task.cancelRequested = true;
    task.cancelToken?.cancel();
    tasks.remove(task);
    notifyListeners();
  }

  void clearDone() {
    tasks.removeWhere((t) =>
        t.status == UploadStatus.done || t.status == UploadStatus.canceled);
    notifyListeners();
  }

  // ---------------- worker ----------------

  Future<void> _kick() async {
    if (_running) return;
    _running = true;
    _ensureSpeedTimer();
    try {
      while (true) {
        final task =
            tasks.where((t) => t.status == UploadStatus.pending).firstOrNull;
        if (task == null) break;
        await _uploadOne(task);
      }
    } finally {
      _running = false;
      if (!hasActive) {
        _speedTimer?.cancel();
        _speedTimer = null;
      }
    }
  }

  Future<void> _uploadOne(UploadTask task) async {
    task
      ..status = UploadStatus.uploading
      ..stage = UploadStage.hashing
      ..error = null
      ..cancelToken = CancelToken();
    notifyListeners();
    final app = AppState.I;
    RandomAccessFile? raf;
    try {
      // 空文件夹任务：仅创建远端目录
      if (task.isDirOnly) {
        task.stage = UploadStage.merging;
        await _resolveDirFid(task.relDir);
        _finishDone(task);
        return;
      }

      final file = File(task.localPath);
      final stat = await file.stat();
      task.size = stat.size;
      final mime = mimeFor(task.fileName);

      // 1. 计算 md5/sha1（供秒传校验；分块推进进度）
      task.uploadedBytes = 0;
      task.lastSampleBytes = 0;
      task.lastSampleTs = DateTime.now();
      final (md5Hex, sha1Hex) = await _hashFile(file, task);
      if (task.cancelRequested) {
        task.status = UploadStatus.canceled;
        return;
      }

      // 2. 上传预申请
      final targetFid = await _resolveDirFid(task.relDir);
      final session = await app.quark.uploadPre(
        pdirFid: targetFid,
        fileName: task.fileName,
        size: task.size,
        mime: mime,
        createdAt: stat.modified.millisecondsSinceEpoch,
        updatedAt: stat.modified.millisecondsSinceEpoch,
      );
      if (session.finish) {
        _finishDone(task);
        return;
      }

      // 3. 秒传校验（哈希命中直接完成）
      final instant = await app.quark.uploadHash(
          md5: md5Hex, sha1: sha1Hex, taskId: session.taskId);
      if (instant) {
        _finishDone(task);
        return;
      }

      // 4. 分片上传
      task.stage = UploadStage.uploading;
      task.uploadedBytes = 0;
      final partSize = session.partSize > 0 ? session.partSize : _defaultPartSize;
      raf = await file.open();
      var offset = 0;
      var partNumber = 1;
      final etags = <String>[];
      while (offset < task.size) {
        if (task.cancelRequested) {
          task.status = UploadStatus.canceled;
          return;
        }
        final len = partSize < task.size - offset ? partSize : task.size - offset;
        final bytes = await _readExact(raf, len);
        final etag = await _uploadPartWithRetry(task, session, partNumber, bytes, mime);
        etags.add(etag);
        offset += len;
        partNumber++;
        task.uploadedBytes = offset;
        notifyListeners();
      }

      // 5. 合并分片 + 完成登记
      task.stage = UploadStage.merging;
      await app.quark.uploadCommit(session: session, etags: etags, mime: mime);
      await app.quark.uploadFinish(
          objKey: session.objKey, taskId: session.taskId);
      await Future<void>.delayed(const Duration(seconds: 1));
      _finishDone(task);
    } catch (e) {
      if (task.cancelRequested) {
        task.status = UploadStatus.canceled;
      } else {
        task.status = UploadStatus.failed;
        task.error = e.toString();
        AppLogger.I.e('upload', '上传失败 ${task.fileName}: $e');
        unawaited(UploadNotifier.showFailed(task.fileName, e.toString()));
      }
      notifyListeners();
    } finally {
      await raf?.close();
      task.cancelToken = null;
    }
  }

  void _finishDone(UploadTask task) {
    task
      ..status = UploadStatus.done
      ..stage = UploadStage.queued
      ..uploadedBytes = task.size
      ..speed = 0;
    notifyListeners();
    unawaited(UploadNotifier.showDone(task.fileName));
  }

  // ---------------- 分片 ----------------

  Future<String> _uploadPartWithRetry(
    UploadTask task,
    QuarkUploadSession session,
    int partNumber,
    Uint8List bytes,
    String mime,
  ) async {
    const maxAttempts = 3;
    Object? lastErr;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await AppState.I.quark.uploadPart(
          session: session,
          partNumber: partNumber,
          bytes: bytes,
          mime: mime,
          cancelToken: task.cancelToken,
        );
      } catch (e) {
        lastErr = e;
        if (task.cancelRequested) rethrow;
        AppLogger.I.w('upload',
            '分片 $partNumber 第 $attempt 次失败: $e，稍后重试');
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    throw QuarkException(-1, '分片 $partNumber 上传失败: $lastErr');
  }

  Future<Uint8List> _readExact(RandomAccessFile raf, int len) async {
    final builder = BytesBuilder(copy: false);
    var remaining = len;
    while (remaining > 0) {
      final chunk = await raf.read(remaining);
      if (chunk.isEmpty) break;
      builder.add(chunk);
      remaining -= chunk.length;
    }
    return builder.takeBytes();
  }

  // ---------------- 哈希（分块推进进度） ----------------

  Future<(String, String)> _hashFile(File file, UploadTask task) async {
    final md5Capture = _DigestCapture();
    final sha1Capture = _DigestCapture();
    final md5Sink = md5.startChunkedConversion(md5Capture);
    final sha1Sink = sha1.startChunkedConversion(sha1Capture);
    final raf = await file.open();
    var processed = 0;
    try {
      while (true) {
        final chunk = await raf.read(_hashChunkSize);
        if (chunk.isEmpty) break;
        md5Sink.add(chunk);
        sha1Sink.add(chunk);
        processed += chunk.length;
        task.uploadedBytes = processed;
        // 每 16MB 或结束时刷新一次界面
        if (processed % (_hashChunkSize * 4) < _hashChunkSize ||
            processed >= task.size) {
          notifyListeners();
        }
      }
    } finally {
      await raf.close();
      md5Sink.close();
      sha1Sink.close();
    }
    return (md5Capture.digest!.toString(), sha1Capture.digest!.toString());
  }

  // ---------------- 远端目录 ----------------

  /// 解析相对目录对应的远端 fid（按需逐级创建）
  Future<String> _resolveDirFid(String relDir) async {
    if (!_folderBatch) return _baseDirFid;
    final cached = _dirFidCache[relDir];
    if (cached != null) return cached;
    final String fid;
    if (relDir.isEmpty) {
      fid = await AppState.I.quark.createFolder(_baseDirFid, _rootFolderName!);
    } else {
      final idx = relDir.lastIndexOf('/');
      final parentRel = idx < 0 ? '' : relDir.substring(0, idx);
      final parentFid = await _resolveDirFid(parentRel);
      final name = idx < 0 ? relDir : relDir.substring(idx + 1);
      fid = await AppState.I.quark.createFolder(parentFid, name);
    }
    _dirFidCache[relDir] = fid;
    return fid;
  }

  static String _basename(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx < 0 ? norm : norm.substring(idx + 1);
  }

  // ---------------- 速度采样 ----------------

  void _ensureSpeedTimer() {
    if (_speedTimer != null) return;
    _speedTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now();
      var changed = false;
      for (final t in tasks) {
        if (t.status != UploadStatus.uploading) continue;
        final dt = now.difference(t.lastSampleTs).inMilliseconds;
        if (dt <= 0) continue;
        final delta = t.uploadedBytes - t.lastSampleBytes;
        t.speed = delta > 0 ? delta / dt * 1000 : 0;
        t.lastSampleBytes = t.uploadedBytes;
        t.lastSampleTs = now;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      } else if (!hasActive) {
        _speedTimer?.cancel();
        _speedTimer = null;
      }
    });
  }
}

/// 捕获 Hash 分块转换的最终摘要（HashingSink 在 close 时下发最终 Digest）
class _DigestCapture implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
