import 'package:flutter/material.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/permission.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import 'search_page.dart';

/// 相册：递归扫描网盘中的全部照片，网格展示
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final List<QuarkFile> _photos = [];
  final Set<String> _seenFids = {};
  final List<String> _queue = [];
  bool _scanning = false;
  bool _scanStarted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_onLoginChanged);
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
      });
    }
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
    while (_queue.isNotEmpty) {
      final fid = _queue.removeAt(0);
      try {
        final files = await AppState.I.quark.listFiles(fid);
        if (!mounted) return;
        for (final f in files) {
          if (f.isDir) {
            _queue.add(f.fid);
          } else if (f.isImage && _seenFids.add(f.fid)) {
            _photos.add(f);
          }
        }
        setState(() {});
      } catch (e) {
        _error = e.toString();
      }
    }
    if (mounted) {
      setState(() => _scanning = false);
    }
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
        if (_scanning)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('扫描中… 已找到 ${_photos.length} 张',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
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

  Widget _buildTile(QuarkFile photo, int index) {
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
                  child: FileIcon(isDir: false, name: photo.fileName, size: 36),
                ),
              ),
            )
          : Container(
              color: AppColors.card,
              child: Center(
                child: FileIcon(isDir: false, name: photo.fileName, size: 36),
              ),
            ),
    );
  }
}

/// 全屏照片查看器
class PhotoViewerPage extends StatefulWidget {
  final List<QuarkFile> photos;
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

  Future<void> _download(QuarkFile photo) async {
    final ok = await ensureStoragePermission(context);
    if (!ok) return;
    if (!mounted) return;
    final err = await DownloadService.downloadQuarkFile(photo.fid,
        fileName: photo.fileName);
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
                photo.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
