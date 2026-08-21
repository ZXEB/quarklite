import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'core/gopeed/gopeed_boot.dart';
import 'core/notify/download_notifier.dart';
import 'pages/downloads/downloads_page.dart';
import 'pages/drive/drive_hub_page.dart';
import 'pages/me/me_page.dart';
import 'pages/parse/parse_page.dart';
import 'pages/uploads/uploads_page.dart';
import 'state/app_state.dart';
import 'state/download_manager.dart';
import 'state/netdisk123_state.dart';
import 'state/upload_manager.dart';
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
    } catch (_) {}
    try {
      await AppState.I.init().timeout(const Duration(seconds: 10));
    } catch (e) {
      _bootError = e.toString();
      AppLogger.I.e('app', 'AppState 初始化失败: $e');
    }
    unawaited(XunleiState.I.init());
    unawaited(Netdisk123State.I.init());
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
      theme: AppTheme.light(),
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
      backgroundColor: AppColors.bg,
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: AppColors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('下载引擎启动失败',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 16)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
    UploadsPage(),
    MePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _AnimatedPageView(index: _index, children: _pages),
      bottomNavigationBar: _MiuixBottomBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

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

class _ActiveDot extends StatelessWidget {
  const _ActiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: AppColors.red,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.bottomBar, width: 1.5),
      ),
    );
  }
}

class _MiuixBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _MiuixBottomBar({required this.index, required this.onTap});

  Widget _tabIcon(int i, IconData icon) {
    if (i != 3) return Icon(icon, size: 26);
    return ListenableBuilder(
      listenable: UploadManager.I,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 26),
          if (UploadManager.I.hasActive)
            const Positioned(
              right: -4,
              top: -4,
              child: _ActiveDot(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.link_rounded, '解析'),
      (Icons.folder_rounded, '网盘'),
      (Icons.download_rounded, '下载'),
      (Icons.upload_rounded, '上传'),
      (Icons.person_outline_rounded, '我的'),
    ];
    return MiuixNavigationBar(
      children: [
        for (var i = 0; i < items.length; i++)
          MiuixNavigationBarItem(
            selected: i == index,
            onPressed: () => onTap(i),
            icon: _tabIcon(i, items[i].$1),
            label: items[i].$2,
          ),
      ],
    );
  }
}
