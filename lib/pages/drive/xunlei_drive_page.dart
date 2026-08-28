import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/xunlei_client.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../utils/video_file.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
import '../player/playback_source.dart';
import '../player/video_player_page.dart';

/// 迅雷云盘文件浏览页（面包屑导航 + 多选批量下载）
class XunleiDrivePage extends StatefulWidget {
  const XunleiDrivePage({super.key});

  @override
  State<XunleiDrivePage> createState() => _XunleiDrivePageState();
}

class _XunleiDrivePageState extends State<XunleiDrivePage> {
  List<XunleiFile> _files = [];
  String _parentId = XunleiClient.rootParentId;
  String _space = XunleiClient.rootSpace;
  String _currentName = '全部文件';
  final List<(String, String, String)> _crumbs = [(XunleiClient.rootParentId, XunleiClient.rootSpace, '全部文件')];
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _downloading = false;

  XunleiClient get _client => XunleiState.I.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!XunleiState.I.isLoggedIn) {
      setState(() {
        _files = [];
        _error = '未登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await _client.listFiles(_parentId, space: _space);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      AppLogger.I.e('xunlei', '文件列表失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _enterDir(XunleiFile dir) {
    setState(() {
      _crumbs.add((_parentId, _space, _currentName));
      _parentId = dir.id;
      _space = dir.space;
      _currentName = dir.name;
      _files = [];
      _loading = true;
    });
    _load();
  }

  void _toBreadcrumb(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(index + 1, _crumbs.length);
      _parentId = _crumbs.last.$1;
      _space = _crumbs.last.$2;
      _currentName = _crumbs.last.$3;
      _files = [];
      _error = null;
      _selectMode = false;
      _selected.clear();
    });
    _load();
  }

  // ---------------- 多选下载 ----------------

  void _enterSelectMode(XunleiFile file) {
    setState(() {
      _selectMode = true;
      _selected.add(file.id);
    });
  }

  void _toggleSelect(XunleiFile file) {
    setState(() {
      if (!_selected.remove(file.id)) {
        _selected.add(file.id);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  Future<void> _batchDownload() async {
    if (_selected.isEmpty || _downloading) return;
    setState(() => _downloading = true);
    _toast('正在扫描文件夹…');
    try {
      final items = await _expandSelection(_selected);
      if (items.isEmpty) {
        _toast('没有可下载的文件');
        return;
      }
      final added = await _downloadFileList(items);
      _toast('已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } catch (e) {
      _toast('批量下载失败: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// 展开选中项为 (id, space, 相对路径) 列表
  Future<List<(String, String, String)>> _expandSelection(
      Set<String> selected) async {
    final result = <(String, String, String)>[];
    for (final f in _files) {
      if (!selected.contains(f.id)) continue;
      if (f.isDir) {
        result.addAll(await _collectFiles(f.id, f.space, '${f.name}/'));
      } else {
        result.add((f.id, f.space, ''));
      }
    }
    return result;
  }

  Future<List<(String, String, String)>> _collectFiles(
      String id, String space, String relPath,
      {int depth = 0}) async {
    if (depth > 8) return [];
    final files = await _client.listFiles(id, space: space);
    final result = <(String, String, String)>[];
    for (final f in files) {
      if (result.length >= 500) break;
      if (f.isDir) {
        result.addAll(await _collectFiles(
            f.id, f.space, '$relPath${f.name}/',
            depth: depth + 1));
      } else {
        result.add((f.id, f.space, relPath));
      }
    }
    return result;
  }

  /// 分批取直链并加入下载队列
  Future<int> _downloadFileList(List<(String, String, String)> items) async {
    final app = AppState.I;
    final base = await app.effectiveDownloadDir();
    var added = 0;
    const batchSize = 20;
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize) > items.length ? items.length : (i + batchSize);
      final batch = items.sublist(i, end);
      final files = await _client.getDownloadFiles(
          batch.map((e) => (e.$1, e.$2)).toList());
      for (final (id, _, rel) in batch) {
        final f = files[id];
        if (f == null) continue;
        final url = f.downloadUrlFor();
        if (url.isEmpty) continue;
        final path = rel.isEmpty ? base : '$base/$rel';
        final err = await DownloadService.addDirectUrl(
          url: url,
          fileName: f.name,
          cookie: '',
          path: path,
          maxConnections: app.xunleiConnections,
          batchTotal: items.length,
          referer: 'https://pan.xunlei.com/',
          userAgent: XunleiClient.downloadUa,
        );
        if (err == null) added++;
      }
    }
    return added;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '迅雷云盘',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
        actions: [
          MiuixIconButton(
            onPressed: _load,
            child: MiuixIcon(icon: Icons.refresh_rounded, tint: colors.primary),
          ),
          MiuixIconButton(
            onPressed: () => _confirmLogout(),
            child: MiuixIcon(icon: Icons.logout_rounded, tint: colors.primary),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_crumbs.length > 1) _buildBreadcrumb(colors),
            Expanded(child: _buildBody()),
            if (_selectMode) _buildSelectBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _crumbs.length; i++) ...[
              if (i > 0)
                MiuixIcon(
                    icon: Icons.chevron_right_rounded,
                    size: 16,
                    tint: colors.onSurfaceSecondary),
              MiuixPressable(
                onPressed: () => _toBreadcrumb(i),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: MiuixText(
                    _crumbs[i].$3,
                    fontSize: 13,
                    color: i == _crumbs.length - 1
                        ? colors.primary
                        : colors.onSurfaceSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectBar() {
    final count = _selected.length;
    final colors = MiuixTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(top: BorderSide(color: colors.dividerLine, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            MiuixText('已选 $count 项',
                fontSize: 14, color: colors.onSurfaceContainer),
            const Spacer(),
            MiuixButton(
              onPressed: _downloading || count == 0 ? null : _batchDownload,
              colors: MiuixButtonColors(
                color: colors.primary,
                disabledColor: colors.primaryVariant,
                contentColor: Colors.white,
                disabledContentColor: Colors.white,
              ),
              child: _downloading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: MiuixCircularProgressIndicator(
                          size: 16,
                          colors: MiuixProgressIndicatorColors(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            backgroundColor: Colors.white24,
                          )),
                    )
                  : MiuixText('下载($count)', color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!XunleiState.I.isLoggedIn) {
      return BodySwitcher(child: const EmptyView(icon: Icons.lock_outline_rounded, text: '未登录迅雷云盘', subText: '请在网盘首页点击迅雷云盘登录'));
    }
    if (_error != null && _files.isEmpty) {
      return BodySwitcher(child: EmptyView(icon: Icons.cloud_off_rounded, text: '加载失败', subText: _error, action: MiuixTextButton('重试', onPressed: _load)));
    }
    if (_loading && _files.isEmpty) {
      return BodySwitcher(child: const Center(child: MiuixCircularProgressIndicator()));
    }
    if (_files.isEmpty) {
      return BodySwitcher(child: const EmptyView(icon: Icons.folder_open_rounded, text: '这里空空如也'));
    }
    final content = MiuixPullToRefresh(
      isRefreshing: _loading,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => StaggeredFileItem(index: i, child: _buildItem(_files[i])),
      ),
    );
    return BodySwitcher(child: content);
  }

  Widget _buildItem(XunleiFile file) {
    final selected = _selected.contains(file.id);
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      onPressed: () {
        if (_selectMode) {
          _toggleSelect(file);
        } else if (file.isDir) {
          _enterDir(file);
        } else if (isVideoFileName(file.name)) {
          _playFile(file);
        } else {
          _showFileActions(file);
        }
      },
      onLongPress: _selectMode ? null : () => _enterSelectMode(file),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            FileIcon(isDir: file.isDir, name: file.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: colors.onSurfaceContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  const SizedBox(height: 4),
                  MiuixText(
                    file.isDir ? '文件夹' : '${formatBytes(file.size)}',
                    color: colors.onSurfaceSecondary,
                    fontSize: 12,
                  ),
                ],
              ),
            ),
            if (_selectMode)
              MiuixIcon(
                icon: selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                tint: selected ? colors.primary : colors.onSurfaceSecondary,
                size: 22,
              )
            else
              MiuixIcon(
                  icon: Icons.chevron_right_rounded,
                  tint: colors.onSurfaceSecondary,
                  size: 20),
          ],
        ),
      ),
    );
  }

  void _showFileActions(XunleiFile file) {
    MiuixActionSheet.show<String>(
      context,
      title: file.name,
      actions: [
        if (isVideoFileName(file.name))
          (
            icon: Icons.play_circle_fill_rounded,
            text: '在线播放',
            value: 'play',
            color: null,
          ),
        (icon: Icons.download_rounded, text: '立即下载', value: 'download', color: null),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'play':
          _playFile(file);
        case 'download':
          _downloadFile(file);
      }
    });
  }

  /// 在线播放：同目录下同名外挂字幕一并带入（按需解析）。
  void _playFile(XunleiFile file) {
    final base = fileNameWithoutExtension(file.name);
    final subs = <String, (String, String)>{};
    for (final f in _files) {
      if (!f.isDir &&
          f.id != file.id &&
          isSubtitleFileName(f.name) &&
          fileNameWithoutExtension(f.name) == base) {
        subs[f.name] = (f.id, f.space);
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerPage(
        request: PlaybackRequest.xunlei(
            id: file.id,
            space: file.space,
            fileName: file.name,
            subtitleIdSpaces: subs),
      ),
    ));
  }

  Future<void> _downloadFile(XunleiFile file) async {
    try {
      final detail = await _client.getFileDetail(file.id, space: file.space);
      final url = detail.downloadUrlFor();
      if (url.isEmpty) {
        throw Exception('未获取到下载地址');
      }
      final app = AppState.I;
      final base = await app.effectiveDownloadDir();
      final err = await DownloadService.addDirectUrl(
        url: url,
        fileName: detail.name,
        cookie: '',
        path: base,
        maxConnections: app.xunleiConnections,
        referer: 'https://pan.xunlei.com/',
        userAgent: XunleiClient.downloadUa,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      AppLogger.I.e('xunlei', '下载失败 ${file.name}: $e');
      _toast('下载失败: $e');
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await confirmMiuix(
      context,
      title: '退出迅雷云盘',
      content: '确定退出登录吗？退出后需要重新登录才能访问网盘文件。',
      confirmText: '退出',
      danger: true,
    );
    if (ok == true) {
      await XunleiState.I.logout();
      if (mounted) {
        setState(() {
          _files = [];
          _parentId = XunleiClient.rootParentId;
          _space = XunleiClient.rootSpace;
          _currentName = '全部文件';
          _crumbs
            ..clear()
            ..add((XunleiClient.rootParentId, XunleiClient.rootSpace, '全部文件'));
        });
        Navigator.of(context).pop();
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    MiuixToast.show(msg);
  }
}
