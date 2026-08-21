import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

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
import '../../widgets/miuix_common.dart';
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
      final granted = await confirmMiuix(
        context,
        title: '需要存储权限',
        content: '下载文件需要「所有文件访问」权限，请授权后继续。',
        confirmText: '去授权',
      );
      if (granted != true) return;
      app.openAllFilesAccess();
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
    final newName = await miuixInputDialog(
      context,
      title: '重命名',
      hint: '输入新名称',
      initialText: file.fileName,
    );
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
    final ok = await confirmMiuix(
      context,
      title: '删除确认',
      content: '确定删除选中的 ${fids.length} 项吗？删除后将移入回收站。',
      confirmText: '删除',
      danger: true,
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
    final name = await miuixInputDialog(
      context,
      title: '新建文件夹',
      hint: '输入文件夹名称',
      confirmText: '创建',
    );
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
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '夸克网盘',
        navigationIcon: _selectMode
            ? null
            : MiuixIconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: MiuixIcon(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tint: colors.onSurfaceVariant,
                    size: 20),
              ),
        actions: _selectMode
            ? [
                MiuixTextButton(
                  '全选',
                  onPressed: _selectAllFiles,
                  colors: MiuixButtonColors(color: colors.primary),
                ),
                MiuixIconButton(
                  onPressed: _exitSelectMode,
                  child: MiuixIcon(
                      icon: Icons.close_rounded, tint: colors.primary),
                ),
              ]
            : [
                MiuixIconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                  child: MiuixIcon(icon: Icons.search_rounded, tint: colors.primary),
                ),
                MiuixIconButton(
                  onPressed: _showUploadMenu,
                  child: MiuixIcon(icon: Icons.upload_rounded, tint: colors.primary),
                ),
                MiuixIconButton(
                  onPressed: _load,
                  child: MiuixIcon(icon: Icons.refresh_rounded, tint: colors.primary),
                ),
                MiuixIconButton(
                  onPressed: _confirmLogout,
                  child: MiuixIcon(icon: Icons.logout_rounded, tint: colors.primary),
                ),
              ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_crumbs.length > 1) _buildBreadcrumb(context, colors),
            Expanded(child: _buildBody()),
            if (_selectMode) _buildSelectBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context, MiuixColors colors) {
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
                    _crumbs[i].$2,
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
                fontSize: 14, color: colors.onSurfaceVariant),
            const Spacer(),
            MiuixTextButton(
              '删除',
              onPressed: _busy || count == 0 ? null : () => _deleteFiles(_selected),
              colors: MiuixButtonColors(color: AppColors.red),
            ),
            const SizedBox(width: 10),
            MiuixTextButton(
              '移动到',
              onPressed: _busy || count == 0 ? null : () => _moveFiles(_selected),
              colors: MiuixButtonColors(color: colors.primary),
            ),
            const SizedBox(width: 10),
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
                  : MiuixText('下载($count)',
                      color: Colors.white, fontSize: 14),
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

  Widget _buildItem(QuarkFile file) {
    final selected = _selected.contains(file.fid);
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      onPressed: () {
        if (_selectMode) {
          _toggleSelect(file);
        } else if (file.isDir) {
          _enterDir(file);
        } else {
          _showFileActions(file);
        }
      },
      onLongPress: _selectMode ? null : () => _enterSelectMode(file),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            FileIcon(isDir: file.isDir, name: file.fileName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  const SizedBox(height: 4),
                  MiuixText(
                    file.isDir ? '文件夹' : formatBytes(file.size),
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

  void _showFileActions(QuarkFile file) {
    MiuixActionSheet.show<String>(
      context,
      title: file.fileName,
      actions: [
        (icon: Icons.download_rounded, text: '立即下载', value: 'download', color: null),
        (icon: Icons.drive_file_move_rounded, text: '移动到', value: 'move', color: null),
        (icon: Icons.drive_file_rename_outline_rounded, text: '重命名', value: 'rename', color: null),
        (icon: Icons.delete_outline_rounded, text: '删除', value: 'delete', color: AppColors.red),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'download':
          _downloadFile(file);
        case 'move':
          _moveFiles({file.fid});
        case 'rename':
          _renameFile(file);
        case 'delete':
          _deleteFiles({file.fid});
      }
    });
  }

  Future<void> _downloadFile(QuarkFile file) async {
    final app = AppState.I;
    final ok = await app.canWriteDownload();
    if (!ok) {
      if (!mounted) return;
      final granted = await confirmMiuix(
        context,
        title: '需要存储权限',
        content: '下载文件需要「所有文件访问」权限，请授权后继续。',
        confirmText: '去授权',
      );
      if (granted != true) return;
      app.openAllFilesAccess();
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
    MiuixActionSheet.show<String>(
      context,
      title: '上传到「${_crumbs.last.$2}」',
      actions: [
        (icon: Icons.create_new_folder_rounded, text: '新建文件夹', value: 'folder', color: null),
        (icon: Icons.upload_file_rounded, text: '上传文件', value: 'file', color: null),
        (icon: Icons.create_new_folder_rounded, text: '上传文件夹', value: 'dir', color: null),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'folder':
          _createFolder();
        case 'file':
          _pickFiles();
        case 'dir':
          _pickFolder();
      }
    });
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
    MiuixToast.show(msg);
  }

  Future<void> _confirmLogout() async {
    final ok = await confirmMiuix(
      context,
      title: '退出夸克网盘',
      content: '确定退出登录吗？退出后需要重新登录才能访问网盘文件。',
      confirmText: '退出',
      danger: true,
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
