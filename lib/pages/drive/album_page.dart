import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/permission.dart';
import '../../utils/types.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import 'search_page.dart';

class AlbumPhoto {
  final String fid;
  final String name;
  final String thumbnail;
  final int size;
  final int updatedAt;

  const AlbumPhoto({
    required this.fid,
    required this.name,
    required this.thumbnail,
    required this.size,
    required this.updatedAt,
  });

  factory AlbumPhoto.fromQuarkFile(QuarkFile f) => AlbumPhoto(
        fid: f.fid,
        name: f.fileName,
        thumbnail: f.thumbnail,
        size: f.size,
        updatedAt: f.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'fid': fid,
        'name': name,
        'thumbnail': thumbnail,
        'size': size,
        'updatedAt': updatedAt,
      };

  factory AlbumPhoto.fromJson(Map<String, dynamic> json) => AlbumPhoto(
        fid: json['fid']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        thumbnail: json['thumbnail']?.toString() ?? '',
        size: toInt(json['size']),
        updatedAt: toInt(json['updatedAt']),
      );
}

/// 相册：并行递归扫描网盘照片，带本地缓存（秒开）
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  static const _cacheKey = 'album_cache';
  static const _workerCount = 5;
  static const _maxFolders = 5000;

  final List<AlbumPhoto> _photos = [];
  final Set<String> _seenFids = {};
  final List<String> _queue = [];
  bool _scanning = false;
  bool _scanStarted = false;
  bool _cached = false;
  String? _error;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_onLoginChanged);
    _loadCache();
    if (AppState.I.isLoggedIn) {
      _startScan();
    }
  }

  @override
  void dispose() {
    AppState.I.removeListener(_onLoginChanged);
    super.dispose();
  }

  void _onLoginChanged() {
    if (AppState.I.isLoggedIn && !_scanStarted) {
      _startScan();
    } else if (!AppState.I.isLoggedIn && mounted) {
      setState(() {
        _photos.clear();
        _scanStarted = false;
        _cached = false;
        _lastScanTime = null;
      });
    }
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AlbumPhoto.fromJson(e.cast<String, dynamic>()))
          .toList();
      final time = toInt(data['time']);
      if (!mounted) return;
      setState(() {
        _photos
          ..clear()
          ..addAll(items);
        _cached = items.isNotEmpty;
        if (time > 0) _lastScanTime = DateTime.fromMillisecondsSinceEpoch(time);
      });
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'time': DateTime.now().millisecondsSinceEpoch,
        'items': _photos.map((p) => p.toJson()).toList(),
      }),
    );
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanStarted = true;
      _scanning = true;
      _error = null;
      _photos.clear();
      _seenFids.clear();
      _queue
        ..clear()
        ..add('0');
    });

    Future<void> worker() async {
      while (_queue.isNotEmpty) {
        final fid = _queue.removeAt(0);
        try {
          final files = await AppState.I.quark.listFiles(fid);
          if (!mounted) return;
          for (final f in files) {
            if (f.isDir) {
              if (_queue.length < _maxFolders) _queue.add(f.fid);
            } else if (f.isImage && _seenFids.add(f.fid)) {
              _photos.add(AlbumPhoto.fromQuarkFile(f));
            }
          }
          setState(() {});
        } catch (e) {
          _error = e.toString();
        }
      }
    }

    await Future.wait(
        List.generate(_workerCount, (_) => worker()));
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _lastScanTime = DateTime.now();
      _cached = _photos.isNotEmpty;
    });
    await _saveCache();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
            icon: const Icon(Icons.search_rounded, color: AppColors.accent),
            tooltip: '搜索照片内容',
          ),
          IconButton(
            onPressed: _scanning ? null : _startScan,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
            tooltip: '重新扫描',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!AppState.I.isLoggedIn) {
      return const EmptyView(
        icon: Icons.lock_outline_rounded,
        text: '登录后查看相册',
        subText: '请在「我的」页面登录夸克账号',
      );
    }
    if (_photos.isEmpty) {
      if (_scanning) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在扫描网盘照片…',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        );
      }
      if (_error != null) {
        return EmptyView(
          icon: Icons.cloud_off_rounded,
          text: '扫描失败',
          subText: _error,
          action: OutlinedButton(
            onPressed: _startScan,
            child: const Text('重试'),
          ),
        );
      }
      return const EmptyView(
        icon: Icons.photo_library_outlined,
        text: '没有找到照片',
        subText: '把照片上传到夸克网盘后即可在这里查看',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _scanning
                    ? '扫描中… 已找到 ${_photos.length} 张'
                    : '共 ${_photos.length} 张'
                        '${_lastScanTime != null ? '  ·  更新于 ${_timeStr(_lastScanTime!)}' : ''}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              if (_cached && !_scanning)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: InkWell(
                    onTap: _startScan,
                    child: const Text('刷新',
                        style: TextStyle(color: AppColors.accent, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _photos.length,
            itemBuilder: (_, i) => _buildTile(_photos[i], i),
          ),
        ),
      ],
    );
  }

  String _timeStr(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.month}/${t.day}';
  }

  Widget _buildTile(AlbumPhoto photo, int index) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerPage(
            photos: _photos,
            index: index,
          ),
        ),
      ),
      child: photo.thumbnail.isNotEmpty
          ? Image.network(
              photo.thumbnail,
              fit: BoxFit.cover,
              headers: quarkImageHeaders(),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      color: AppColors.card,
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
              errorBuilder: (_, _, _) => Container(
                color: AppColors.card,
                child: Center(
                  child: FileIcon(isDir: false, name: photo.name, size: 36),
                ),
              ),
            )
          : Container(
              color: AppColors.card,
              child: Center(
                child: FileIcon(isDir: false, name: photo.name, size: 36),
              ),
            ),
    );
  }
}

/// 全屏照片查看器
class PhotoViewerPage extends StatefulWidget {
  final List<AlbumPhoto> photos;
  final int index;

  const PhotoViewerPage({super.key, required this.photos, required this.index});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.index;
    _controller = PageController(initialPage: widget.index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _download(AlbumPhoto photo) async {
    final ok = await ensureStoragePermission(context);
    if (!ok) return;
    if (!mounted) return;
    final err =
        await DownloadService.downloadQuarkFile(photo.fid, fileName: photo.name);
    if (!mounted) return;
    if (err != null) {
      toast(context, err);
      return;
    }
    toast(context, '已加入下载队列');
    DownloadManager.I.startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_current];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '${_current + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            onPressed: () => _download(photo),
            icon: const Icon(Icons.download_rounded, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final p = widget.photos[i];
                return Center(
                  child: p.thumbnail.isNotEmpty
                      ? InteractiveViewer(
                          maxScale: 5,
                          child: Image.network(
                            p.thumbnail,
                            fit: BoxFit.contain,
                            headers: quarkImageHeaders(),
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                        child: CircularProgressIndicator()),
                            errorBuilder: (_, _, _) => const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.white54,
                                size: 56),
                          ),
                        )
                      : const Icon(Icons.broken_image_rounded,
                          color: Colors.white54, size: 56),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                photo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
