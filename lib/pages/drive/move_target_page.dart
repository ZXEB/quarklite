import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';

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
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '移动到',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.pop(context),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            _buildBreadcrumb(colors),
            Expanded(child: _buildBody()),
            _buildMoveBar(),
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

  Widget _buildBody() {
    if (_error != null) {
      return BodySwitcher(
        child: EmptyView(
          icon: Icons.cloud_off_rounded,
          text: '加载失败',
          subText: _error,
          action: MiuixTextButton('重试', onPressed: _load),
        ),
      );
    }
    if (_loading && _files.isEmpty) {
      return BodySwitcher(child: const Center(child: MiuixCircularProgressIndicator()));
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
        final colors = MiuixTheme.of(context).colors;
        return StaggeredFileItem(index: i, child: MiuixCard(
          onPressed: blocked ? null : () => _enterDir(dir),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FileIcon(isDir: true, name: dir.fileName),
                const SizedBox(width: 12),
                Expanded(
                  child: MiuixText(
                    dir.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: blocked
                        ? colors.onSurfaceSecondary
                        : colors.onSurfaceContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                MiuixIcon(
                    icon: Icons.chevron_right_rounded,
                    tint: colors.onSurfaceSecondary,
                    size: 20),
              ],
            ),
          ),
        ));
      },
    );
    return content;
  }

  Widget _buildMoveBar() {
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
            Expanded(
              child: MiuixText(
                '移动到「${_crumbs.last.$2}」',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: colors.onSurfaceContainer,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 12),
            MiuixButton(
              onPressed: () => Navigator.pop(context, _dirFid),
              colors: MiuixButtonColors(
                color: colors.primary,
                disabledColor: colors.primary,
                contentColor: Colors.white,
                disabledContentColor: Colors.white,
              ),
              child: MiuixText('移动到此处', color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
