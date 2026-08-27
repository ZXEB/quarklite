import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';

/// MD3 风格底部导航：白色圆角浮条，选中项胶囊高亮 + filled 图标。
///
/// 选中/取消带 fastOutSlowIn 过渡（胶囊淡入 + 图标缩放），与原 Miuix 底栏观感一致；
/// 5 个 tab：解析 / 网盘 / 下载 / 上传 / 我的，上传保留活跃任务红点角标。
class Md3NavBar extends StatelessWidget {
  const Md3NavBar({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _animDuration = Duration(milliseconds: 220);
  static const _animCurve = Curves.fastOutSlowIn;

  static const _items = [
    (Icons.link_rounded, Icons.link_rounded, '解析'),
    (Icons.cloud_outlined, Icons.cloud_rounded, '网盘'),
    (Icons.download_outlined, Icons.download_rounded, '下载'),
    (Icons.upload_outlined, Icons.upload_rounded, '上传'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = MiuixTheme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF1C1C22) : AppColors.bottomBar;
    return Container(
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(isDark ? 0x40000000 : 0x14000000),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++) _item(context, i, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i, bool isDark) {
    final (outline, filled, label) = _items[i];
    final selected = i == index;
    final barColor = isDark ? const Color(0xFF1C1C22) : AppColors.bottomBar;
    final color = selected
        ? (isDark ? const Color(0xFFECECF1) : AppColors.textPrimary)
        : (isDark ? const Color(0xFF9C9CA6) : AppColors.textSecondary);
    final pillColor = selected
        ? (isDark ? const Color(0xFF2E2F3A) : AppColors.pillActive)
        : Colors.transparent;

    return Expanded(
      child: MiuixPressable(
        onPressed: () => onTap(i),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: _animDuration,
              curve: _animCurve,
              width: 54,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: _tabIcon(
                i,
                iconData: selected ? filled : outline,
                color: color,
                selected: selected,
                badgeBorder: barColor,
              ),
            ),
            const SizedBox(height: 2),
            MiuixText(label, fontSize: 11, color: color),
          ],
        ),
      ),
    );
  }

  /// tab 图标。上传 tab 监听 UploadManager：有活跃任务时叠红色角标。
  /// 图标必须在 builder 内部引用已完成的 final 变量，禁止 builder 依赖
  /// 其自身赋值的变量（自引用会无限递归构建，渲染成错误灰框）。
  Widget _tabIcon(
    int i, {
    required IconData iconData,
    required Color color,
    required bool selected,
    required Color badgeBorder,
  }) {
    final baseIcon = AnimatedScale(
      duration: _animDuration,
      curve: _animCurve,
      scale: selected ? 1.08 : 1.0,
      child: Icon(iconData, size: 23, color: color),
    );
    if (i != 3) return baseIcon;
    return ListenableBuilder(
      listenable: UploadManager.I,
      builder: (context, _) {
        if (!UploadManager.I.hasActive) return baseIcon;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            baseIcon,
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: badgeBorder, width: 1.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
