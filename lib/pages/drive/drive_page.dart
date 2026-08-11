import 'package:flutter/material.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({super.key});

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with AutomaticKeepAliveClientMixin {
  List<QuarkFile> _files = [];
  String _pdirFid = '0';
  String _currentName = '全部文件';
  final List<(String, String)> _crumbs = [('0', '全部文件')];
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
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
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Text('网盘',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    _crumbs
                      ..clear()
                      ..add(('0', '全部文件'));
                    _pdirFid = '0';
                    _currentName = '全部文件';
                    _files = [];
                    _load();
                  },
                  icon: const Icon(Icons.home_rounded, color: AppColors.accent),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.accent),
                ),
              ],
            ),
          ),
          if (_crumbs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!AppState.I.isLoggedIn) {
      return const EmptyView(
        icon: Icons.lock_outline_rounded,
        text: '登录后查看网盘文件',
        subText: '请在「我的」页面登录夸克账号',
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

  Widget _buildItem(QuarkFile file) {
    return InkWell(
      onTap: () {
        if (file.isDir) {
          _enterDir(file);
        } else {
          _showFileActions(file);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
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
                    file.isDir
                        ? '文件夹'
                        : '${formatBytes(file.size)}  ·  ${formatDateTime(file.updatedAt * 1000)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
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
              leading: const Icon(Icons.download_rounded, color: AppColors.accent),
              title: const Text('立即下载'),
              subtitle: const Text('提取直链，多线程不限速下载'),
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
        connections: app.connections,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
