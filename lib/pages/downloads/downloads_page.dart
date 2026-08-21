import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/gopeed/gopeed_boot.dart';
import '../../core/gopeed/gopeed_models.dart';
import '../../state/download_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with AutomaticKeepAliveClientMixin {
  int _filter = 0;
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  List<GopeedTask> _applyFilter(List<GopeedTask> all) {
    return switch (_filter) {
      1 => all
          .where((t) =>
              t.status != GopeedStatus.done &&
              t.status != GopeedStatus.error)
          .toList(),
      2 => all.where((t) => t.status == GopeedStatus.done).toList(),
      3 => all.where((t) => t.status == GopeedStatus.error).toList(),
      _ => all,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: DownloadManager.I,
      builder: (context, _) {
        final dm = DownloadManager.I;
        final all = dm.tasks;
        final done = dm.countOf(GopeedStatus.done);
        final failed = dm.countOf(GopeedStatus.error);
        final active = all.length - done - failed;

        final filtered = _applyFilter(all);

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    MiuixText(_selectMode ? '批量操作' : '下载管理',
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
                                color: MiuixTheme.of(context).colors.primary),
                          ),
                          MiuixIconButton(
                            onPressed: _exitSelectMode,
                            child: MiuixIcon(
                                icon: Icons.close_rounded,
                                tint: MiuixTheme.of(context).colors.primary),
                          ),
                        ],
                      )
                    else ...[
                      if (dm.hasEngineError)
                        MiuixIconButton(
                          onPressed: _retryEngine,
                          child: MiuixIcon(
                              icon: Icons.error_outline,
                              tint: AppColors.red,
                              size: 20),
                        ),
                      MiuixIconButton(
                        onPressed: () => _showActionsMenu(dm),
                        child: MiuixIcon(
                            icon: Icons.more_horiz_rounded,
                            tint: MiuixTheme.of(context).colors.primary,
                            size: 26),
                      ),
                    ],
                  ],
                ),
              ),
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
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: BodySwitcher(child: all.isEmpty
                    ? const EmptyView(
                        icon: Icons.inventory_2_outlined,
                        text: '暂无任务',
                        subText: '去网盘或解析页添加下载任务吧')
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
              if (_selectMode) _buildSelectBar(filtered),
            ],
          ),
        );
      },
    );
  }

  void _showActionsMenu(DownloadManager dm) {
    MiuixActionSheet.show<String>(
      context,
      title: '下载管理',
      actions: [
        (icon: Icons.pause_rounded, text: '全部暂停', value: 'pauseAll', color: null),
        (icon: Icons.cleaning_services_rounded, text: '清除已完成', value: 'clearDone', color: null),
      ],
    ).then((v) async {
      if (v == null) return;
      switch (v) {
        case 'pauseAll':
          await dm.pauseAllActive();
          _toast('已全部暂停');
        case 'clearDone':
          await dm.clearDone();
          _toast('已清除已完成任务');
      }
    });
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

  bool _isAllSelected(List<GopeedTask> list) {
    return list.isNotEmpty && list.every((t) => _selected.contains(t.id));
  }

  // ---------------- 多选 ----------------

  void _enterSelectMode(GopeedTask task) {
    setState(() {
      _selectMode = true;
      _selected.add(task.id);
    });
  }

  void _toggleSelect(GopeedTask task) {
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

  List<GopeedTask> _selectedTasks() =>
      DownloadManager.I.tasks.where((t) => _selected.contains(t.id)).toList();

  void _afterBatch(String msg) {
    setState(() {
      _exitSelectMode();
      _busy = false;
    });
    _toast(msg);
  }

  Future<void> _batchPause() async {
    if (_selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final list = _selectedTasks()
          .where((t) => t.status.isActive)
          .toList();
      if (list.isEmpty) return;
      for (final t in list) {
        await DownloadManager.I.pauseTask(t);
      }
      _afterBatch('已暂停 ${list.length} 个任务');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('批量暂停失败: $e');
      }
    }
  }

  Future<void> _batchResume() async {
    if (_selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final list = _selectedTasks()
          .where((t) => t.status == GopeedStatus.pause)
          .toList();
      if (list.isEmpty) return;
      for (final t in list) {
        await DownloadManager.I.resumeTask(t);
      }
      _afterBatch('已恢复 ${list.length} 个任务');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('批量继续失败: $e');
      }
    }
  }

  Future<void> _batchDelete({bool deleteFile = false}) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await _confirmDeleteBatch(count, deleteFile: deleteFile);
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final list = _selectedTasks();
      for (final t in list) {
        await DownloadManager.I.removeTask(t, deleteFile: deleteFile);
      }
      _afterBatch('已删除 $count 个任务${deleteFile ? '及文件' : ''}');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('批量删除失败: $e');
      }
    }
  }

  Widget _buildSelectBar(List<GopeedTask> filtered) {
    final count = _selected.length;
    final hasPause = _selectedTasks().any((t) => t.status.isActive);
    final hasResume =
        _selectedTasks().any((t) => t.status == GopeedStatus.pause);
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
              onPressed: _busy || count == 0 ? null : () => _batchDelete(),
              child: MiuixIcon(
                  icon: Icons.delete_outline_rounded,
                  tint: _busy || count == 0
                      ? colors.onSurfaceSecondary
                      : AppColors.red,
                  size: 24),
            ),
            MiuixIconButton(
              onPressed: _busy || count == 0 ? null : () => _batchDelete(deleteFile: true),
              child: MiuixIcon(
                  icon: Icons.delete_forever_outlined,
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

  Widget _buildTaskCard(GopeedTask task) {
    final done = task.status == GopeedStatus.done;
    final failed = task.status == GopeedStatus.error;
    final paused = task.status == GopeedStatus.pause;
    final selected = _selected.contains(task.id);
    final colors = MiuixTheme.of(context).colors;

    return MiuixCard(
      onPressed: () {
        if (_selectMode) _toggleSelect(task);
      },
      onLongPress: _selectMode ? null : () => _enterSelectMode(task),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FileIcon(isDir: false, name: task.name, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiuixText(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      const SizedBox(height: 3),
                      MiuixText(
                        _subtitle(task),
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
            if (!done && !failed) ...[
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
                    '${formatBytes(task.downloaded)} / ${formatBytes(task.size)}',
                    color: colors.onSurfaceSecondary,
                    fontSize: 11,
                  ),
                  const Spacer(),
                  if (task.status == GopeedStatus.running)
                    MiuixText(
                      formatSpeed(task.speed),
                      color: colors.primary,
                      fontSize: 11,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTaskMenu(GopeedTask task) {
    final done = task.status == GopeedStatus.done;
    final failed = task.status == GopeedStatus.error;
    final paused = task.status == GopeedStatus.pause;
    final actions = <({IconData icon, String text, String value, Color? color})>[
      if (!done && !failed && !paused)
        (icon: Icons.pause_rounded, text: '暂停', value: 'pause', color: null),
      if (paused)
        (icon: Icons.play_arrow_rounded, text: '继续下载', value: 'resume', color: null),
      (icon: Icons.delete_outline_rounded, text: '删除任务', value: 'delete', color: AppColors.red),
      (icon: Icons.delete_forever_outlined, text: '删除任务和文件', value: 'deleteFile', color: AppColors.red),
    ];
    MiuixActionSheet.show<String>(context, title: task.name, actions: actions)
        .then((v) async {
      if (v == null) return;
      switch (v) {
        case 'pause':
          await DownloadManager.I.pauseTask(task);
        case 'resume':
          await DownloadManager.I.resumeTask(task);
        case 'delete':
          await _confirmDelete(task);
        case 'deleteFile':
          await _confirmDelete(task, deleteFile: true);
      }
    });
  }

  String _subtitle(GopeedTask task) {
    switch (task.status) {
      case GopeedStatus.done:
        return '${formatBytes(task.size)}  ·  已完成';
      case GopeedStatus.error:
        return '下载出错，可删除后重试';
      case GopeedStatus.running:
        return '${formatPercent(task.downloaded, task.size)}  ·  ${formatSpeed(task.speed)}';
      case GopeedStatus.pause:
        return '已暂停  ·  ${formatPercent(task.downloaded, task.size)}';
      default:
        return '排队中  ·  ${formatPercent(task.downloaded, task.size)}';
    }
  }

  Widget _buildStatusBadge(GopeedTask task) {
    final (color, text) = switch (task.status) {
      GopeedStatus.done => (AppColors.green, '完成'),
      GopeedStatus.error => (AppColors.red, '失败'),
      GopeedStatus.pause => (AppColors.orange, '暂停'),
      GopeedStatus.running => (AppColors.accent, '下载中'),
      _ => (AppColors.textSecondary, '排队'),
    };
    return MiuixStatusChip(text, color);
  }

  Future<void> _confirmDelete(GopeedTask task,
      {bool deleteFile = false}) async {
    final ok = await confirmMiuix(
      context,
      title: deleteFile ? '删除任务和文件' : '删除任务',
      content: deleteFile
          ? '将删除下载任务和已下载的文件，确定？'
          : '将删除「${task.name}」任务，确定？',
      confirmText: '删除',
      danger: true,
    );
    if (ok == true) {
      await DownloadManager.I.removeTask(task, deleteFile: deleteFile);
    }
  }

  Future<bool?> _confirmDeleteBatch(int count, {bool deleteFile = false}) {
    return confirmMiuix(
      context,
      title: deleteFile ? '删除任务和文件' : '删除任务',
      content: deleteFile
          ? '将删除选中的 $count 个下载任务及其已下载的文件，确定？'
          : '将删除选中的 $count 个下载任务，确定？',
      confirmText: '删除',
      danger: true,
    );
  }

  Future<void> _retryEngine() async {
    try {
      await GopeedEngine.start();
      DownloadManager.I.engineError = null;
      await DownloadManager.I.refresh();
      _toast('下载引擎已启动');
    } catch (e) {
      final detail = GopeedEngine.lastError ?? e.toString();
      if (!mounted) return;
      final isKilled = detail.contains('立即退出') || detail.contains('code=-1');
      await confirmMiuix(
        context,
        title: '下载引擎启动失败',
        content: isKilled
            ? '$detail\n\n引擎进程被系统直接终止，最常见原因是杀毒软件拦截未签名的引擎程序。请：\n'
                '1. 打开 Windows 安全中心 → 病毒和威胁防护 → 保护历史记录\n'
                '2. 找到被阻止的 gopeed.exe，选择「允许」\n'
                '3. 或将 Quarklite 安装目录加入排除项后重新打开软件'
            : detail,
        confirmText: '知道了',
      );
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    MiuixToast.show(msg);
  }
}
