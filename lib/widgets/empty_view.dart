import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subText;
  final Widget? action;

  const EmptyView({
    super.key,
    required this.icon,
    required this.text,
    this.subText,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 42, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Text(text,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15)),
          if (subText != null) ...[
            const SizedBox(height: 6),
            Text(subText!,
                style:
                    const TextStyle(color: AppColors.divider, fontSize: 12)),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}
