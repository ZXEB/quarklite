import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../theme/app_theme.dart';
import 'md3_progress_bar.dart';

/// MD3 网盘账号卡：圆形字标头像 + 名称/账号行 + 「已用 X / Y」细进度条 + ⋮ 菜单。
///
/// 视觉还原参考：浅灰大圆角卡片、头像圆底字标（夸/迅/123）、右侧竖三点菜单。
class Md3AccountCard extends StatelessWidget {
  const Md3AccountCard({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.usageText,
    this.usageValue,
    this.usageColor,
    this.onTap,
    this.onMenu,
  });

  /// 头像字标（1–3 个字符，如 夸 / UC / 123）。
  final String badge;
  final String title;
  final String subtitle;
  final Color? subtitleColor;

  /// 「已用 X / Y」文案；为 null 时不显示用量区。
  final String? usageText;

  /// 进度 0..1；与 [usageText] 同时提供才显示。
  final double? usageValue;

  /// 进度条颜色；为 null 时用 [AppColors.accent]。
  final Color? usageColor;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final showUsage = usageText != null && usageValue != null;
    return MiuixCard(
      cornerRadius: 20,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 6, 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.avatarBg,
                shape: BoxShape.circle,
              ),
              child: MiuixText(
                badge,
                fontSize: badge.length >= 3 ? 12 : 15,
                fontWeight: FontWeight.w700,
                color: AppColors.avatarFg,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(title,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceContainer),
                  const SizedBox(height: 3),
                  MiuixText(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      fontSize: 12,
                      color: subtitleColor ?? colors.onSurfaceSecondary),
                  if (showUsage) ...[
                    const SizedBox(height: 9),
                    Md3ProgressBar(value: usageValue!, fillColor: usageColor),
                    const SizedBox(height: 5),
                    MiuixText(usageText!,
                        fontSize: 11, color: colors.onSurfaceSecondary),
                  ],
                ],
              ),
            ),
            if (onMenu != null)
              IconButton(
                onPressed: onMenu,
                icon: Icon(Icons.more_vert_rounded,
                    size: 22, color: colors.onSurfaceSecondary),
                tooltip: '更多操作',
              ),
          ],
        ),
      ),
    );
  }
}
