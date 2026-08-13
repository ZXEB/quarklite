import 'dart:async';

import 'package:flutter/material.dart';

import 'core/gopeed/gopeed_boot.dart';
import 'core/notify/download_notifier.dart';
import 'pages/downloads/downloads_page.dart';
import 'pages/drive/drive_page.dart';
import 'pages/me/me_page.dart';
import 'pages/parse/parse_page.dart';
import 'state/app_state.dart';
import 'state/download_manager.dart';
import 'theme/app_theme.dart';

class QuarkLiteApp extends StatefulWidget {
  const QuarkLiteApp({super.key});

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
    try {
      await DownloadNotifier.init().timeout(const Duration(seconds: 10));
    } catch (_) {
      // 通知初始化失败不影响主流程
    }
    try {
      await AppState.I.init().timeout(const Duration(seconds: 10));
    } catch (e) {
      _bootError = e.toString();
    }
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
    } catch (_) {
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
    DrivePage(),
    DownloadsPage(),
    MePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

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
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
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
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentDeep,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(items[i].$1,
                              size: 22, color: AppColors.accent),
                        )
                      else
                        Icon(items[i].$1, size: 22, color: color),
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
    );
  }
}
