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

enum AlbumFilter { all, photo, screenshot, live }

/// 相册：官方 file/category 分页 + 时间轴跳转 + 年月分组 + 筛选 + 动态照片
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  static const _pageSize = 100;
  static const _tileGap = 4.0;
  static const _headerH = 36.0;
  static const _axisW = 34.0;

  final List<QuarkFile> _photos = [];
  final Set<String> _seenFids = {};
  final ScrollController _scroll = ScrollController();

  bool _loading = false;
  bool _loadingMore = false;
  bool _imgHasMore = true;
  bool _videoLoaded = false;
  int _imgPage = 0;
  int _vidPage = 0;
  String? _error;

  AlbumFilter _filter = AlbumFilter.all;

  // 时间轴
  List<({String key, String label, int startIndex, double offset, double extent})>
      _monthIndex = [];
  String _axisDragMonth = '';
  double _axisDragFraction = 0;
  String _liveMonth = '';

  List<QuarkFile> get _filtered {
    if (_filter == AlbumFilter.all) return _photos;
    return _photos.where((f) {
      switch (_filter) {
        case AlbumFilter.all:
          return true;
        case AlbumFilter.photo:
          return f.isImage && !f.isScreenshot;
        case AlbumFilter.screenshot:
          return f.isImage && f.isScreenshot;
        case AlbumFilter.live:
          return f.isLivePhoto;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_onLoginChanged);
    _scroll.addListener(_updateLiveMonth);
    if (AppState.I.isLoggedIn) {
      _loadFirst();
    }
  }

  @override
  void dispose() {
    AppState.I.removeListener(_onLoginChanged);
    _scroll.dispose();
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
      if (_photos[mid].albumTime >= f.albumTime) {
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
      while (!_videoLoaded && _vidPage < 40) {
        final videos = await AppState.I.quark
            .listCategoryVideos(page: _vidPage + 1, size: _pageSize);
        _vidPage++;
        if (videos.isEmpty) {
          _videoLoaded = true;
          break;
        }
        for (final f in videos) {
          if (f.isLivePhoto) _insertSorted(f);
        }
        if (videos.length < _pageSize) {
          _videoLoaded = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _videoLoaded = true;
        _rebuildMonthIndex();
      });
      _updateLiveMonth();
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
        _rebuildMonthIndex();
      });
    } catch (_) {
    } finally {
      if (mounted) _loadingMore = false;
    }
  }

  void _rebuildMonthIndex() {
    final index = <({String key, String label, int startIndex, double offset, double extent})>[];
    double offset = 0;
    String? curKey;
    int curStart = 0;
    int curCount = 0;
    double tileSize = 0;
    void flush() {
      if (curKey == null) return;
      final rows = (curCount / 3).ceil();
      final h = tileSize * rows + _tileGap * (rows - 1) + _headerH;
      index.add((
        key: curKey,
        label: curKey,
        startIndex: curStart,
        offset: offset,
        extent: h,
      ));
      offset += h;
    }

    final width = MediaQuery.of(context).size.width - _axisW;
    tileSize = (width - _tileGap * 2) / 3;
    for (var i = 0; i < _photos.length; i++) {
      final f = _photos[i];
      final t = DateTime.fromMillisecondsSinceEpoch(f.albumTime);
      final key = '${t.year}-${t.month}';
      if (key != curKey) {
        flush();
        curKey = key;
        curStart = i;
        curCount = 0;
      }
      curCount++;
    }
    flush();
    _monthIndex = index;
  }

  String _monthLabel(String key) {
    final p = key.split('-');
    return '${p[0]}年${int.parse(p[1])}月';
  }

  void _updateLiveMonth() {
    if (_monthIndex.isEmpty) return;
    final pos = _scroll.hasClients ? _scroll.offset : 0;
    String cur = _monthIndex.last.label;
    for (final m in _monthIndex) {
      if (pos >= m.offset) {
        cur = m.label;
      } else {
        break;
      }
    }
    if (cur != _liveMonth && mounted) {
      setState(() => _liveMonth = cur);
    }
  }

  // ---------- 筛选 ----------

  void _setFilter(AlbumFilter f) {
    if (_filter == f) return;
    setState(() => _filter = f);
    if (f == AlbumFilter.screenshot) {
      _autoScanScreenshots();
    }
  }

  int get _screenshotCount =>
      _photos.where((x) => x.isImage && x.isScreenshot).length;

  Future<void> _autoScanScreenshots() async {
    while (_imgHasMore && _screenshotCount < 200) {
      await _loadMoreImages();
      if (!mounted) return;
      // 限速：避免突发大量分页请求触发接口限流
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  bool get _scanningScreenshots =>
      _filter == AlbumFilter.screenshot &&
      _imgHasMore &&
      _screenshotCount < 200;

  // ---------- 时间轴跳转 ----------

  void _axisDrag(double dy, double height) {
    if (_monthIndex.isEmpty) return;
    final frac = (dy / height).clamp(0.0, 0.999);
    final idx = (frac * _monthIndex.length).floor();
    final month = _monthIndex[idx];
    setState(() {
      _axisDragFraction = frac;
      _axisDragMonth = _monthLabel(month.key);
    });
  }

  void _axisJump() {
    if (_axisDragMonth.isEmpty || _monthIndex.isEmpty) return;
    final target = _monthIndex.firstWhere(
      (m) => _monthLabel(m.key) == _axisDragMonth,
      orElse: () => _monthIndex.last,
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(target.offset.clamp(0.0, _scroll.position.maxScrollExtent));
    }
    setState(() {
      _axisDragMonth = '';
      _axisDragFraction = 0;
    });
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
    final filtered = _filtered;
    final liveCount = _photos.where((f) => f.isLivePhoto).length;
    return Stack(
      children: [
        Column(
          children: [
            _buildFilterBar(liveCount),
            if (_scanningScreenshots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('正在筛选中… 已找到 $_screenshotCount 张截图',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyView(
                      icon: Icons.photo_library_outlined, text: '筛选结果为空')
                  : _buildTimeline(filtered),
            ),
          ],
        ),
        // 滚动中的月份气泡
        if (_liveMonth.isNotEmpty && _axisDragMonth.isEmpty)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_liveMonth,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        // 拖动时间轴时的气泡
        if (_axisDragMonth.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.cardLight.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(_axisDragMonth,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterBar(int liveCount) {
    final total = _photos.length;
    final photoCount =
        _photos.where((f) => f.isImage && !f.isScreenshot).length;
    final shotCount = _screenshotCount;
    final items = [
      (AlbumFilter.all, '全部', total),
      (AlbumFilter.photo, '照片', photoCount),
      (AlbumFilter.screenshot, '截图', shotCount),
      (AlbumFilter.live, '动态', liveCount),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          for (final (f, label, count) in items) ...[
            if (f != AlbumFilter.all) const SizedBox(width: 8),
            InkWell(
              onTap: () => _setFilter(f),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _filter == f ? AppColors.accent : AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _filter == f ? '$label $count' : label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _filter == f
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight:
                        _filter == f ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 时间轴分组网格 ----------

  Widget _buildTimeline(List<QuarkFile> filtered) {
    final groups = <
        ({String key, String label, List<(QuarkFile, int)> items})>[];
    for (var i = 0; i < filtered.length; i++) {
      final f = filtered[i];
      final t = DateTime.fromMillisecondsSinceEpoch(f.albumTime);
      final key = '${t.year}-${t.month}';
      if (groups.isEmpty || groups.last.key != key) {
        groups.add((key: key, label: _monthLabel(key), items: []));
      }
      groups.last.items.add((f, i));
    }
    return Row(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              for (final g in groups)
                SliverMainAxisGroup(slivers: [
                  SliverToBoxAdapter(child: _buildMonthHeader(g.label)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: _tileGap,
                        crossAxisSpacing: _tileGap,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final (photo, index) = g.items[i];
                          if (filtered.length > 200 &&
                              index > filtered.length - 25) {
                            _loadMoreImages();
                          }
                          return _buildTile(photo, index);
                        },
                        childCount: g.items.length,
                      ),
                    ),
                  ),
                ]),
              if (_imgHasMore && _filter == AlbumFilter.all)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        _buildTimeAxis(),
      ],
    );
  }

  Widget _buildMonthHeader(String label) {
    return Container(
      height: _headerH,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildTimeAxis() {
    if (_monthIndex.isEmpty) return const SizedBox(width: _axisW);
    final labels = _monthIndex.reversed.toList();
    return SizedBox(
      width: _axisW,
      child: GestureDetector(
        onVerticalDragUpdate: (d) {
          final box = context.findRenderObject() as RenderBox?;
          final h = box == null ? 400.0 : box.size.height;
          _axisDrag(d.globalPosition.dy, h);
        },
        onVerticalDragEnd: (_) => _axisJump(),
        onTapUp: (d) {
          final box = context.findRenderObject() as RenderBox?;
          final h = box == null ? 400.0 : box.size.height;
          _axisDrag(d.localPosition.dy, h);
          _axisJump();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (_, c) {
              final itemH = c.maxHeight / labels.length;
              return Column(
                children: [
                  for (final m in labels)
                    SizedBox(
                      height: itemH,
                      child: Center(
                        child: Text(
                          _shortMonth(m.key),
                          style: TextStyle(
                            fontSize: 9,
                            color: _axisDragFraction > 0 &&
                                    _monthLabel(m.key) == _axisDragMonth
                                ? AppColors.accent
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _shortMonth(String key) {
    final p = key.split('-');
    final y = p[0].substring(2);
    return '$y/${int.parse(p[1])}';
  }

  Widget _buildTile(QuarkFile photo, int index) {
    final live = photo.isLivePhoto;
    final shot = photo.isScreenshot;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerPage(
            photos: _filtered,
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
            const Positioned(
              left: 4,
              top: 4,
              child: Badge2(label: '动态'),
            )
          else if (shot)
            const Positioned(
              left: 4,
              top: 4,
              child: Badge2(label: '截图'),
            ),
        ],
      ),
    );
  }
}

class Badge2 extends StatelessWidget {
  final String label;
  const Badge2({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}

/// 全屏查看器：图片（查看原图）+ 动态照片视频播放
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

  /// 预览质量：preview_url（高分辨率 CDN）> big_thumbnail > thumbnail
  String _displayUrl(QuarkFile f) {
    final orig = _origUrls[f.fid];
    if (orig != null && orig.isNotEmpty) return orig;
    if (f.previewUrl.isNotEmpty) return f.previewUrl;
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
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(infos.first.url),
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
