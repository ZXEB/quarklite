import 'package:flutter/material.dart';

import '../../api/netdisk123_client.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

/// 123 网盘文件浏览页（面包屑导航 + 多选批量下载）
class Netdisk123DrivePage extends StatefulWidget {
  const Netdisk123DrivePage({super.key});

  @override
  State<Netdisk123DrivePage> createState() => _Netdisk123DrivePageState();
}

class _Netdisk123DrivePageState extends State<Netdisk123DrivePage> {
  List<Netdisk123File> _files = [];
  String _parentId = Netdisk123Client.rootParentId;
  String _currentName = '全部文件';
  final List<(String, String)> _crumbs = [
    (Netdisk123Client.rootParentId, '全部文件'),
  ];
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _downloading = false;

  Netdisk123Client get _client => Netdisk123State.I.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Netdisk123State.I.isLoggedIn) {
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
      final files = await _client.listFiles(_parentId);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      AppLogger.I.e('netdisk123', '文件列表失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _enterDir(Netdisk123File dir) {
    setState(() {
      _crumbs.add((_parentId, _currentName));
      _parentId = dir.id;
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
      _currentName = _crumbs.last.$2;
      _files = [];
      _error = null;
      _selectMode = false;
      _selected.clear();
    });
    _load();
  }

  // ---------------- 多选下载 ----------------

  void _enterSelectMode(Netdisk123File file) {
    setState(() {
      _selectMode = true;
      _selected.add(file.id);
    });
  }

  void _toggleSelect(Netdisk123File file) {
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

  /// 展开选中项为 (file, 相对路径) 列表
  Future<List<(Netdisk123File, String)>> _expandSelection(
      Set<String> selected) async {
    final result = <(Netdisk123File, String)>[];
    for (final f in _files) {
      if (!selected.contains(f.id)) continue;
      if (f.isDir) {
        result.addAll(await _collectFiles(f.id, '${f.name}/'));
      } else {
        result.add((f, ''));
      }
    }
    return result;
  }

  Future<List<(Netdisk123File, String)>> _collectFiles(
      String parentId, String relPath,
      {int depth = 0}) async {
    if (depth > 8) return [];
    final files = await _client.listFiles(parentId);
    final result = <(Netdisk123File, String)>[];
    for (final f in files) {
      if (result.length >= 500) break;
      if (f.isDir) {
        result.addAll(await _collectFiles(
            f.id, '$relPath${f.name}/',
            depth: depth + 1));
      } else {
        result.add((f, relPath));
      }
    }
    return result;
  }

  /// 分批取直链并加入下载队列
  Future<int> _downloadFileList(List<(Netdisk123File, String)> items) async {
    final app = AppState.I;
    final base = await app.effectiveDownloadDir();
    var added = 0;
    const batchSize = 20;
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize) > items.length ? items.length : (i + batchSize);
      final batch = items.sublist(i, end);
      for (final (f, rel) in batch) {
        try {
          final url = await _client.getDownloadUrl(f);
          if (url.isEmpty) continue;
          final path = rel.isEmpty ? base : '$base/$rel';
          final err = await DownloadService.addDirectUrl(
            url: url,
            fileName: f.name,
            cookie: '',
            path: path,
            maxConnections: app.netdisk123Connections,
            batchTotal: items.length,
            referer: 'https://www.123pan.com/',
            userAgent: Netdisk123Client.ua,
          );
          if (err == null) added++;
        } catch (e) {
          AppLogger.I.e('netdisk123', '取直链失败 ${f.name}: $e');
        }
      }
    }
    return added;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('123 网盘'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: () => _confirmLogout(),
            icon: const Icon(Icons.logout_rounded, color: AppColors.accent),
            tooltip: '退出登录',
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
                            _crumbs[i].$2,
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
    if (!Netdisk123State.I.isLoggedIn) {
      return const EmptyView(
        icon: Icons.lock_outline_rounded,
        text: '未登录 123 网盘',
        subText: '请在网盘首页点击 123 网盘登录',
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

  Widget _buildItem(Netdisk123File file) {
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

  void _showFileActions(Netdisk123File file) {
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

  Future<void> _downloadFile(Netdisk123File file) async {
    try {
      final url = await _client.getDownloadUrl(file);
      if (url.isEmpty) {
        throw Exception('未获取到下载地址');
      }
      final app = AppState.I;
      final base = await app.effectiveDownloadDir();
      final err = await DownloadService.addDirectUrl(
        url: url,
        fileName: file.name,
        cookie: '',
        path: base,
        maxConnections: app.netdisk123Connections,
        referer: 'https://www.123pan.com/',
        userAgent: Netdisk123Client.ua,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      AppLogger.I.e('netdisk123', '下载失败 ${file.name}: $e');
      _toast('下载失败: $e');
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出 123 网盘'),
        content: const Text('确定退出登录吗？退出后需要重新登录才能访问网盘文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Netdisk123State.I.logout();
      if (mounted) {
        setState(() {
          _files = [];
          _parentId = Netdisk123Client.rootParentId;
          _currentName = '全部文件';
          _crumbs
            ..clear()
            ..add((Netdisk123Client.rootParentId, '全部文件'));
        });
        Navigator.of(context).pop();
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
