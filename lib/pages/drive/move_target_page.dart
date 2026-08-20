import 'package:flutter/material.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';

/// 选择移动目标目录页：只展示文件夹，禁止进入被移动的文件夹内部，
/// 底部固定「移动到此处」按钮返回目标 fid（根目录 fid 为 '0'）。
class MoveTargetPage extends StatefulWidget {
  /// 被移动的文件 fid 集合（含文件夹本身），用于禁止移入自身
  final Set<String> movedFids;

  const MoveTargetPage({super.key, required this.movedFids});

  @override
  State<MoveTargetPage> createState() => _MoveTargetPageState();
}

class _MoveTargetPageState extends State<MoveTargetPage> {
  String _dirFid = '0';
  final List<(String, String)> _crumbs = [('0', '全部文件')];
  List<QuarkFile> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await AppState.I.quark.listFiles(_dirFid);
      if (mounted) {
        setState(() {
          _files = files.where((f) => f.isDir).toList();
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

  void _enterDir(QuarkFile dir) {
    if (widget.movedFids.contains(dir.fid)) return;
    setState(() {
      _crumbs.add((_dirFid, dir.fileName));
      _dirFid = dir.fid;
      _files = [];
      _loading = true;
    });
    _load();
  }

  void _toBreadcrumb(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(index + 1, _crumbs.length);
      _dirFid = _crumbs.last.$1;
      _files = [];
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('移动到'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
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
          _buildMoveBar(),
        ],
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
        action: OutlinedButton(onPressed: _load, child: const Text('重试')),
      ));
    }
    if (_loading && _files.isEmpty) {
      return BodySwitcher(child: const Center(child: CircularProgressIndicator()));
    }
    if (_files.isEmpty) {
      return BodySwitcher(
          child: const EmptyView(icon: Icons.folder_open_rounded, text: '这里没有文件夹'));
    }
    final content = ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final dir = _files[i];
        final blocked = widget.movedFids.contains(dir.fid);
        return StaggeredFileItem(index: i, child: InkWell(
          onTap: blocked ? null : () => _enterDir(dir),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                FileIcon(isDir: true, name: dir.fileName),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dir.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: blocked
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoveBar() {
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
            Expanded(
              child: Text(
                '移动到「${_crumbs.last.$2}」',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, _dirFid),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('移动到此处'),
            ),
          ],
        ),
      ),
    );
  }
}
