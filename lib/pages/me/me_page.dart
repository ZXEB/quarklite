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
                child: Text('我的', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
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
            icon: Icons.folder_special_rounded,
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
            icon: Icons.bolt_rounded,
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
            icon: Icons.cloud_upload_rounded,
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
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? capability,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentDeep,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
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
    final ok = await _confirm(context, '退出$name', '确定退出登录吗？');
    if (ok == true) {
      await action();
    }
  }

  Widget _buildSettingsCard(BuildContext context, AppState app) {
    Widget leading(IconData icon) => Icon(icon, size: 22, color: MiuixTheme.of(context).colors.primary);
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
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('关闭窗口时'),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setCloseAction(value);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    value == app.closeAction
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: value == app.closeAction
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    Widget leading(IconData icon) => Icon(icon, size: 22, color: MiuixTheme.of(context).colors.primary);
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('运行日志'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('日志文件位置：',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              SelectableText(path,
                  style: TextStyle(fontSize: 12, color: AppColors.accent)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cardLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  content.length > 3000
                      ? '…${content.substring(content.length - 3000)}'
                      : content,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!kIsWeb && Platform.isWindows)
            TextButton.icon(
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('打开目录'),
              onPressed: () async {
                final dir = path.contains(Platform.pathSeparator)
                    ? path.substring(0, path.lastIndexOf(Platform.pathSeparator))
                    : '.';
                try {
                  await Process.start('explorer.exe', [dir]);
                } catch (_) {}
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制日志'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('日志已复制，请直接粘贴发送给开发者')));
              }
            },
          ),
        ],
      ),
    );
  }

  void _editDownloadDir(BuildContext context, AppState app) {
    final controller = TextEditingController(text: app.downloadDir);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载目录'),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '/storage/emulated/0/Download/Quarklite'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final dir = controller.text.trim();
              if (dir.isNotEmpty) {
                await app.setDownloadDir(dir);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
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
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '线程数越高下载越快，但过高可能让性能较弱的设备卡顿；\n过低则速度偏慢。请按设备性能自行取舍。',
              style: TextStyle(
                  color: AppColors.orange, fontSize: 12, height: 1.6),
            ),
          ),
          const SizedBox(height: 8),
          for (final n in options)
            SimpleDialogOption(
              onPressed: () async {
                await onPick(n);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    n == current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: n == current
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('$n $unit', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editMaxRunning(BuildContext context, AppState app) {
    final options = [1, 2, 3, 4, 6, 8];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('同时下载任务数'),
        children: [
          for (final n in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setMaxRunning(n);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    n == app.maxRunning
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: n == app.maxRunning
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('$n 个任务', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editConnectionBudget(BuildContext context, AppState app) {
    final options = [32, 64, 128, 256, 512];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('连接预算'),
        children: [
          for (final n in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setConnectionBudget(n);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    n == app.connectionBudget
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: n == app.connectionBudget
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('$n 连接', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
        ],
      ),
    );
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quarklite'),
        content: Text(
          '夸克网盘不限速下载工具\n\n'
          '· 内置 Gopeed 多线程下载引擎\n'
          '· 支持分享链接解析 / 网盘直连 / BT 磁力\n'
          '· $liveText\n'
          '· 本项目基于 GPL-3.0 协议开源\n\n'
          'v1.0.0',
          style: const TextStyle(fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(BuildContext context, String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 账号行右侧的「退出」小按钮
class _LogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout_rounded, size: 14, color: AppColors.red),
            SizedBox(width: 4),
            Text('退出', style: TextStyle(color: AppColors.red, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
