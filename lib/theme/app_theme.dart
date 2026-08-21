import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// 应用颜色表 — 细节配色（辅助 Miuix 主题的少数强调色）。
///
/// 主体颜色一律取自 `MiuixTheme.of(context).colors`；这里仅保留与原有配色
/// 语义一致的常量，供不方便读取主题的绘制/角标使用。
class AppColors {
  static const bg = Color(0xFFF2F3F7);
  static const card = Color(0xFFFFFFFF);
  static const cardLight = Color(0xFFE8E9EF);
  static const accent = Color(0xFF3482FF);
  static const accentDeep = Color(0xFFD6E6FF);
  static const textPrimary = Color(0xFF1A1A1E);
  static const textSecondary = Color(0xFF8C93B0);
  static const divider = Color(0xFFE6E7EC);
  static const green = Color(0xFF0FA35C);
  static const orange = Color(0xFFF08C00);
  static const red = Color(0xFFE94634);
  static const bottomBar = Color(0xFFF7F7F7);

  @Deprecated('UI 已全量迁移到 Miuix 主题，AppColors 仅保留细节常量')
  static void apply(UIStyle _) {}
}

// 兼容存根：迁移前的双主题符号，避免历史引用报错。新代码不应使用。
enum UIStyle {
  dark,
  miuix;

  bool get isMiuix => this == UIStyle.miuix;
}

class MiuixColorBridge {
  const MiuixColorBridge();
  Color get seedColor => AppColors.accent;
}

class AppStyleState extends ChangeNotifier {
  AppStyleState._();
  static AppStyleState? _instance;
  static AppStyleState get I => _instance ??= AppStyleState._();

  UIStyle get style => UIStyle.miuix;

  Future<void> init() async {}
  Future<void> setStyle(UIStyle _) async {}
}

/// Miuix 风格页转场：新页面自右下向左上淡入 + 轻微缩放，返回时逆向收束，
/// 复刻 HyperOS 的应用切换过渡。
class MiuixPageTransitionsBuilder extends PageTransitionsBuilder {
  const MiuixPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.04, 0.02),
      end: Offset.zero,
    ).animate(curved);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    final scale = Tween<double>(begin: 0.98, end: 1.0).animate(curved);
    // 下层页面轻微后移淡出，形成视差返回感
    final prev = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
      ),
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 下层页面
        if (prev.value < 1.0)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 1.0 - secondaryAnimation.value * 0.4,
                child: Transform.scale(scale: prev.value, child: child),
              ),
            ),
          ),
        Transform.translate(
          offset: slide.value,
          child: Opacity(opacity: fade.value, child: child),
        ),
      ],
    );
  }
}

class AppTheme {
  /// Material 主题：`MaterialApp.theme` 需要的主题基座。
  /// 颜色/外观由外层 `MiuixTheme` 提供，此处仅配置文字、转场与基础色标，
  /// 使 `MaterialPageRoute` 与文本默认样式稳定可用。
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary,
        onPrimary: Colors.white,
      ),
      fontFamily: 'MiSansPro',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: MiuixPageTransitionsBuilder(),
          TargetPlatform.iOS: MiuixPageTransitionsBuilder(),
          TargetPlatform.windows: MiuixPageTransitionsBuilder(),
          TargetPlatform.macOS: MiuixPageTransitionsBuilder(),
          TargetPlatform.linux: MiuixPageTransitionsBuilder(),
        },
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.textPrimary),
        bodyLarge: TextStyle(color: AppColors.textPrimary),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.card,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider),
    );
  }
}
