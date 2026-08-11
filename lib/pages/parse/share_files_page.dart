import 'package:flutter/material.dart';

import '../../api/quark_client.dart';
import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stack.isEmpty ? widget.initialName : _files.isEmpty ? '文件夹' : ''),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (_stack.isNotEmpty) {
              _back();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        text: '加载失败',
        subText: _error,
        action: OutlinedButton(
          onPressed: _reloadCurrent,
          child: const Text('重试'),
        ),
      );
    }
    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return const EmptyView(icon: Icons.folder_open_rounded, text: '这个文件夹是空的');
    }
    return RefreshIndicator(
      onRefresh: _reloadCurrent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildItem(_files[i]),
      ),
    );
  }

  Widget _buildItem(QuarkShareFile file) {
    return InkWell(
      onTap: () {
        if (file.isDir) {
          _openDir(file);
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
                    file.isDir ? '文件夹' : formatBytes(file.size),
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

  void _showFileActions(QuarkShareFile file) {
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
            ListTile(
              leading: const Icon(Icons.save_alt_rounded, color: AppColors.green),
              title: const Text('保存到网盘'),
              subtitle: const Text('转存到自己的夸克网盘'),
              onTap: () {
                Navigator.pop(ctx);
                _saveFile(file);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
        connections: AppState.I.connections,
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
  void _showSaveFallback(QuarkShareFile file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('直链获取失败'),
        content: const Text('该文件暂时无法获取直链，可以先保存到自己的网盘，再从网盘中下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveFile(file);
            },
            child: const Text('保存到网盘'),
          ),
        ],
      ),
    );
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
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.openAllFilesAccess();
            },
            child: const Text('去授权'),
          ),
        ],
      ),
    );
    return '未授权存储权限';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
