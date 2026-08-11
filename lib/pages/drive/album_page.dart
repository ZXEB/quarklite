import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/permission.dart';
import '../../utils/quark_image.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import 'search_page.dart';

/// 相册：官方 file/category 接口分页 + 滚动视口懒加载 + 磁盘缓存 + 动态照片
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  static const _pageSize = 100;

  final List<QuarkFile> _photos = []; // 按 updatedAt 倒序合并（图片+动态照片）
  final Set<String> _seenFids = {};
  bool _loading = false;
  bool _loadingMore = false;
  bool _imgHasMore = true;
  bool _videoLoaded = false;
  int _imgPage = 0;
  int _vidPage = 0;
  String? _error;

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
        _seenFids.clear();
        _imgHasMore = true;
        _videoLoaded = false;
        _imgPage = 0;
        _vidPage = 0;
      });
    }
  }

  void _insertSorted(QuarkFile f) {
    if (!_seenFids.add(f.fid)) return;
    int lo = 0, hi = _photos.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_photos[mid].updatedAt >= f.updatedAt) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _photos.insert(lo, f);
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
      _photos.clear();
      _seenFids.clear();
      _imgHasMore = true;
      _videoLoaded = false;
      _imgPage = 0;
      _vidPage = 0;
    });
    try {
      final images = await AppState.I.quark
          .listCategoryImages(page: 1, size: _pageSize);
      _imgPage = 1;
      _imgHasMore = images.length == _pageSize;
      for (final f in images) {
        _insertSorted(f);
      }
      // 动态照片：拉取全部短时视频（通常只有几页）
      while (!_videoLoaded && _vidPage < 20) {
        final videos = await AppState.I.quark
            .listCategoryVideos(page: _vidPage + 1, size: _pageSize);
        _vidPage++;
        if (videos.isEmpty) {
          _videoLoaded = true;
          break;
        }
        final live = videos.where((f) => f.isLivePhoto).toList();
        for (final f in live) {
          _insertSorted(f);
        }
        if (videos.length < _pageSize) {
          _videoLoaded = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _videoLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMoreImages() async {
    if (_loadingMore || !_imgHasMore || _loading) return;
    _loadingMore = true;
    try {
      final list = await AppState.I.quark
          .listCategoryImages(page: _imgPage + 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _imgPage++;
        _imgHasMore = list.length == _pageSize;
        for (final f in list) {
          _insertSorted(f);
        }
      });
    } catch (_) {
      // 静默，滚动可重试
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
    final liveCount = _photos.where((f) => f.isLivePhoto).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            '共 ${_photos.length} 项'
            '${liveCount > 0 ? '  ·  动态照片 $liveCount 张' : ''}'
            '${_imgHasMore ? '  ·  上滑加载更多' : ''}',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _photos.length + (_imgHasMore ? 1 : 0),
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
              if (i > _photos.length - 25) {
                _loadMoreImages();
              }
              return _buildTile(_photos[i], i);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTile(QuarkFile photo, int index) {
    final live = photo.isLivePhoto;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerPage(
            photos: _photos,
            index: index,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo.thumbnail.isNotEmpty)
            QuarkImage(photo.thumbnail, fileName: photo.fileName)
          else
            Container(
              color: AppColors.card,
              child: Center(
                child:
                    FileIcon(isDir: false, name: photo.fileName, size: 36),
              ),
            ),
          if (live)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on_rounded,
                        color: Colors.white, size: 13),
                    SizedBox(width: 3),
                    Text('动态',
                        style:
                            TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 全屏查看器：图片（可查看原图）+ 动态照片视频播放
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
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoError = false;
  final Map<String, String> _origUrls = {};
  bool _loadingOrig = false;

  @override
  void initState() {
    super.initState();
    _current = widget.index;
    _controller = PageController(initialPage: widget.index);
  }

  @override
  void dispose() {
    _controller.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  QuarkFile get _photo => widget.photos[_current];

  String _displayUrl(QuarkFile f) {
    final orig = _origUrls[f.fid];
    if (orig != null && orig.isNotEmpty) return orig;
    return f.bigThumbnail.isNotEmpty ? f.bigThumbnail : f.thumbnail;
  }

  Future<void> _viewOriginal() async {
    final f = _photo;
    if (f.isLivePhoto) return;
    if (_origUrls[f.fid]?.isNotEmpty ?? false) {
      setState(() {});
      return;
    }
    setState(() => _loadingOrig = true);
    try {
      final (infos, _) = await AppState.I.quark.getDownloadInfo([f.fid]);
      if (infos.isNotEmpty && infos.first.url.isNotEmpty) {
        _origUrls[f.fid] = infos.first.url;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loadingOrig = false);
    if (_origUrls[f.fid] == null) {
      toast(context, '原图获取失败');
    }
  }

  Future<void> _playVideo() async {
    final f = _photo;
    if (_videoController != null) return;
    setState(() {
      _videoReady = false;
      _videoError = false;
    });
    try {
      final (infos, _) = await AppState.I.quark.getDownloadInfo([f.fid]);
      if (infos.isEmpty || infos.first.url.isEmpty) {
        throw Exception('获取视频地址失败');
      }
      final url = infos.first.url;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: quarkImageHeaders(),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _videoReady = true;
      });
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _videoError = true);
    }
  }

  Future<void> _download() async {
    final f = _photo;
    final ok = await ensureStoragePermission(context);
    if (!ok) return;
    if (!mounted) return;
    final err = await DownloadService.downloadQuarkFile(f.fid,
        fileName: f.fileName);
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
    final photo = _photo;
    final isLive = photo.isLivePhoto;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '${_current + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          if (!isLive)
            TextButton(
              onPressed: _loadingOrig ? null : _viewOriginal,
              child: _loadingOrig
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      (_origUrls[photo.fid]?.isNotEmpty ?? false)
                          ? '原图'
                          : '查看原图',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
            ),
          IconButton(
            onPressed: _download,
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
              onPageChanged: (i) {
                setState(() {
                  _current = i;
                  _videoController?.dispose();
                  _videoController = null;
                  _videoReady = false;
                  _videoError = false;
                });
              },
              itemBuilder: (_, i) => _buildPage(widget.photos[i]),
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

  Widget _buildPage(QuarkFile f) {
    final isLive = f.isLivePhoto;
    final display = _displayUrl(f);
    if (isLive && _videoReady && _videoController != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    return GestureDetector(
      onTap: isLive && !_videoReady ? _playVideo : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: display.isNotEmpty
                ? InteractiveViewer(
                    maxScale: 5,
                    child: _origUrls.containsKey(f.fid)
                        ? Image.network(
                            display,
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
                          )
                        : QuarkImage(
                            display,
                            fit: BoxFit.contain,
                            fileName: f.fileName,
                            placeholder: (_) => const Center(
                                child: CircularProgressIndicator()),
                          ),
                  )
                : const Icon(Icons.broken_image_rounded,
                    color: Colors.white54, size: 56),
          ),
          if (isLive && !_videoReady)
            Center(
              child: _videoError
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.white54, size: 40),
                        SizedBox(height: 8),
                        Text('动态照片播放失败',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 40),
                    ),
            ),
        ],
      ),
    );
  }
}
