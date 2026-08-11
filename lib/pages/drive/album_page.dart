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

/// 相册：官方 file/category 接口分页拉取全部照片，滚动懒加载
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  static const _pageSize = 100;

  final List<QuarkFile> _photos = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  int _total = -1;

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_onLoginChanged);
    if (AppState.I.isLoggedIn) {
      _loadFirst();
    }
  }

  @override
  void dispose() {
    AppState.I.removeListener(_onLoginChanged);
    super.dispose();
  }

  void _onLoginChanged() {
    if (AppState.I.isLoggedIn && _photos.isEmpty && !_loading) {
      _loadFirst();
    } else if (!AppState.I.isLoggedIn && mounted) {
      setState(() {
        _photos.clear();
        _hasMore = true;
        _page = 1;
        _total = -1;
      });
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
      _photos.clear();
    });
    try {
      final list = await AppState.I.quark.listCategoryImages(
          page: 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _photos.addAll(list);
        _total = list.length < _pageSize ? list.length : -1;
        _hasMore = list.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    _loadingMore = true;
    try {
      final list = await AppState.I.quark.listCategoryImages(
          page: _page + 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _page++;
        _photos.addAll(list);
        _hasMore = list.length == _pageSize;
      });
    } catch (_) {
      // 加载更多失败静默，滚动可重试
    } finally {
      if (mounted) _loadingMore = false;
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
            onPressed: _loading ? null : _loadFirst,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
            tooltip: '刷新',
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
    if (_error != null && _photos.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        text: '加载失败',
        subText: _error,
        action: OutlinedButton(onPressed: _loadFirst, child: const Text('重试')),
      );
    }
    if (_loading && _photos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_photos.isEmpty) {
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
          child: Text(
            _total > 0 ? '共 $_total 张照片  ·  上滑加载更多' : '加载中…',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
            itemCount: _photos.length + (_hasMore ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= _photos.length) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final photo = _photos[i];
              if (i > _photos.length - 20) {
                _loadMore();
              }
              return _buildTile(photo, i);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTile(QuarkFile photo, int index) {
    final thumb = photo.thumbnail;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerPage(
            photos: _photos,
            index: index,
          ),
        ),
      ),
      child: thumb.isNotEmpty
          ? Image.network(
              thumb,
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
                final thumb = p.bigThumbnail.isNotEmpty
                    ? p.bigThumbnail
                    : p.thumbnail;
                return Center(
                  child: thumb.isNotEmpty
                      ? InteractiveViewer(
                          maxScale: 5,
                          child: Image.network(
                            thumb,
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
                photo.fileName,
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
