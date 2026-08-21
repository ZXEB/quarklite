import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI 风格：Material 深色（默认）/ Miuix 灵动浅色
enum UIStyle {
  dark,
  miuix;

  bool get isMiuix => this == UIStyle.miuix;
}

class AppColors {
  /// 当前 UI 风格对应的颜色表。
  ///
  /// 随 [AppStyleState] 切换：dark 用原有深色值，miuix 用 HyperOS 浅色值。
  /// 组件里始终通过 `AppColors.of(context)` / `AppColors.bg` 取色，
  /// 不要直接引用 `Colors.white` 等硬编码色，否则切换风格后不会变化。
  static Color bg = const Color(0xFF0E0E12);
  static Color card = const Color(0xFF191921);
  static Color cardLight = const Color(0xFF22222C);
  static Color accent = const Color(0xFF3D7BFE);
  static Color accentDeep = const Color(0xFF1E3D75);
  static Color textPrimary = const Color(0xFFF2F3F5);
  static Color textSecondary = const Color(0xFF9A9AA6);
  static Color divider = const Color(0xFF2A2A34);
  static Color green = const Color(0xFF34C77B);
  static Color orange = const Color(0xFFFFA63D);
  static Color red = const Color(0xFFF34C4C);

  /// 底部栏背景色（各页硬编码 0xFF12121A 的来源）
  static Color bottomBar = const Color(0xFF12121A);

  /// 按风格取一套配色，覆盖默认深色值。
  static void apply(UIStyle style) {
    switch (style) {
      case UIStyle.dark:
        bg = const Color(0xFF0E0E12);
        card = const Color(0xFF191921);
        cardLight = const Color(0xFF22222C);
        accent = const Color(0xFF3D7BFE);
        accentDeep = const Color(0xFF1E3D75);
        textPrimary = const Color(0xFFF2F3F5);
        textSecondary = const Color(0xFF9A9AA6);
        divider = const Color(0xFF2A2A34);
        green = const Color(0xFF34C77B);
        orange = const Color(0xFFFFA63D);
        red = const Color(0xFFF34C4C);
        bottomBar = const Color(0xFF12121A);
      case UIStyle.miuix:
        // HyperOS 浅色：主色 0xFF3482FF，浅灰底、白卡片、深灰文字。
        bg = const Color(0xFFF2F3F7);
        card = const Color(0xFFFFFFFF);
        cardLight = const Color(0xFFE8E9EF);
        accent = const Color(0xFF3482FF);
        accentDeep = const Color(0xFFD6E6FF);
        textPrimary = const Color(0xFF1A1A1E);
        textSecondary = const Color(0xFF8C93B0);
        divider = const Color(0xFFE6E7EC);
        green = const Color(0xFF0FA35C);
        orange = const Color(0xFFF08C00);
        red = const Color(0xFFE94634);
        bottomBar = const Color(0xFFF7F7F7);
    }
  }
}

/// Miuix 对应 AppColors 的 HyperOS 色板（浅色默认值）。组件通过 MiuixTheme.of(context) 取色。
class MiuixColorBridge {
  const MiuixColorBridge();

  /// 从当前 AppColors 推导 Miuix 可用的种子色。
  Color get seedColor => AppColors.accent;
}

/// 全局 UI 风格状态（ChangeNotifier 单例，设置页可切换）。
///
/// 因为本仓库 336 处直接引用 `AppColors.*` 静态色，把颜色做成可变静态量、
/// 切换时整体换值，是最小侵入的动态化方案（无需改每处调用点）。
class AppStyleState extends ChangeNotifier {
  AppStyleState._() {
    _style = UIStyle.dark;
    AppColors.apply(_style);
  }

  static AppStyleState? _instance;
  static AppStyleState get I => _instance ??= AppStyleState._();

  static const _kStyle = 'ui_style';
  UIStyle _style = UIStyle.dark;
  UIStyle get style => _style;

  /// 界面风格持久化：启动时调用一次
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kStyle);
      if (v == 'miuix') {
        _style = UIStyle.miuix;
        AppColors.apply(_style);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 切换风格并持久化
  Future<void> setStyle(UIStyle s) async {
    if (s == _style) return;
    _style = s;
    AppColors.apply(s);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStyle, s.name);
    } catch (_) {}
    notifyListeners();
  }
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary,
        onPrimary: Colors.white,
      ),
      fontFamily: 'MiSansPro',
      // 全局路由转场：Material 3 淡入前进动画（fade + 轻微水平滑动 + 缩放）
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
        hintStyle:
            TextStyle(color: AppColors.textSecondary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent, width: 1.2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardLight,
        contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
      ),
      dividerTheme: DividerThemeData(color: AppColors.divider),
    );
  }
}
