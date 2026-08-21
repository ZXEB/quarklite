import 'package:flutter/material.dart';

/// 应用颜色表 — 单一 Miuix / HyperOS 浅色。
///
/// 重构后不再支持 dark/miuix 双主题，全部使用 HyperOS 浅色。
/// 旧的 [UIStyle]/[AppStyleState] 保留为兼容存根，避免历史引用报错。
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

  @Deprecated('双主题已移除，AppColors 现为固定常量，无需 apply()')
  static void apply(UIStyle _) {}
}

// ---------------------------------------------------------------------------
// 兼容存根：保留旧符号，避免大量文件一次性改名导致编译阻断。
// 新代码不应再使用这些类型，请直接使用 AppColors 常量或
// MiuixTheme.of(context).colors。
// ---------------------------------------------------------------------------

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

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => light();

  static ThemeData _build(Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.light(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary,
        onPrimary: Colors.white,
      ),
      fontFamily: 'MiSansPro',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg,
        hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent, width: 1.2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.accent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardLight,
        contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(iconColor: AppColors.textSecondary),
      dividerTheme: DividerThemeData(color: AppColors.divider),
    );
  }
}
