import 'package:flutter/material.dart';

class StaggeredFileItem extends StatelessWidget {
  final int index;
  final Widget child;
  const StaggeredFileItem({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = (index * 40).clamp(0, 240);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

class BodySwitcher extends StatelessWidget {
  final Widget child;
  const BodySwitcher({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
