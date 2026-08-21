import 'package:flutter/material.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/permission.dart';
import '../../utils/upload_picker.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/file_icon.dart';
import 'move_target_page.dart';
import 'search_page.dart';

class DrivePage extends StatefulWidget {
  final String initialDirFid;
  final String initialName;

  const DrivePage({
    super.key,
    this.initialDirFid = '0',
    this.initialName = '全部文件',
  });

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with AutomaticKeepAliveClientMixin {
  List<QuarkFile> _files = [];
  late String _pdirFid = widget.initialDirFid;
  late String _currentName = widget.initialName;
  late final List<(String, String)> _crumbs = [
    (widget.initialDirFid, widget.initialName)
  ];
  bool _loading = false;
  String? _error;
  bool? _lastLoggedIn;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _downloading = false;
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_onLoginChanged);
    _load();
  }

  @override
  void dispose() {
    AppState.I.removeListener(_onLoginChanged);
    super.dispose();
  }

  void _onLoginChanged() {
    final logged = AppState.I.isLoggedIn;
    if (logged == _lastLoggedIn) return;
    _lastLoggedIn = logged;
    if (mounted) {
      setState(() {
        _selectMode = false;
        _selected.clear();
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (!AppState.I.isLoggedIn) {
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
      final files = await AppState.I.quark.listFiles(_pdirFid);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _enterDir(QuarkFile dir) async {
    setState(() {
      _crumbs.add((_pdirFid, _currentName));
      _pdirFid = dir.fid;
      _currentName = dir.fileName;
      _files = [];
      _loading = true;
    });
    try {
      final files = await AppState.I.quark.listFiles(_pdirFid);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _toBreadcrumb(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(index + 1, _crumbs.length);
      _pdirFid = _crumbs.last.$1;
      _currentName = _crumbs.last.$2;
      _files = [];
      _error = null;
      _selectMode = false;
      _selected.clear();
    });
    _load();
  }

  // ---------------- 多选 ----------------

  void _enterSelectMode(QuarkFile file) {
    setState(() {
      _selectMode = true;
      _selected.add(file.fid);
    });
  }

  void _toggleSelect(QuarkFile file) {
    setState(() {
      if (!_selected.remove(file.fid)) {
        _selected.add(file.fid);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _selectAllFiles() {
    final fileIds = _files.map((f) => f.fid).toSet();
    setState(() {
      if (_selected.length == fileIds.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(fileIds);
      }
    });
  }

  Future<void> _batchDownload() async {
    if (_selected.isEmpty || _downloading) return;
    final app = AppState.I;
    final ok = await app.canWriteDownload();
    if (!ok) {
      if (!mounted) return;
      final granted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要存储权限'),
          content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, true);
                app.openAllFilesAccess();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (granted != true) return;
      _toast('授权完成后请重新下载');
      return;
    }
    setState(() => _downloading = true);
    _toast('正在扫描文件夹…');
    try {
      final fids = await _expandSelection(_selected);
      if (fids.isEmpty) {
        _toast('没有可下载的文件');
        return;
      }
      final added = await _downloadFileList(fids);
      _toast('已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } catch (e) {
      _toast('批量下载失败: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ---------------- 文件管理 ----------------

  /// 校验重命名名称（去掉首尾空白，禁止为空与特殊字符）
  String? _validateName(String name) {
    if (name.isEmpty) return '名称不能为空';
    if (name.contains('/') || name.contains('\\')) return '名称不能包含 / 或 \\';
    return null;
  }

  Future<void> _renameFile(QuarkFile file) async {
    final controller = TextEditingController(text: file.fileName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          decoration: const InputDecoration(hintText: '输入新名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || !mounted) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      _toast('名称不能为空');
      return;
    }
    if (trimmed == file.fileName) return;
    final err = _validateName(trimmed);
    if (err != null) {
      _toast(err);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppState.I.quark.renameFile(file.fid, trimmed);
      _toast('已重命名');
      _load();
    } catch (e) {
      _toast('重命名失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveFiles(Set<String> fids) async {
    if (fids.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final toFid = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => MoveTargetPage(movedFids: fids),
        ),
      );
      if (!mounted || toFid == null) return;
      if (toFid == _pdirFid) {
        _toast('目标目录与当前目录相同');
        return;
      }
      await AppState.I.quark.moveFiles(fids.toList(), toFid);
      _toast('已移动 ${fids.length} 项');
      _exitSelectMode();
      _load();
    } catch (e) {
      _toast('移动失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFiles(Set<String> fids) async {
    if (fids.isEmpty || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除选中的 ${fids.length} 项吗？删除后将移入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AppState.I.quark.deleteFiles(fids.toList());
      _toast('已删除 ${fids.length} 项');
      _exitSelectMode();
      _load();
    } catch (e) {
      _toast('删除失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFolder() async {
    if (!AppState.I.isLoggedIn || _busy) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          decoration: const InputDecoration(hintText: '输入文件夹名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _toast('名称不能为空');
      return;
    }
    final err = _validateName(trimmed);
    if (err != null) {
      _toast(err);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppState.I.quark.createFolder(_pdirFid, trimmed);
      _toast('已创建文件夹');
      _load();
    } catch (e) {
      _toast('创建失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把选中的文件/文件夹展开为 (fid, 相对路径) 列表（文件夹递归收集）
  Future<List<(String, String)>> _expandSelection(Set<String> selected) async {
    final result = <(String, String)>[];
    for (final f in _files) {
      if (!selected.contains(f.fid)) continue;
      if (f.isDir) {
        result.addAll(await _collectFiles(f.fid, '${f.fileName}/'));
      } else {
        result.add((f.fid, ''));
      }
    }
    return result;
  }

  /// 分批获取直链并加入下载队列（每批 50 个，避免接口超限）。
  /// [files] 为 (fid, 相对路径) 列表，相对路径为空表示下载到根目录。
  Future<int> _downloadFileList(List<(String, String)> files) async {
    final app = AppState.I;
    final base = await app.effectiveDownloadDir();
    var added = 0;
    const batchSize = 50;
    final total = files.length;
    for (var i = 0; i < files.length; i += batchSize) {
      final end = (i + batchSize) > files.length ? files.length : (i + batchSize);
      final batch = files.sublist(i, end);
      final (infos, cookie) =
          await app.quark.getDownloadInfo(batch.map((e) => e.$1).toList());
      final pathByFid = {for (final e in batch) e.$1: e.$2};
      for (final info in infos) {
        if (info.url.isEmpty) continue;
        final rel = pathByFid[info.fid] ?? '';
        // 保持网盘目录结构：下载到 根目录/相对路径/
        final path = rel.isEmpty ? base : '$base/$rel';
        final err = await DownloadService.addDirectUrl(
          url: info.url,
          fileName: info.fileName,
          path: path,
          cookie: cookie,
          batchTotal: total,
        );
        if (err == null) added++;
      }
    }
    return added;
  }

  /// 递归收集文件夹内所有文件，返回 (fid, 相对路径)
  /// （限制层数与数量，避免超大目录卡死）
  Future<List<(String, String)>> _collectFiles(String fid, String relPath,
      {int depth = 0}) async {
    if (depth > 8) return [];
    final files = await AppState.I.quark.listFiles(fid);
    final result = <(String, String)>[];
    for (final f in files) {
      if (result.length >= 500) break;
      if (f.isDir) {
        result.addAll(
            await _collectFiles(f.fid, '$relPath${f.fileName}/', depth: depth + 1));
      } else {
        result.add((f.fid, relPath));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('夸克网盘'),
        actions: _selectMode
            ? [
                TextButton(
                  onPressed: _selectAllFiles,
                  child: const Text('全选',
                      style: TextStyle(color: AppColors.accent)),
                ),
                IconButton(
                  onPressed: _exitSelectMode,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.accent),
                ),
              ]
            : [
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                  icon: const Icon(Icons.search_rounded,
                      color: AppColors.accent),
                  tooltip: '搜索',
                ),
                IconButton(
                  onPressed: _showUploadMenu,
                  icon: const Icon(Icons.upload_rounded,
                      color: AppColors.accent),
                  tooltip: '上传',
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.accent),
                  tooltip: '刷新',
                ),
                IconButton(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout_rounded,
                      color: AppColors.accent),
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
        color: AppColors.bottomBar,
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
            OutlinedButton.icon(
              onPressed: _busy || count == 0 ? null : () => _deleteFiles(_selected),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: BorderSide(color: AppColors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _busy || count == 0 ? null : () => _moveFiles(_selected),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.drive_file_move_rounded, size: 18),
              label: const Text('移动到'),
            ),
            const SizedBox(width: 10),
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
    if (!AppState.I.isLoggedIn) {
      return BodySwitcher(child: const EmptyView(icon: Icons.lock_outline_rounded, text: '登录后查看网盘文件', subText: '请在「我的」页面登录夸克账号'));
    }
    if (_error != null && _files.isEmpty) {
      return BodySwitcher(child: EmptyView(icon: Icons.cloud_off_rounded, text: '加载失败', subText: _error, action: OutlinedButton(onPressed: _load, child: const Text('重试'))));
    }
    if (_loading && _files.isEmpty) {
      return BodySwitcher(child: const Center(child: CircularProgressIndicator()));
    }
    if (_files.isEmpty) {
      return BodySwitcher(child: const EmptyView(icon: Icons.folder_open_rounded, text: '这里空空如也'));
    }
    final content = RefreshIndicator(
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

  Widget _buildItem(QuarkFile file) {
    final selected = _selected.contains(file.fid);
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
            FileIcon(isDir: file.isDir, name: file.fileName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.isDir ? '文件夹' : formatBytes(file.size),
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

  void _showFileActions(QuarkFile file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            FileIcon(isDir: false, name: file.fileName, size: 52),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                file.fileName,
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
              leading: Icon(Icons.download_rounded, color: AppColors.accent),
              title: const Text('立即下载'),
              subtitle: const Text('提取直链，多线程不限速下载'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadFile(file);
              },
            ),
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.drive_file_move_rounded,
              title: '移动到',
              subtitle: '转移到其他文件夹',
              onTap: () {
                Navigator.pop(ctx);
                _moveFiles({file.fid});
              },
            ),
            const Divider(height: 1),
            _actionTile(
              icon: Icons.drive_file_rename_outline_rounded,
              title: '重命名',
              subtitle: null,
              onTap: () {
                Navigator.pop(ctx);
                _renameFile(file);
              },
            ),
            _actionTile(
              icon: Icons.delete_outline_rounded,
              title: '删除',
              subtitle: null,
              color: AppColors.red,
              onTap: () {
                Navigator.pop(ctx);
                _deleteFiles({file.fid});
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color color = AppColors.accent,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(color: AppColors.textSecondary)),
      onTap: onTap,
    );
  }

  Future<void> _downloadFile(QuarkFile file) async {
    final app = AppState.I;
    final ok = await app.canWriteDownload();
    if (!ok) {
      if (!mounted) return;
      final granted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要存储权限'),
          content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, true);
                app.openAllFilesAccess();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (granted != true) return;
      _toast('授权完成后请重新点击下载');
      return;
    }
    try {
      final (infos, cookie) =
          await app.quark.getDownloadInfo([file.fid]);
      if (infos.isEmpty) {
        throw Exception('未获取到下载地址');
      }
      final info = infos.first;
      final err = await DownloadService.addDirectUrl(
        url: info.url,
        fileName: info.fileName,
        cookie: cookie,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  // ---------------- 上传 ----------------

  void _showUploadMenu() {
    if (!AppState.I.isLoggedIn) {
      _toast('请先登录夸克账号');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded,
                  color: AppColors.accent),
              title: const Text('新建文件夹'),
              subtitle: const Text('在当前目录创建新文件夹'),
              onTap: () {
                Navigator.pop(ctx);
                _createFolder();
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.upload_file_rounded, color: AppColors.accent),
              title: const Text('上传文件'),
              subtitle: const Text('支持一次选择多个文件，上传到当前目录'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded,
                  color: AppColors.accent),
              title: const Text('上传文件夹'),
              subtitle: const Text('保持目录结构上传到当前目录'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFolder();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final sources = await UploadPicker.pickFiles();
      if (!mounted) return;
      if (sources.isEmpty) return;
      UploadManager.I.addFiles(sources, _pdirFid);
      _toast('已加入 ${sources.length} 个上传任务，可在「上传」页查看进度');
    } catch (e) {
      _toast('选择文件失败: $e');
    }
  }

  Future<void> _pickFolder() async {
    final FolderPickResult result;
    try {
      result = await UploadPicker.pickFolder();
    } catch (e) {
      _toast('选择文件夹失败: $e');
      return;
    }
    if (!mounted) return;
    if (result.canceled) return;
    if (result.needPermission) {
      await ensureStoragePermission(context, purpose: '上传文件夹');
      if (mounted) _toast('授权完成后请重新选择文件夹');
      return;
    }
    if (result.error != null) {
      _toast(result.error!);
      return;
    }
    if (result.files.isEmpty && result.emptyDirs.isEmpty) {
      _toast('所选文件夹为空');
      return;
    }
    UploadManager.I.addFolderBatch(
      files: result.files,
      emptyDirs: result.emptyDirs,
      targetDirFid: _pdirFid,
      rootFolderName: result.rootName,
    );
    _toast('已加入 ${result.files.length} 个上传任务，可在「上传」页查看进度');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出夸克网盘'),
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
      await AppState.I.logout();
      if (mounted) {
        setState(() {
          _files = [];
          _pdirFid = '0';
          _currentName = '全部文件';
          _crumbs
            ..clear()
            ..add(('0', '全部文件'));
          _selectMode = false;
          _selected.clear();
        });
        Navigator.of(context).pop();
      }
    }
  }
}
