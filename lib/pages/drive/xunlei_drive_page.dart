import 'package:flutter/material.dart';

import '../../api/xunlei_client.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

/// 迅雷云盘文件浏览页（面包屑导航 + 多选批量下载）
class XunleiDrivePage extends StatefulWidget {
  const XunleiDrivePage({super.key});

  @override
  State<XunleiDrivePage> createState() => _XunleiDrivePageState();
}

class _XunleiDrivePageState extends State<XunleiDrivePage> {
  List<XunleiFile> _files = [];
  String _parentId = '0';
  String _space = XunleiClient.rootSpace;
  String _currentName = '全部文件';
  final List<(String, String, String)> _crumbs = [('0', XunleiClient.rootSpace, '全部文件')];
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
      final links = await _client.getDownloadLinks(
          batch.map((e) => (e.$1, e.$2)).toList());
      for (final (id, _, rel) in batch) {
        final url = links[id];
        if (url == null || url.isEmpty) continue;
        final name = _nameOf(id) ?? 'file_$id';
        final path = rel.isEmpty ? base : '$base/$rel';
        final err = await DownloadService.addDirectUrl(
          url: url,
          fileName: name,
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

  String? _nameOf(String id) {
    for (final f in _files) {
      if (f.id == id) return f.name;
    }
    return null;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('迅雷云盘'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_crumbs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _crumbs.length; i++) ...[
                      if (i > 0)
                        const Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.textSecondary),
                      InkWell(
                        onTap: () => _toBreadcrumb(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: Text(
                            _crumbs[i].$3,
                            style: TextStyle(
                              fontSize: 13,
                              color: i == _crumbs.length - 1
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody()),
          if (_selectMode) _buildSelectBar(),
        ],
      ),
    );
  }

  Widget _buildSelectBar() {
    final count = _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text('已选 $count 项',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _downloading || count == 0 ? null : _batchDownload,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.accentDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _downloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text('下载($count)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!XunleiState.I.isLoggedIn) {
      return const EmptyView(
        icon: Icons.lock_outline_rounded,
        text: '未登录迅雷云盘',
        subText: '请在网盘首页点击迅雷云盘登录',
      );
    }
    if (_error != null && _files.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        text: '加载失败',
        subText: _error,
        action: OutlinedButton(onPressed: _load, child: const Text('重试')),
      );
    }
    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return const EmptyView(
          icon: Icons.folder_open_rounded, text: '这里空空如也');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildItem(_files[i]),
      ),
    );
  }

  Widget _buildItem(XunleiFile file) {
    final selected = _selected.contains(file.id);
    return InkWell(
      onTap: () {
        if (_selectMode) {
          _toggleSelect(file);
        } else if (file.isDir) {
          _enterDir(file);
        } else {
          _showFileActions(file);
        }
      },
      onLongPress: _selectMode ? null : () => _enterSelectMode(file),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDeep : AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            FileIcon(isDir: file.isDir, name: file.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.isDir
                        ? '文件夹'
                        : '${formatBytes(file.size)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_selectMode)
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.accent : AppColors.textSecondary,
                size: 22,
              )
            else
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showFileActions(XunleiFile file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            FileIcon(isDir: false, name: file.name, size: 52),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text(formatBytes(file.size),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppColors.accent),
              title: const Text('立即下载'),
              subtitle: const Text('高速直链，多线程不限速下载'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadFile(file);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(XunleiFile file) async {
    try {
      final detail = await _client.getFileDetail(file.id, space: file.space);
      if (detail.webContentLink.isEmpty) {
        throw Exception('未获取到下载地址');
      }
      final app = AppState.I;
      final base = await app.effectiveDownloadDir();
      final err = await DownloadService.addDirectUrl(
        url: detail.webContentLink,
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
