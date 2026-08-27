import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'md3/md3_progress_bar.dart';

/// 网盘剩余容量卡片：MD3 细进度条（带末端圆点） + 已用/总量 + 剩余量。
///
/// [totalSize] / [usedSize] 为字节数；已有有效数据时显示进度条，
/// 否则显示「容量信息暂不可用」占位。
class StorageCapacityRow extends StatelessWidget {
  final int totalSize;
  final int usedSize;

  const StorageCapacityRow({
    super.key,
    required this.totalSize,
    required this.usedSize,
  });

  bool get _valid => totalSize > 0 && usedSize >= 0;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final valid = _valid;
    final ratio = valid ? (usedSize / totalSize).clamp(0.0, 1.0).toDouble() : 0.0;
    final color = ratio >= 0.9 ? AppColors.orange : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (valid) ...[
          Md3ProgressBar(value: ratio, fillColor: color),
          const SizedBox(height: 7),
          Row(
            children: [
              MiuixText(
                '已用 ${formatBytes(usedSize)} / ${formatBytes(totalSize)}',
                fontSize: 11,
                color: colors.onSurfaceSecondary,
              ),
              const Spacer(),
              MiuixText(
                '剩余 ${formatBytes(totalSize - usedSize)}',
                fontSize: 11,
                color: color,
              ),
            ],
          ),
        ] else ...[
          MiuixText(
            '容量信息暂不可用',
            fontSize: 11,
            color: colors.onSurfaceSecondary,
          ),
        ],
      ],
    );
  }
}
