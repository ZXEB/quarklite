import 'package:flutter/material.dart';

import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key});

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage>
    with AutomaticKeepAliveClientMixin {
  int _filter = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: UploadManager.I,
      builder: (context, _) {
        final um = UploadManager.I;
        final all = um.tasks;
        final active = um.activeCount;
        final done = um.doneCount;
        final failed = um.failedCount;

        final filtered = switch (_filter) {
          1 => all
              .where((t) =>
                  t.status == UploadStatus.pending ||
                  t.status == UploadStatus.uploading)
              .toList(),
          2 => all.where((t) => t.status == UploadStatus.done).toList(),
          3 => all.where((t) => t.status == UploadStatus.failed).toList(),
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
                    const Text('上传管理',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded,
                          color: AppColors.accent, size: 26),
                      onSelected: (v) async {
                        switch (v) {
                          case 'clearDone':
                            um.clearDone();
                            _toast('已清除已完成任务');
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'clearDone', child: Text('清除已完成')),
                      ],
                    ),
                  ],
                ),
              ),
              if (um.hasActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '上传中 $active 个  ·  ${(um.overallProgress * 100).clamp(0, 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: um.overallProgress,
                          minHeight: 4,
                          backgroundColor: AppColors.bg,
                        ),
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
                            itemBuilder: (_, i) =>
                                _buildTaskCard(filtered[i]),
                          ),
              ),
            ],
          ),
        );
      },
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

  Widget _buildTaskCard(UploadTask task) {
    final done = task.status == UploadStatus.done;
    final failed = task.status == UploadStatus.failed;
    final canceled = task.status == UploadStatus.canceled;
    final active = task.status == UploadStatus.uploading;

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
              FileIcon(isDir: task.isDirOnly, name: task.fileName, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                    case 'retry':
                      UploadManager.I.retry(task);
                      _toast('已重新加入队列');
                    case 'cancel':
                      UploadManager.I.cancel(task);
                    case 'delete':
                      UploadManager.I.remove(task);
                  }
                },
                itemBuilder: (_) => [
                  if (failed || canceled || done)
                    const PopupMenuItem(value: 'retry', child: Text('重新上传')),
                  if (task.isActive)
                    const PopupMenuItem(value: 'cancel', child: Text('取消上传')),
                  const PopupMenuItem(value: 'delete', child: Text('删除任务')),
                ],
              ),
            ],
          ),
          if (task.isActive) ...[
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
                  '${formatBytes(task.uploadedBytes)} / ${formatBytes(task.size)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                const Spacer(),
                if (active && task.speed > 0)
                  Text(
                    formatSpeed(task.speed),
                    style: const TextStyle(
                        color: AppColors.accent, fontSize: 11),
                  ),
              ],
            ),
          ],
          if (failed && task.error != null) ...[
            const SizedBox(height: 8),
            Text(
              task.error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.red, fontSize: 11),
            ),
          ],
        ],
      ),
    );
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
      UploadStatus.uploading => switch (task.stage) {
          UploadStage.hashing => (AppColors.accent, '校验中'),
          UploadStage.merging => (AppColors.orange, '合并中'),
          _ => (AppColors.accent, '上传中'),
        },
      UploadStatus.pending => (AppColors.textSecondary, '排队'),
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
