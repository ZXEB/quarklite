import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/netdisk123_client.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';
import 'netdisk123_pay_page.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../utils/video_file.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
import '../player/playback_source.dart';
import '../player/video_player_page.dart';

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
      // 同 drive_page：压入新目录，避免路径落后一级且根目录重复
      _crumbs.add((dir.id, dir.name));
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

  Future<Netdisk123Account?> _pickAccountForDownload() async {
    final s = Netdisk123State.I;
    if (s.accounts.isEmpty) {
      _toast('未登录');
      return null;
    }
    if (s.accounts.length == 1) return s.active ?? s.accounts.first;
    final picked = await MiuixActionSheet.show<Netdisk123Account>(
      context,
      title: '选择下载账号',
      actions: [
        for (final a in s.accounts)
          (
            icon: s.activeId == a.id
                ? Icons.check_circle_rounded
                : Icons.account_circle_rounded,
            text: s.activeId == a.id ? '${a.username}（当前活跃）' : a.username,
            value: a,
            color: s.activeId == a.id ? AppColors.accent : null,
          ),
      ],
    );
    return picked;
  }

  Future<void> _showTrafficExhausted(Netdisk123Account acc) async {
    final go = await confirmMiuix(
      context,
      title: '流量不足',
      content: '账号「${acc.username}」本月免费流量已用完，是否购买流量包（0.5 元起）？',
      confirmText: '去充值',
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const Netdisk123PayPage()),
      );
    }
  }

  bool _isTrafficExhausted(Object e) =>
      e is Netdisk123Exception && e.code == 5113;

  Future<void> _batchDownload() async {
    if (_selected.isEmpty || _downloading) return;
    final picked = await _pickAccountForDownload();
    if (picked == null) return;
    if (picked.id != Netdisk123State.I.activeId) {
      await Netdisk123State.I.setActive(picked.id);
    }
    setState(() => _downloading = true);
    _toast('正在扫描文件夹…');
    try {
      final items = await _expandSelection(_selected);
      if (items.isEmpty) {
        _toast('没有可下载的文件');
        return;
      }
      final added = await _downloadFileList(items, picked);
      if (added == -1) return; // 已弹流量不足
      _toast('已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } catch (e) {
      if (_isTrafficExhausted(e)) {
        await _showTrafficExhausted(picked);
      } else {
        _toast('批量下载失败: $e');
      }
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

  /// 分批取直链并加入下载队列；返回 -1 表示遇到 5113 已弹窗
  Future<int> _downloadFileList(List<(Netdisk123File, String)> items,
      Netdisk123Account picked) async {
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
          if (_isTrafficExhausted(e)) {
            await _showTrafficExhausted(picked);
            return -1;
          }
          AppLogger.I.e('netdisk123', '取直链失败 ${f.name}: $e');
        }
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
        title: '123 网盘',
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
    if (!Netdisk123State.I.isLoggedIn) {
      return BodySwitcher(child: const EmptyView(icon: Icons.lock_outline_rounded, text: '未登录 123 网盘', subText: '请在网盘首页点击 123 网盘登录'));
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

  Widget _buildItem(Netdisk123File file) {
    final selected = _selected.contains(file.id);
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

  void _showFileActions(Netdisk123File file) {
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
  void _playFile(Netdisk123File file) {
    final base = fileNameWithoutExtension(file.name);
    final subs = <String, Netdisk123File>{};
    for (final f in _files) {
      if (!f.isDir &&
          f.id != file.id &&
          isSubtitleFileName(f.name) &&
          fileNameWithoutExtension(f.name) == base) {
        subs[f.name] = f;
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerPage(
        request:
            PlaybackRequest.netdisk123(file: file, subtitleFiles: subs),
      ),
    ));
  }

  Future<void> _downloadFile(Netdisk123File file) async {
    final picked = await _pickAccountForDownload();
    if (picked == null) return;
    if (picked.id != Netdisk123State.I.activeId) {
      await Netdisk123State.I.setActive(picked.id);
    }
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
      if (_isTrafficExhausted(e)) {
        await _showTrafficExhausted(picked);
        return;
      }
      AppLogger.I.e('netdisk123', '下载失败 ${file.name}: $e');
      _toast('下载失败: $e');
    }
  }

  Future<void> _confirmLogout() async {
    final s = Netdisk123State.I;
    if (s.accounts.length > 1) {
      final choice = await MiuixActionSheet.show<String>(
        context,
        title: '退出 123 网盘',
        actions: [
          (icon: Icons.account_circle_rounded, text: '退出当前（${s.active?.username ?? ''}）', value: 'active', color: null),
          (icon: Icons.logout_rounded, text: '退出全部账号', value: 'all', color: AppColors.red),
        ],
      );
      if (choice == 'active') {
        await s.logoutActive();
        if (s.accounts.isEmpty && mounted) Navigator.of(context).pop();
        if (mounted) setState(() {});
      } else if (choice == 'all') {
        await s.logout();
        if (mounted) {
          setState(() {
            _files = [];
            _parentId = Netdisk123Client.rootParentId;
            _currentName = '全部文件';
            _crumbs..clear()..add((Netdisk123Client.rootParentId, '全部文件'));
          });
          Navigator.of(context).pop();
        }
      }
      return;
    }
    final ok = await confirmMiuix(
      context,
      title: '退出 123 网盘',
      content: '确定退出登录吗？退出后需要重新登录才能访问网盘文件。',
      confirmText: '退出',
      danger: true,
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
    MiuixToast.show(msg);
  }
}
