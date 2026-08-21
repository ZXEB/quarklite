import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

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
    final colors = MiuixTheme.of(context).colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiuixSurface(
            color: colors.surface,
            cornerRadius: 28,
            child: SizedBox(
              width: 88,
              height: 88,
              child: Center(
                child: MiuixIcon(
                    icon: icon, size: 42, tint: colors.onSurfaceSecondary),
              ),
            ),
          ),
          const SizedBox(height: 20),
          MiuixText(text,
              fontSize: 15, color: colors.onSurfaceSecondary),
          if (subText != null) ...[
            const SizedBox(height: 6),
            MiuixText(subText!,
                fontSize: 12, color: colors.outline, textAlign: TextAlign.center),
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
