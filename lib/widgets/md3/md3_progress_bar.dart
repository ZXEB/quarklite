import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// MD3 极简细进度条：3.5px 圆角条 + 轨道右末端一枚圆点。
class Md3ProgressBar extends StatelessWidget {
  const Md3ProgressBar({
    super.key,
    required this.value,
    this.height = 3.5,
    this.dotSize = 6,
    this.fillColor,
    this.trackColor,
    this.dotColor,
  });

  /// 进度 0..1。
  final double value;
  final double height;
  final double dotSize;
  final Color? fillColor;
  final Color? trackColor;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final fill = fillColor ?? AppColors.accent;
    final v = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    return SizedBox(
      height: dotSize + 2,
      child: Row(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: trackColor ?? AppColors.progressTrack,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: dotColor ?? fill,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
