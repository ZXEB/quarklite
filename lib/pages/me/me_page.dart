import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/notify/download_notifier.dart';
import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../widgets/miuix_common.dart';
import '../../widgets/netdisk_logo.dart';
import '../../widgets/storage_capacity.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, XunleiState.I, Netdisk123State.I]),
      builder: (context, _) {
        final app = AppState.I;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: MiuixText('我的',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              _buildAccountCard(context, app),
              const SizedBox(height: 16),
              _buildSettingsCard(context, app),
              const SizedBox(height: 16),
              _buildAboutCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountCard(BuildContext context, AppState app) {
    return MiuixCard(
      child: Column(
        children: [
          _buildAccountRow(
            context: context,
            icon: const NetdiskLogo(provider: NetdiskProvider.quark),
            title: '夸克网盘',
            subtitle: app.isLoggedIn
                ? (app.user?.nickname.isNotEmpty == true
                    ? app.user!.nickname
                    : '已登录')
                : '未登录，请到「网盘」页登录',
            capability: app.isLoggedIn &&
                    app.user != null &&
                    app.user!.totalSize > 0
                ? StorageCapacityRow(
                    totalSize: app.user!.totalSize,
                    usedSize: app.user!.usedSize,
                  )
                : null,
            trailing: app.isLoggedIn
                ? _LogoutButton(
                    onPressed: () => _confirmLogout(context, '夸克网盘',
                        () => app.logout()),
                  )
                : null,
          ),
          const MiuixHorizontalDivider(),
          _buildAccountRow(
            context: context,
            icon: const NetdiskLogo(provider: NetdiskProvider.xunlei),
            title: '迅雷云盘',
            subtitle: XunleiState.I.isLoggedIn
                ? (XunleiState.I.username?.isNotEmpty == true
                    ? XunleiState.I.username!
                    : '已登录')
                : '未登录，请到「网盘」页登录',
            capability: XunleiState.I.isLoggedIn && XunleiState.I.hasQuota
                ? StorageCapacityRow(
                    totalSize: XunleiState.I.totalSize,
                    usedSize: XunleiState.I.usedSize,
                  )
                : null,
            trailing: XunleiState.I.isLoggedIn
                ? _LogoutButton(
                    onPressed: () => _confirmLogout(context, '迅雷云盘',
                        () => XunleiState.I.logout()),
                  )
                : null,
          ),
          const MiuixHorizontalDivider(),
          _buildAccountRow(
            context: context,
            icon: const NetdiskLogo(provider: NetdiskProvider.netdisk123),
            title: '123 网盘',
            subtitle: Netdisk123State.I.isLoggedIn
                ? (Netdisk123State.I.username?.isNotEmpty == true
                    ? Netdisk123State.I.username!
                    : '已登录')
                : '未登录，请到「网盘」页登录',
            capability: Netdisk123State.I.isLoggedIn && Netdisk123State.I.hasQuota
                ? StorageCapacityRow(
                    totalSize: Netdisk123State.I.totalSize,
                    usedSize: Netdisk123State.I.usedSize,
                  )
                : null,
            trailing: Netdisk123State.I.isLoggedIn
                ? _LogoutButton(
                    onPressed: () => _confirmLogout(context, '123 网盘',
                        () => Netdisk123State.I.logout()),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow({
    required BuildContext context,
    required Widget icon,
    required String title,
    required String subtitle,
    Widget? capability,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(title,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                const SizedBox(height: 2),
                MiuixText(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: AppColors.textSecondary,
                    fontSize: 12),
                if (capability != null) ...[
                  const SizedBox(height: 10),
                  capability,
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _confirmLogout(
      BuildContext context, String name, Future<void> Function() action) async {
    final ok = await confirmMiuix(context, title: '退出$name', content: '确定退出登录吗？', confirmText: '退出', danger: true);
    if (ok == true) {
      await action();
    }
  }

  Widget _buildSettingsCard(BuildContext context, AppState app) {
    Widget leading(IconData icon) => MiuixIcon(icon: icon, size: 22, tint: MiuixTheme.of(context).colors.primary);
    Widget arrowPref({required String title, required String summary, required IconData icon, required VoidCallback onClick}) => MiuixArrowPreference(title: title, summary: summary, startAction: leading(icon), insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), onClick: onClick);
    return MiuixCard(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          arrowPref(title: '下载目录', summary: app.downloadDir, icon: Icons.folder_rounded, onClick: () => _editDownloadDir(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(title: '夸克下载线程', summary: '单任务最大 ${app.connections} 线程', icon: Icons.speed_rounded, onClick: () => _editConnections(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(title: '迅雷下载线程', summary: '单任务最大 ${app.xunleiConnections} 线程', icon: Icons.bolt_rounded, onClick: () => _editXunleiConnections(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(title: '123下载线程', summary: '单任务最大 ${app.netdisk123Connections} 线程', icon: Icons.cloud_upload_rounded, onClick: () => _editNetdisk123Connections(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(title: '同时下载任务数', summary: '最多 ${app.maxRunning} 个任务并发，其余排队', icon: Icons.low_priority_rounded, onClick: () => _editMaxRunning(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(title: '连接预算', summary: '所有任务总连接数上限 ${app.connectionBudget}，防系统卡顿', icon: Icons.tune_rounded, onClick: () => _editConnectionBudget(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(title: '存储权限', summary: '访问下载目录所需权限', icon: Icons.storage_rounded, onClick: () => app.openAllFilesAccess()),
          if (!kIsWeb && Platform.isWindows) ...[const MiuixHorizontalDivider(), arrowPref(title: '关闭窗口时', summary: _closeActionLabel(app.closeAction), icon: Icons.close_fullscreen_rounded, onClick: () => _editCloseAction(context, app))],
        ]),
    );
  }

    String _closeActionLabel(String action) {
    switch (action) {
      case 'minimize':
        return '最小化到托盘（后台继续下载）';
      case 'exit':
        return '直接退出';
      case 'ask':
        return '每次询问';
      default:
        return '首次询问后记住（默认）';
    }
  }

  void _editCloseAction(BuildContext context, AppState app) {
    final options = <(String, String)>[
      ('ask_once', '首次询问后记住（默认）'),
      ('minimize', '最小化到托盘（后台继续下载）'),
      ('exit', '直接退出'),
      ('ask', '每次询问'),
    ];
    miuixChoiceDialog<String>(
      context,
      title: '关闭窗口时',
      options: options.map((e) => e.$1).toList(),
      current: app.closeAction,
      labelOf: (v) => options.firstWhere((e) => e.$1 == v).$2,
    ).then((v) {
      if (v != null) app.setCloseAction(v);
    });
  }

  Widget _buildAboutCard(BuildContext context) {
    Widget leading(IconData icon) => MiuixIcon(icon: icon, size: 22, tint: MiuixTheme.of(context).colors.primary);
    return MiuixCard(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          MiuixArrowPreference(title: '日志', summary: '查看/复制运行日志，排查下载问题', startAction: leading(Icons.bug_report_rounded), insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), onClick: () => _showLog(context)),
          const MiuixHorizontalDivider(),
          MiuixArrowPreference(title: '关于', summary: 'Quarklite v1.3.1  ·  基于 Gopeed 下载引擎', startAction: leading(Icons.info_outline_rounded), insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), onClick: () => _showAbout(context)),
        ]),
    );
  }

  Future<void> _showLog(BuildContext context) async {
    final path = await AppLogger.I.logPath();
    final content = await AppLogger.I.readLog();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _LogDialog(
        path: path,
        content: content,
        onOpenDir: () async {
          final dir = path.contains(Platform.pathSeparator)
              ? path.substring(0, path.lastIndexOf(Platform.pathSeparator))
              : '.';
          try {
            await Process.start('explorer.exe', [dir]);
          } catch (_) {}
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: content));
          if (ctx.mounted) {
            Navigator.pop(ctx);
            MiuixToast.show('日志已复制，请直接粘贴发送给开发者');
          }
        },
      ),
    );
  }

  void _editDownloadDir(BuildContext context, AppState app) {
    miuixInputDialog(
      context,
      title: '下载目录',
      hint: '/storage/emulated/0/Download/Quarklite',
      initialText: app.downloadDir,
      confirmText: '保存',
    ).then((dir) async {
      if (dir == null) return;
      final trimmed = dir.trim();
      if (trimmed.isNotEmpty) {
        await app.setDownloadDir(trimmed);
      }
    });
  }

  void _editConnections(BuildContext context, AppState app) {
    final options = [64, 128, 256, 512, 1024];
    _showThreadPicker(
      context,
      title: '夸克下载线程',
      options: options,
      current: app.connections,
      unit: '线程',
      onPick: (n) => app.setConnections(n),
    );
  }

  void _editXunleiConnections(BuildContext context, AppState app) {
    final options = [16, 32, 64, 128, 256];
    _showThreadPicker(
      context,
      title: '迅雷下载线程',
      options: options,
      current: app.xunleiConnections,
      unit: '线程',
      onPick: (n) => app.setXunleiConnections(n),
    );
  }

  void _editNetdisk123Connections(BuildContext context, AppState app) {
    final options = [16, 32, 64, 128, 256];
    _showThreadPicker(
      context,
      title: '123下载线程',
      options: options,
      current: app.netdisk123Connections,
      unit: '线程',
      onPick: (n) => app.setNetdisk123Connections(n),
    );
  }

  /// 线程数选择弹窗：附性能提醒，让用户自行取舍
  void _showThreadPicker(
    BuildContext context, {
    required String title,
    required List<int> options,
    required int current,
    required String unit,
    required Future<void> Function(int) onPick,
  }) {
    miuixChoiceDialog<int>(
      context,
      title: title,
      options: options,
      current: current,
      labelOf: (n) => '$n $unit',
      hint: '线程数越高下载越快，但过高可能让性能较弱的设备卡顿；\n过低则速度偏慢。请按设备性能自行取舍。',
    ).then((n) {
      if (n != null) onPick(n);
    });
  }

  void _editMaxRunning(BuildContext context, AppState app) {
    miuixChoiceDialog<int>(
      context,
      title: '同时下载任务数',
      options: [1, 2, 3, 4, 6, 8],
      current: app.maxRunning,
      labelOf: (n) => '$n 个任务',
    ).then((n) {
      if (n != null) app.setMaxRunning(n);
    });
  }

  void _editConnectionBudget(BuildContext context, AppState app) {
    miuixChoiceDialog<int>(
      context,
      title: '连接预算',
      options: [32, 64, 128, 256, 512],
      current: app.connectionBudget,
      labelOf: (n) => '$n 连接',
    ).then((n) {
      if (n != null) app.setConnectionBudget(n);
    });
  }

  void _showAbout(BuildContext context) {
    final live = DownloadNotifier.liveUpdateStatus;
    var liveText = '实时动态: 未查询';
    if (live != null) {
      final sdk = live['sdk'];
      final supported = live['promotedSupported'] == true;
      final canPost = live['canPost'] == true;
      final promotable = live['promotable'] == true;
      if (!supported) {
        liveText = '实时动态: 需要 Android 16+（当前 $sdk）';
      } else if (!canPost) {
        liveText = '实时动态: 未启用（请在系统设置中开启）';
      } else if (promotable) {
        liveText = '实时动态: 已就绪（Android $sdk）';
      } else {
        liveText = '实时动态: 不满足条件（${live['reason'] ?? '未知'}）';
      }
    }
    confirmMiuix(
      context,
      title: 'Quarklite',
      content: '夸克网盘不限速下载工具\n\n'
          '· 内置 Gopeed 多线程下载引擎\n'
          '· 支持分享链接解析 / 网盘直连 / BT 磁力\n'
          '· $liveText\n'
          '· 本项目基于 GPL-3.0 协议开源\n\n'
          'v1.0.0',
      confirmText: '关闭',
    );
  }
}

/// 账号行右侧的「退出」小按钮
class _LogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return MiuixPressable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(8),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiuixIcon(icon: Icons.logout_rounded, tint: AppColors.red, size: 14),
            const SizedBox(width: 4),
            MiuixText('退出', color: AppColors.red, fontSize: 12),
          ],
        ),
      ),
    );
  }
}

/// 运行日志展示对话框（MiuixOverlayDialog 包裹在 Navigator 弹层中）
class _LogDialog extends StatefulWidget {
  final String path;
  final String content;
  final VoidCallback onOpenDir;
  final VoidCallback onCopy;

  const _LogDialog({
    super.key,
    required this.path,
    required this.content,
    required this.onOpenDir,
    required this.onCopy,
  });

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final MiuixPopupController _controller = MiuixPopupController(visible: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.show());
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final content = widget.content.length > 3000
        ? '…${widget.content.substring(widget.content.length - 3000)}'
        : widget.content;
    return MiuixOverlayDialog(
      show: false,
      title: '运行日志',
      onDismissRequest: _close,
      content: MiuixDismissScope(
        onDismissRequest: _close,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiuixText('日志文件位置：',
                  color: colors.onSurfaceSecondary, fontSize: 12),
              SelectableText(
                widget.path,
                style: TextStyle(fontSize: 12, color: colors.primary),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  content,
                  style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceSecondary,
                      height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!kIsWeb && Platform.isWindows)
                    MiuixTextButton(
                      '打开目录',
                      onPressed: widget.onOpenDir,
                      colors: MiuixButtonColors(color: colors.primary, disabledColor: colors.primary, contentColor: Colors.white, disabledContentColor: Colors.white),
                    ),
                  const SizedBox(width: 8),
                  MiuixTextButton(
                    '关闭',
                    onPressed: _close,
                    colors: MiuixButtonColors(color: colors.onSurfaceSecondary, disabledColor: colors.onSurfaceSecondary, contentColor: Colors.white, disabledContentColor: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  MiuixTextButton(
                    '复制日志',
                    onPressed: widget.onCopy,
                    colors: MiuixButtonColors(color: colors.primary, disabledColor: colors.primary, contentColor: Colors.white, disabledContentColor: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
