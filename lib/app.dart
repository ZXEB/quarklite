import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'theme/app_theme.dart';

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.link_rounded, '解析'),
      (Icons.folder_rounded, '网盘'),
      (Icons.download_rounded, '下载'),
      (Icons.person_outline_rounded, '我的'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(top: BorderSide(color: AppColors.divider.withOpacity(0.6), width: 0.5)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card.withOpacity(0.65),
              border: Border(top: BorderSide(color: AppColors.divider.withOpacity(0.8), width: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: List.generate(items.length, (i) {
                  final selected = i == index;
                  final color = selected ? AppColors.accent : AppColors.textSecondary;
                  return Expanded(
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              padding: EdgeInsets.symmetric(
                                horizontal: selected ? 14 : 0,
                                vertical: selected ? 3 : 0,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.accentDeep : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, anim) => ScaleTransition(
                                  scale: anim,
                                  child: child,
                                ),
                                child: Icon(
                                  items[i].$1,
                                  key: ValueKey(selected),
                                  size: 22,
                                  color: selected
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].$2,
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}