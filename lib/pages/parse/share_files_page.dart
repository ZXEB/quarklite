import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/quark_client.dart';
import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';

class ShareFilesPage extends StatefulWidget {
  final QuarkShareSession session;
  final List<QuarkShareFile> initialFiles;
  final String initialName;

  const ShareFilesPage({
    super.key,
    required this.session,
    required this.initialFiles,
    required this.initialName,
  });

  @override
  State<ShareFilesPage> createState() => _ShareFilesPageState();
}

class _ShareFilesPageState extends State<ShareFilesPage> {
  late List<QuarkShareFile> _files;
  String _dirFid = '0';
  final List<String> _stack = [];
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _files = widget.initialFiles;
  }

  Future<void> _openDir(QuarkShareFile dir) async {
    setState(() {
      _loading = true;
      _error = null;
      _stack.add(_dirFid);
      _dirFid = dir.fid;
    });
    try {
      final files =
          await AppState.I.quark.listShare(widget.session, _dirFid);
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
          _stack.removeLast();
          _dirFid = _stack.isEmpty ? '0' : _stack.last;
        });
      }
    }
  }

  void _back() {
    if (_stack.isEmpty) return;
    setState(() {
      _dirFid = _stack.removeLast();
      _files = widget.initialFiles;
      _error = null;
    });
    _reloadCurrent();
  }

  Future<void> _reloadCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await AppState.I.quark.listShare(widget.session, _dirFid);
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

  // ---------------- 多选 ----------------

  void _enterSelectMode(QuarkShareFile file) {
    setState(() {
      _selectMode = true;
      if (!file.isDir) _selected.add(file.fid);
    });
  }

  void _toggleSelect(QuarkShareFile file) {
    if (file.isDir) return;
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

  List<QuarkShareFile> _selectedFiles() {
    return _files.where((f) => _selected.contains(f.fid)).toList();
  }

  void _selectAllFiles() {
    final fileIds = _files.where((f) => !f.isDir).map((f) => f.fid).toSet();
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
    if (_selected.isEmpty || _busy) return;
    final msg = await _ensurePermission();
    if (msg != null) return;
    setState(() => _busy = true);
    try {
      final cookie = AppState.I.quark.downloadCookieSnapshot;
      final infos = await AppState.I.quark
          .getShareDownloadInfo(widget.session, _selected.toList());
      var added = 0;
      final total = infos.length;
      for (final info in infos) {
        if (info.url.isEmpty) continue;
        final err = await DownloadService.addDirectUrl(
          url: info.url,
          fileName: info.fileName,
          cookie: cookie,
          batchTotal: total,
        );
        if (err == null) added++;
      }
      _toast('已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } on QuarkException {
      _showSaveFallback();
    } catch (e) {
      _toast('批量下载失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batchSave() async {
    if (_selected.isEmpty || _busy) return;
    if (!AppState.I.isLoggedIn) {
      _toast('请先登录');
      return;
    }
    setState(() => _busy = true);
    try {
      await AppState.I.quark
          .saveShare(widget.session, _selectedFiles(), '0');
      _toast('已保存 ${_selected.length} 项到网盘根目录');
      _exitSelectMode();
    } catch (e) {
      _toast('保存失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: _selectMode
            ? '已选 ${_selected.length} 项'
            : _stack.isEmpty
                ? widget.initialName
                : _files.isEmpty
                    ? '文件夹'
                    : '分享内容',
        navigationIcon: MiuixIconButton(
          onPressed: () {
            if (_selectMode) {
              _exitSelectMode();
            } else if (_stack.isNotEmpty) {
              _back();
            } else {
              Navigator.pop(context);
            }
          },
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceVariant,
              size: 20),
        ),
        actions: [
          if (_selectMode)
            MiuixTextButton(
              '全选',
              onPressed: _selectAllFiles,
              colors: MiuixButtonColors(color: colors.primary),
            ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            if (_selectMode) _buildSelectBar(),
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
              '转存',
              onPressed: _busy || count == 0 ? null : _batchSave,
              colors: MiuixButtonColors(color: AppColors.green),
            ),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: _busy || count == 0 ? null : _batchDownload,
              colors: MiuixButtonColors(
                color: colors.primary,
                disabledColor: colors.primaryVariant,
                contentColor: Colors.white,
                disabledContentColor: Colors.white,
              ),
              child: _busy
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
    if (_error != null) {
      return BodySwitcher(
        child: EmptyView(
          icon: Icons.cloud_off_rounded,
          text: '加载失败',
          subText: _error,
          action: MiuixTextButton('重试', onPressed: _reloadCurrent),
        ),
      );
    }
    if (_loading && _files.isEmpty) {
      return BodySwitcher(child: const Center(child: MiuixCircularProgressIndicator()));
    }
    if (_files.isEmpty) {
      return BodySwitcher(child: const EmptyView(icon: Icons.folder_open_rounded, text: '这个文件夹是空的'));
    }
    final content = MiuixPullToRefresh(
      isRefreshing: _loading,
      onRefresh: _reloadCurrent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => StaggeredFileItem(index: i, child: _buildItem(_files[i])),
      ),
    );
    return BodySwitcher(child: content);
  }

  Widget _buildItem(QuarkShareFile file) {
    final selected = _selected.contains(file.fid);
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      onPressed: () {
        if (_selectMode) {
          _toggleSelect(file);
        } else if (file.isDir) {
          _openDir(file);
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

  void _showFileActions(QuarkShareFile file) {
    MiuixActionSheet.show<String>(
      context,
      title: file.fileName,
      actions: [
        (icon: Icons.download_rounded, text: '立即下载', value: 'download', color: null),
        (icon: Icons.save_alt_rounded, text: '保存到网盘', value: 'save', color: AppColors.green),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'download':
          _downloadFile(file);
        case 'save':
          _saveFile(file);
      }
    });
  }

  Future<void> _downloadFile(QuarkShareFile file) async {
    final msg = await _ensurePermission();
    if (msg != null) return;
    try {
      final cookie = AppState.I.quark.downloadCookieSnapshot;
      final infos = await AppState.I.quark
          .getShareDownloadInfo(widget.session, [file.fid]);
      if (infos.isEmpty) {
        throw QuarkException(-1, '未获取到下载地址');
      }
      final info = infos.first;
      final err = await DownloadService.addDirectUrl(
        url: info.url,
        fileName: info.fileName.isNotEmpty ? info.fileName : file.fileName,
        cookie: cookie,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } on QuarkException {
      _showSaveFallback(file);
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  /// 直链获取失败时降级：转存到网盘再下载
  void _showSaveFallback([QuarkShareFile? file]) {
    final single = file != null;
    confirmMiuix(
      context,
      title: '直链获取失败',
      content: single
          ? '该文件暂时无法获取直链，可以先保存到自己的网盘，再从网盘中下载。'
          : '所选文件暂时无法获取直链，可以先转存到自己的网盘，再从网盘中下载。',
      confirmText: '转存',
    ).then((ok) {
      if (ok != true) return;
      if (single) {
        _saveFile(file);
      } else {
        _batchSave();
      }
    });
  }

  Future<void> _saveFile(QuarkShareFile file) async {
    if (!AppState.I.isLoggedIn) {
      _toast('请先登录');
      return;
    }
    try {
      await AppState.I.quark
          .saveShare(widget.session, [file], '0');
      _toast('已保存到网盘根目录');
    } catch (e) {
      _toast('保存失败: $e');
    }
  }

  /// 存储权限检查，返回 null 表示可用
  Future<String?> _ensurePermission() async {
    final app = AppState.I;
    final ok = await app.canWriteDownload();
    if (ok) return null;
    if (!mounted) return '权限不足';
    final granted = await confirmMiuix(
      context,
      title: '需要存储权限',
      content: '下载文件需要「所有文件访问」权限，请授权后继续。',
      confirmText: '去授权',
    );
    if (granted == true) app.openAllFilesAccess();
    return '未授权存储权限';
  }

  void _toast(String msg) {
    if (!mounted) return;
    MiuixToast.show(msg);
  }
}
