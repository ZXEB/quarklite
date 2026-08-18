import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

import 'core/gopeed/gopeed_boot.dart';
import 'core/notify/download_notifier.dart';
import 'pages/downloads/downloads_page.dart';
import 'pages/drive/drive_hub_page.dart';
import 'pages/me/me_page.dart';
import 'pages/parse/parse_page.dart';
import 'state/app_state.dart';
import 'state/download_manager.dart';
import 'state/xunlei_state.dart';
import 'theme/app_theme.dart';
import 'utils/app_logger.dart';

class QuarkLiteApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const QuarkLiteApp({super.key, this.navigatorKey});

  @override
  State<QuarkLiteApp> createState() => _QuarkLiteAppState();
}

class _QuarkLiteAppState extends State<QuarkLiteApp> {
  bool _ready = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await AppLogger.I.init();
    AppLogger.I.i('app', '应用启动 bootstrap 开始');
    try {
      await DownloadNotifier.init().timeout(const Duration(seconds: 10));
    } catch (_) {
      // 通知初始化失败不影响主流程
    }
    try {
      await AppState.I.init().timeout(const Duration(seconds: 10));
    } catch (e) {
      _bootError = e.toString();
      AppLogger.I.e('app', 'AppState 初始化失败: $e');
    }
    unawaited(XunleiState.I.init());
    // 引擎后台异步启动，不阻塞界面（失败时下载页可重试/查看原因）
    unawaited(_bootEngine());
    DownloadManager.I.startPolling();
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  Future<void> _bootEngine() async {
    try {
      await GopeedEngine.start();
      final client = GopeedEngine.client;
      final cfg = await client.getConfig();
      final dir = await AppState.I.effectiveDownloadDir();
      final firstBoot = cfg['downloadDir']?.toString().isEmpty ?? true;
      await client.updateConfig(
        downloadDir: firstBoot ? dir : null,
        maxRunning: AppState.I.maxRunning,
        connections: AppState.I.connectionBudget,
      );
    } catch (e) {
      AppLogger.I.e('app', '后台启动引擎失败: $e');
      // 引擎启动失败不阻塞应用：下载页可手动重试，添加任务时也会自动拉起
    }
  }

  @override
  void dispose() {
    DownloadManager.I.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quarklite',
      debugShowCheckedModeBanner: false,
      navigatorKey: widget.navigatorKey,
      theme: AppTheme.dark(),
      home: _ready ? const RootPage() : _BootView(error: _bootError),
    );
  }
}

class _BootView extends StatelessWidget {
  final String? error;

  const _BootView({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('下载引擎启动失败', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  static const _pages = [
    ParsePage(),
    DriveHubPage(),
    DownloadsPage(),
    MePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _AnimatedPageView(index: _index, children: _pages),
      // 内容延伸到底栏下方，滚动时从液态玻璃底栏下透出（磨砂折射感）
      extendBody: true,
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 保留页面状态的 Tab 切换动画（淡入淡出 + 轻微位移动效）
class _AnimatedPageView extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const _AnimatedPageView({required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          AnimatedOpacity(
            opacity: i == index ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: i == index ? Offset.zero : const Offset(0, 0.04),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: i != index,
                child: TickerMode(
                  enabled: i == index,
                  child: children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 液态玻璃底栏：磨砂模糊 + 半透明填充 + 渐变边缘光 + 镜面高光 +
/// 弹性入场 / 选中项液体气泡滑动 / 缓慢流动的镜面光带。
class _BottomBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _BottomBar({required this.index, required this.onTap});

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> with TickerProviderStateMixin {
  /// 弹性入场（弹簧过冲）
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..forward();

  /// 镜面高光带循环流动
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  late final Animation<double> _spring = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
  );

  static const _items = [
    (Icons.link_rounded, '解析'),
    (Icons.folder_rounded, '网盘'),
    (Icons.download_rounded, '下载'),
    (Icons.person_outline_rounded, '我的'),
  ];

  @override
  void dispose() {
    _entrance.dispose();
    _sheen.dispose();
    super.dispose();
  }

  /// 选中项气泡的水平对齐（4 项均匀分布）
  Alignment _bubbleAlignment(int index) => Alignment((index - 1.5) / 2, 0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _sheen]),
      builder: (context, _) {
        final scale = 0.92 + 0.08 * _spring.value;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: _fade.value,
                child: _buildGlassBar(_sheen.value),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassBar(double sheenT) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // 柔和悬浮投影 + 轻微主题色辉光
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.10),
            blurRadius: 34,
            offset: Offset.zero,
          ),
        ],
      ),
      // 1px 渐变描边壳：上亮下暗，模拟玻璃切口边缘光
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x6BFFFFFF), // 顶部边缘最亮
              Color(0x1FFFFFFF),
              Color(0x0DFFFFFF),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 26,
              sigmaY: 26,
              tileMode: TileMode.mirror,
            ),
            child: Container(
              // 半透明玻璃填充 + 上部镜面高光
              foregroundDecoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(27)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment(0, 0.55),
                  colors: [
                    Color(0x1AFFFFFF),
                    Colors.transparent,
                  ],
                ),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF171722).withValues(alpha: 0.58),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final bandWidth = c.maxWidth + 260.0;
                  final dx = (sheenT * 2 - 1) * (bandWidth / 2);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 选中项「液体气泡」：弹性滑动到当前项
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        alignment: _bubbleAlignment(widget.index),
                        child: Container(
                          width: 64,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.accent.withValues(alpha: 0.36),
                                AppColors.accent.withValues(alpha: 0.14),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                      ),
                      // 缓慢流动的镜面光带
                      Positioned(
                        left: -130,
                        top: 0,
                        bottom: 0,
                        width: bandWidth,
                        child: Transform.translate(
                          offset: Offset(dx, 0),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0x12FFFFFF),
                                  Colors.transparent,
                                ],
                                stops: [0.32, 0.5, 0.68],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 菜单项
                      Row(
                        children: List.generate(_items.length, (i) {
                          final selected = i == widget.index;
                          final color = selected
                              ? AppColors.accent
                              : AppColors.textSecondary;
                          return Expanded(
                            child: InkWell(
                              onTap: () => widget.onTap(i),
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 240),
                                      curve: Curves.easeOutCubic,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: selected ? 14 : 0,
                                        vertical: selected ? 3 : 0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.accentDeep
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                            milliseconds: 200),
                                        transitionBuilder: (child, anim) =>
                                            ScaleTransition(
                                          scale: anim,
                                          child: child,
                                        ),
                                        child: Icon(
                                          _items[i].$1,
                                          key: ValueKey(selected),
                                          size: 22,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _items[i].$2,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
