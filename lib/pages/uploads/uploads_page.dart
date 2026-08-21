import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';

class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key});

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage>
    with AutomaticKeepAliveClientMixin {
  int _filter = 0;
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  UploadManager get _um => UploadManager.I;

  List<UploadTask> _applyFilter(List<UploadTask> all) {
    return switch (_filter) {
      1 => all
          .where((t) =>
              t.status == UploadStatus.pending ||
              t.status == UploadStatus.uploading)
          .toList(),
      2 => all.where((t) => t.status == UploadStatus.done).toList(),
      3 => all.where((t) => t.status == UploadStatus.failed).toList(),
      4 => all.where((t) => t.status == UploadStatus.paused).toList(),
      _ => all,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: UploadManager.I,
      builder: (context, _) {
        final um = UploadManager.I;
        final all = um.tasks;
        final active = um.activeCount;
        final paused = um.tasks.where((t) => t.status == UploadStatus.paused).length;
        final done = um.doneCount;
        final failed = um.failedCount;

        final filtered = _applyFilter(all);

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    MiuixText(_selectMode ? '批量操作' : '上传管理',
                        fontSize: 24, fontWeight: FontWeight.w800),
                    const Spacer(),
                    if (_selectMode)
                      Row(
                        children: [
                          MiuixTextButton(
                            _isAllSelected(filtered) ? '全不选' : '全选',
                            onPressed: () => setState(() {
                              final allIds =
                                  filtered.map((t) => t.id).toSet();
                              if (_selected.length == allIds.length &&
                                  allIds.isNotEmpty) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(allIds);
                              }
                            }),
                            colors: MiuixButtonColors(
                              color: MiuixTheme.of(context).colors.primary,
                              disabledColor: MiuixTheme.of(context).colors.primary,
                              contentColor: Colors.white,
                              disabledContentColor: Colors.white,
                            ),
                          ),
                          MiuixIconButton(
                            onPressed: _exitSelectMode,
                            child: MiuixIcon(
                                icon: Icons.close_rounded,
                                tint: MiuixTheme.of(context).colors.primary),
                          ),
                        ],
                      )
                    else
                      MiuixIconButton(
                        onPressed: () => _showActionsMenu(um),
                        child: MiuixIcon(
                            icon: Icons.more_horiz_rounded,
                            tint: MiuixTheme.of(context).colors.primary,
                            size: 26),
                      ),
                  ],
                ),
              ),
              if (!_selectMode && um.hasActive) _buildOverallProgress(um),
              if (um.hasActive && _selectMode) const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip(0, '全部', all.length),
                    const SizedBox(width: 8),
                    _buildFilterChip(1, '进行中', active),
                    const SizedBox(width: 8),
                    _buildFilterChip(2, '已完成', done),
                    const SizedBox(width: 8),
                    _buildFilterChip(3, '失败', failed),
                    const SizedBox(width: 8),
                    _buildFilterChip(4, '已暂停', paused),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: BodySwitcher(child: all.isEmpty
                    ? const EmptyView(
                        icon: Icons.cloud_upload_outlined,
                        text: '暂无上传任务',
                        subText: '去网盘页点「上传」选择文件或文件夹吧')
                    : filtered.isEmpty
                        ? const EmptyView(
                            icon: Icons.inbox_outlined, text: '没有符合条件的任务')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => StaggeredFileItem(
                                index: i, child: _buildTaskCard(filtered[i])),
                          )),
              ),
              if (_selectMode) _buildSelectBar(),
            ],
          ),
        );
      },
    );
  }

  void _showActionsMenu(UploadManager um) {
    MiuixActionSheet.show<String>(
      context,
      title: '上传管理',
      actions: [
        (icon: Icons.cleaning_services_rounded, text: '清除已完成', value: 'clearDone', color: null),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'clearDone':
          um.clearDone();
          _toast('已清除已完成任务');
      }
    });
  }

  Widget _buildOverallProgress(UploadManager um) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixText(
            '上传中 ${um.activeCount} 个  ·  ${(um.overallProgress * 100).clamp(0, 100).toStringAsFixed(1)}%',
            color: colors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: MiuixLinearProgressIndicator(
              progress: um.overallProgress,
              height: 4,
              colors: MiuixProgressIndicatorColors(
                foregroundColor: colors.primary,
                disabledForegroundColor: colors.primary,
                backgroundColor: colors.surfaceContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, int count) {
    final selected = _filter == index;
    final colors = MiuixTheme.of(context).colors;
    return MiuixPressable(
      onPressed: () => setState(() => _filter = index),
      borderRadius: BorderRadius.circular(20),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: MiuixText(
          selected ? '$label $count' : label,
          fontSize: 13,
          color: selected ? Colors.white : colors.onSurfaceSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  bool _isAllSelected(List<UploadTask> list) {
    return list.isNotEmpty && list.every((t) => _selected.contains(t.id));
  }

  // ---------------- 多选 ----------------

  void _enterSelectMode(UploadTask task) {
    setState(() {
      _selectMode = true;
      _selected.add(task.id);
    });
  }

  void _toggleSelect(UploadTask task) {
    setState(() {
      if (!_selected.remove(task.id)) {
        _selected.add(task.id);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  List<UploadTask> _selectedTasks() =>
      _um.tasks.where((t) => _selected.contains(t.id)).toList();

  void _afterBatch(String msg) {
    setState(() {
      _exitSelectMode();
      _busy = false;
    });
    _toast(msg);
  }

  Future<void> _batchPause() async {
    if (_selected.isEmpty) return;
    final list = _selectedTasks().where((t) => t.isActive).toList();
    _um.pauseAll(list);
    _afterBatch('已暂停 ${list.length} 个任务');
  }

  Future<void> _batchResume() async {
    if (_selected.isEmpty) return;
    final list = _selectedTasks().where((t) => t.status == UploadStatus.paused).toList();
    _um.resumeAll(list);
    _afterBatch('已恢复 ${list.length} 个任务');
  }

  Future<void> _batchDelete() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await _confirmU(
        '删除上传任务', '确定删除选中的 $count 个上传任务吗？此操作不会删除本地文件。');
    if (ok != true || !mounted) return;
    _um.removeAll(_selectedTasks());
    _afterBatch('已删除 $count 个任务');
  }

  Widget _buildSelectBar() {
    final count = _selected.length;
    final hasPause = _selectedTasks().any((t) => t.isActive);
    final hasResume = _selectedTasks().any((t) => t.status == UploadStatus.paused);
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
            MiuixIconButton(
              onPressed: _busy || !hasPause ? null : _batchPause,
              child: MiuixIcon(
                  icon: Icons.pause_rounded,
                  tint: hasPause && !_busy
                      ? AppColors.orange
                      : colors.onSurfaceSecondary,
                  size: 24),
            ),
            MiuixIconButton(
              onPressed: _busy || !hasResume ? null : _batchResume,
              child: MiuixIcon(
                  icon: Icons.play_arrow_rounded,
                  tint: hasResume && !_busy
                      ? colors.primary
                      : colors.onSurfaceSecondary,
                  size: 24),
            ),
            MiuixIconButton(
              onPressed: _busy || count == 0 ? null : _batchDelete,
              child: MiuixIcon(
                  icon: Icons.delete_outline_rounded,
                  tint: _busy || count == 0
                      ? colors.onSurfaceSecondary
                      : AppColors.red,
                  size: 24),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 列表项 ----------------

  Widget _buildTaskCard(UploadTask task) {
    final done = task.status == UploadStatus.done;
    final failed = task.status == UploadStatus.failed;
    final canceled = task.status == UploadStatus.canceled;
    final paused = task.status == UploadStatus.paused;
    final active = task.status == UploadStatus.uploading;
    final selected = _selected.contains(task.id);
    final colors = MiuixTheme.of(context).colors;

    return MiuixCard(
      onPressed: () {
        if (_selectMode) {
          _toggleSelect(task);
        }
      },
      onLongPress: _selectMode ? null : () => _enterSelectMode(task),
      child: Container(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FileIcon(isDir: task.isDirOnly, name: task.fileName, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiuixText(
                        task.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: colors.onSurfaceContainer,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      const SizedBox(height: 3),
                      MiuixText(
                        _subtitle(task),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        color: colors.onSurfaceSecondary,
                        fontSize: 11,
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(task),
                if (_selectMode)
                  MiuixIcon(
                    icon: selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    tint: selected ? colors.primary : colors.onSurfaceSecondary,
                    size: 22,
                  )
                else
                  MiuixIconButton(
                    onPressed: () => _showTaskMenu(task),
                    child: MiuixIcon(
                        icon: Icons.more_vert_rounded,
                        tint: colors.onSurfaceSecondary,
                        size: 18),
                  ),
              ],
            ),
            if (task.isActive || paused) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: MiuixLinearProgressIndicator(
                  progress: task.progress,
                  height: 5,
                  colors: MiuixProgressIndicatorColors(
                    foregroundColor: colors.primary,
                    disabledForegroundColor: colors.primary,
                    backgroundColor: colors.surfaceContainer,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  MiuixText(
                    '${formatBytes(task.uploadedBytes)} / ${formatBytes(task.size)}',
                    color: colors.onSurfaceSecondary,
                    fontSize: 11,
                  ),
                  const Spacer(),
                  if (active && task.speed > 0)
                    MiuixText(
                      formatSpeed(task.speed),
                      color: colors.primary,
                      fontSize: 11,
                    ),
                ],
              ),
            ],
            if (failed && task.error != null) ...[
              const SizedBox(height: 8),
              MiuixText(
                task.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                color: AppColors.red,
                fontSize: 11,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTaskMenu(UploadTask task) {
    final paused = task.status == UploadStatus.paused;
    final failed = task.status == UploadStatus.failed;
    final canceled = task.status == UploadStatus.canceled;
    final done = task.status == UploadStatus.done;
    final actions = <({IconData icon, String text, String value, Color? color})>[
      if (task.isActive)
        (icon: Icons.pause_rounded, text: '暂停', value: 'pause', color: null),
      if (paused)
        (icon: Icons.play_arrow_rounded, text: '继续上传', value: 'resume', color: null),
      if (failed || canceled || done)
        (icon: Icons.refresh_rounded, text: '重新上传', value: 'retry', color: null),
      if (task.isActive)
        (icon: Icons.close_rounded, text: '取消上传', value: 'cancel', color: AppColors.orange),
      (icon: Icons.delete_outline_rounded, text: '删除任务', value: 'delete', color: AppColors.red),
    ];
    MiuixActionSheet.show<String>(context, title: task.fileName, actions: actions)
        .then((v) {
      if (v == null) return;
      switch (v) {
        case 'pause':
          _um.pause(task);
          _toast('已暂停');
        case 'resume':
          _um.resume(task);
          _toast('已恢复上传');
        case 'retry':
          _um.retry(task);
          _toast('已重新加入队列');
        case 'cancel':
          _um.cancel(task);
        case 'delete':
          _um.remove(task);
      }
    });
  }

  String _subtitle(UploadTask task) {
    final base = task.isDirOnly ? '空文件夹' : formatBytes(task.size);
    switch (task.status) {
      case UploadStatus.done:
        return '$base  ·  已上传到夸克网盘';
      case UploadStatus.failed:
        return '$base  ·  上传失败，可重新上传';
      case UploadStatus.canceled:
        return '$base  ·  已取消';
      case UploadStatus.paused:
        return '$base  ·  已暂停，可继续上传';
      case UploadStatus.uploading:
        final stage = switch (task.stage) {
          UploadStage.hashing => '校验中',
          UploadStage.uploading => '上传中',
          UploadStage.merging => '合并中',
          UploadStage.queued => '排队中',
        };
        return '$stage  ·  ${formatPercent(task.uploadedBytes, task.size)}';
      case UploadStatus.pending:
        return '排队中  ·  ${formatPercent(task.uploadedBytes, task.size)}';
    }
  }

  Widget _buildStatusBadge(UploadTask task) {
    final (color, text) = switch (task.status) {
      UploadStatus.done => (AppColors.green, '完成'),
      UploadStatus.failed => (AppColors.red, '失败'),
      UploadStatus.canceled => (AppColors.textSecondary, '已取消'),
      UploadStatus.paused => (AppColors.orange, '已暂停'),
      UploadStatus.uploading => switch (task.stage) {
          UploadStage.hashing => (AppColors.accent, '校验中'),
          UploadStage.merging => (AppColors.orange, '合并中'),
          _ => (AppColors.accent, '上传中'),
        },
      UploadStatus.pending => (AppColors.textSecondary, '排队'),
    };
    return MiuixStatusChip(text, color);
  }

  Future<bool?> _confirmU(String title, String content) {
    return confirmMiuix(
      context,
      title: title,
      content: content,
      confirmText: '删除',
      danger: true,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    MiuixToast.show(msg);
  }
}
