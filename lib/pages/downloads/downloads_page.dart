import 'package:flutter/material.dart';

import '../../core/gopeed/gopeed_models.dart';
import '../../state/download_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with AutomaticKeepAliveClientMixin {
  int _filter = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dm = DownloadManager.I;
    final all = dm.tasks;
    final done = dm.countOf(GopeedStatus.done);
    final failed = dm.countOf(GopeedStatus.error);
    final active = all.length - done - failed;

    final filtered = switch (_filter) {
      1 => all.where((t) => t.status != GopeedStatus.done && t.status != GopeedStatus.error).toList(),
      2 => dm.byStatus(GopeedStatus.done),
      3 => dm.byStatus(GopeedStatus.error),
      _ => all,
    };

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Text('下载管理',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (dm.hasEngineError)
                  const Icon(Icons.error_outline,
                      color: AppColors.red, size: 20),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded,
                      color: AppColors.accent, size: 26),
                  onSelected: (v) async {
                    switch (v) {
                      case 'pauseAll':
                        await dm.pauseAllActive();
                        _toast('已全部暂停');
                      case 'clearDone':
                        await dm.clearDone();
                        _toast('已清除已完成任务');
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pauseAll', child: Text('全部暂停')),
                    PopupMenuItem(value: 'clearDone', child: Text('清除已完成')),
                  ],
                ),
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
            child: all.isEmpty
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
                        itemBuilder: (_, i) => _buildTaskCard(filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, int count) {
    final selected = _filter == index;
    return InkWell(
      onTap: () => setState(() => _filter = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          selected ? '$label $count' : label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(GopeedTask task) {
    final done = task.status == GopeedStatus.done;
    final failed = task.status == GopeedStatus.error;
    final paused = task.status == GopeedStatus.pause;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
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
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(task),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(task),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.textSecondary, size: 18),
                onSelected: (v) async {
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
                },
                itemBuilder: (_) => [
                  if (!done && !failed && !paused)
                    const PopupMenuItem(value: 'pause', child: Text('暂停')),
                  if (paused)
                    const PopupMenuItem(value: 'resume', child: Text('继续下载')),
                  const PopupMenuItem(value: 'delete', child: Text('删除任务')),
                  const PopupMenuItem(value: 'deleteFile', child: Text('删除任务和文件')),
                ],
              ),
            ],
          ),
          if (!done && !failed) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 5,
                backgroundColor: AppColors.bg,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${formatBytes(task.downloaded)} / ${formatBytes(task.size)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                const Spacer(),
                if (task.status == GopeedStatus.running)
                  Text(
                    formatSpeed(task.speed),
                    style: const TextStyle(
                        color: AppColors.accent, fontSize: 11),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11)),
    );
  }

  Future<void> _confirmDelete(GopeedTask task,
      {bool deleteFile = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deleteFile ? '删除任务和文件' : '删除任务'),
        content: Text(deleteFile
            ? '将删除下载任务和已下载的文件，确定？'
            : '将删除「${task.name}」任务，确定？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DownloadManager.I.removeTask(task, deleteFile: deleteFile);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
