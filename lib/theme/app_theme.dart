import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 应用颜色表 — MD3 (Material You) 极简卡片流设计 tokens。
///
/// 主体颜色一律取自 `MiuixTheme.of(context).colors`（由 [md3LightColors] /
/// [md3DarkColors] 全局注入）；这里保留细节常量，供不方便读取主题的绘制/角标使用。
class AppColors {
  static const bg = Color(0xFFF6F5F9); // 页面背景
  static const card = Color(0xFFF1F0F5); // 卡片表面
  static const cardLight = Color(0xFFE7E6F0); // 头像圆底 / 浅容器
  static const accent = Color(0xFF46557E); // 深蓝灰点缀（进度条/选中态）
  static const accentDark = Color(0xFF9AA8D0); // 暗色模式点缀
  static const accentDeep = Color(0xFFDCE1EE); // 点缀浅容器
  static const textPrimary = Color(0xFF1A1A1E);
  static const textSecondary = Color(0xFF85858E);
  static const divider = Color(0xFFE8E7EE);
  static const green = Color(0xFF0FA35C);
  static const orange = Color(0xFFF08C00);
  static const red = Color(0xFFE94634);
  static const bottomBar = Color(0xFFFFFFFF);
  static const avatarBg = Color(0xFFE7E6F0); // 字标头像圆底
  static const avatarFg = Color(0xFF4A5578); // 字标头像文字
  static const progressTrack = Color(0xFFDFDEE6); // 进度条轨道
  static const pillActive = Color(0xFFEEEDF3); // 底栏选中胶囊

  @Deprecated('UI 已全量迁移到 Miuix 主题，AppColors 仅保留细节常量')
  static void apply(UIStyle _) {}
}

/// MD3 浅色方案：在 Miuix 默认浅色基础上覆盖中性灰白表面 + 深蓝灰点缀。
MiuixColors md3LightColors() => lightColorScheme().copy(
      primary: AppColors.accent,
      onPrimary: const Color(0xFFFFFFFF),
      primaryVariant: const Color(0xFF3A4767),
      onPrimaryVariant: const Color(0xFFC9D2E8),
      disabledPrimary: const Color(0xFFC7CDDD),
      disabledPrimaryButton: const Color(0xFFC7CDDD),
      disabledPrimarySlider: const Color(0xFFB7BFD2),
      primaryContainer: const Color(0xFF5A6A96),
      onPrimaryContainer: const Color(0xFFFFFFFF),
      secondaryContainer: AppColors.pillActive,
      onSecondaryContainer: AppColors.accent,
      secondaryContainerVariant: AppColors.pillActive,
      onSecondaryContainerVariant: AppColors.textSecondary,
      tertiaryContainer: AppColors.avatarBg,
      onTertiaryContainer: AppColors.avatarFg,
      tertiaryContainerVariant: AppColors.avatarBg,
      background: AppColors.bg,
      onBackground: AppColors.textPrimary,
      onBackgroundVariant: AppColors.textSecondary,
      surface: AppColors.bg,
      onSurface: AppColors.textPrimary,
      surfaceVariant: const Color(0xFFFFFFFF),
      onSurfaceSecondary: AppColors.textSecondary,
      onSurfaceVariantSummary: AppColors.textSecondary,
      onSurfaceVariantActions: const Color(0xFF8C8C94),
      disabledOnSurface: const Color(0xFFB8B8C0),
      surfaceContainer: AppColors.card,
      onSurfaceContainer: AppColors.textPrimary,
      onSurfaceContainerVariant: AppColors.textSecondary,
      surfaceContainerHigh: const Color(0xFFECEBF1),
      onSurfaceContainerHigh: const Color(0xFF6E6E76),
      surfaceContainerHighest: const Color(0xFFE7E6EE),
      onSurfaceContainerHighest: AppColors.textPrimary,
      outline: AppColors.progressTrack,
      dividerLine: AppColors.divider,
      sliderKeyPoint: AppColors.progressTrack,
      sliderKeyPointForeground: AppColors.accent,
      sliderBackground: AppColors.progressTrack,
    );

/// MD3 深色方案：炭黑表面 + 浅蓝灰点缀。
MiuixColors md3DarkColors() => darkColorScheme().copy(
      primary: AppColors.accentDark,
      onPrimary: const Color(0xFF14161F),
      primaryVariant: const Color(0xFF7E8CB6),
      onPrimaryVariant: const Color(0xFF3E4A6B),
      disabledPrimary: const Color(0xFF3A4056),
      disabledPrimaryButton: const Color(0xFF3A4056),
      disabledPrimarySlider: const Color(0xFF4A5269),
      primaryContainer: const Color(0xFF7E8CB6),
      onPrimaryContainer: const Color(0xFF14161F),
      secondaryContainer: const Color(0xFF2E2F3A),
      onSecondaryContainer: const Color(0xFFB9C2DC),
      secondaryContainerVariant: const Color(0xFF2E2F3A),
      onSecondaryContainerVariant: const Color(0xFF9C9CA6),
      tertiaryContainer: const Color(0xFF2C2E3C),
      onTertiaryContainer: const Color(0xFFB4BDD8),
      tertiaryContainerVariant: const Color(0xFF2C2E3C),
      background: const Color(0xFF141418),
      onBackground: const Color(0xFFECECF1),
      onBackgroundVariant: const Color(0xFF9C9CA6),
      surface: const Color(0xFF141418),
      onSurface: const Color(0xFFECECF1),
      surfaceVariant: const Color(0xFF232329),
      onSurfaceSecondary: const Color(0xFF9C9CA6),
      onSurfaceVariantSummary: const Color(0xFF9C9CA6),
      onSurfaceVariantActions: const Color(0xFFA2A2AC),
      disabledOnSurface: const Color(0xFF5E5E66),
      surfaceContainer: const Color(0xFF232329),
      onSurfaceContainer: const Color(0xFFECECF1),
      onSurfaceContainerVariant: const Color(0xFF9C9CA6),
      surfaceContainerHigh: const Color(0xFF2A2A31),
      onSurfaceContainerHigh: const Color(0xFF9C9CA6),
      surfaceContainerHighest: const Color(0xFF323239),
      onSurfaceContainerHighest: const Color(0xFFECECF1),
      outline: const Color(0xFF3C3C44),
      dividerLine: const Color(0xFF2E2E36),
      sliderKeyPoint: const Color(0xFF3A3A44),
      sliderKeyPointForeground: AppColors.accentDark,
      sliderBackground: const Color(0xFF3A3A44),
    );

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
  /// 构建 Material 主题基座（明/暗共用）。
  /// 颜色/外观由外层 Miuix 主题主导，此处仅配置转场、文字与基础色标，
  /// 使 `MaterialPageRoute` 运行时稳定可用。
  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = dark ? AppColors.accentDark : AppColors.accent;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: dark ? const Color(0xFF141418) : AppColors.bg,
      colorScheme: dark
          ? const ColorScheme.dark(
              primary: AppColors.accentDark,
              secondary: AppColors.accentDark,
              surface: Color(0xFF232329),
              onSurface: Color(0xFFECECF1),
              onPrimary: Color(0xFF14161F),
            )
          : const ColorScheme.light(
              primary: AppColors.accent,
              secondary: AppColors.accent,
              surface: AppColors.card,
              onSurface: AppColors.textPrimary,
              onPrimary: Colors.white,
            ),
      // 跟随系统默认字体（不强制绑定 MiSansPro，避免包内无该字体出现兜底/异常）
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: MiuixPageTransitionsBuilder(),
          TargetPlatform.iOS: MiuixPageTransitionsBuilder(),
          TargetPlatform.windows: MiuixPageTransitionsBuilder(),
          TargetPlatform.macOS: MiuixPageTransitionsBuilder(),
          TargetPlatform.linux: MiuixPageTransitionsBuilder(),
        },
      ),
      textTheme: TextTheme(
        bodySmall: TextStyle(color: dark ? const Color(0xFFECECF1) : AppColors.textPrimary, decoration: TextDecoration.none, decorationColor: Colors.transparent),
        bodyMedium: TextStyle(color: dark ? const Color(0xFFECECF1) : AppColors.textPrimary, decoration: TextDecoration.none, decorationColor: Colors.transparent),
        bodyLarge: TextStyle(color: dark ? const Color(0xFFECECF1) : AppColors.textPrimary, decoration: TextDecoration.none, decorationColor: Colors.transparent),
        labelMedium: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        labelSmall: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        labelLarge: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        titleSmall: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        titleMedium: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        titleLarge: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        headlineSmall: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        headlineMedium: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        displaySmall: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
        displayMedium: const TextStyle(decoration: TextDecoration.none, decorationColor: Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF232329) : Colors.white,
      ),
      dividerTheme: DividerThemeData(color: dark ? const Color(0xFF2E2E36) : AppColors.divider),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: dark ? const Color(0xFF3A4560) : AppColors.accentDeep,
        selectionHandleColor: accent,
      ),
    );
  }

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);
}
