import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 网盘剩余容量卡片：进度条 + 已用/总量 + 百分比。
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
    final valid = _valid;
    final ratio = valid ? (usedSize / totalSize).clamp(0.0, 1.0) : 0.0;
    final color = ratio >= 0.9 ? AppColors.orange : AppColors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (valid) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.cardLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                formatCapacity(usedSize, totalSize),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '剩余 ${formatBytes(totalSize - usedSize)}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ] else ...[
          const Text(
            '容量信息暂不可用',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
  }
}