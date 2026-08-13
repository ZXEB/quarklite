import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/notify/download_notifier.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../login/login_page.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final app = AppState.I;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('我的',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              _buildLoginCard(context, app),
              const SizedBox(height: 16),
              _buildSettingsCard(context, app),
              const SizedBox(height: 16),
              _buildAboutCard(context),
              if (app.isLoggedIn) ...[
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    final ok = await _confirm(context, '退出登录', '确定退出当前账号吗？');
                    if (ok == true) {
                      await app.logout();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('退出登录'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoginCard(BuildContext context, AppState app) {
    final user = app.user;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: () async {
          if (app.isLoggedIn) return;
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            user == null
                ? Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.cardLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: AppColors.textSecondary, size: 32),
                  )
                : user.avatar.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          user.avatar,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 56,
                            height: 56,
                            color: AppColors.cardLight,
                            child: const Icon(Icons.person_rounded,
                                color: AppColors.textSecondary, size: 32),
                          ),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.accentDeep,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            user.nickname.isNotEmpty
                                ? user.nickname.characters.first
                                : '夸',
                            style: const TextStyle(
                                color: AppColors.accent, fontSize: 22),
                          ),
                        ),
                      ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user == null
                        ? '未登录'
                        : user.nickname.isNotEmpty
                            ? user.nickname
                            : '夸克用户',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user == null
                        ? '登录夸克账号，解锁全部功能'
                        : '夸克网盘已连接',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (user == null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('登录',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              )
            else
              const Icon(Icons.verified_rounded,
                  color: AppColors.green, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context, AppState app) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.accent),
            title: const Text('下载目录'),
            subtitle: Text(app.downloadDir,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editDownloadDir(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading:
                const Icon(Icons.speed_rounded, color: AppColors.accent),
            title: const Text('夸克下载线程'),
            subtitle: Text('单任务最大 ${app.connections} 线程'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editConnections(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.bolt_rounded, color: AppColors.accent),
            title: const Text('迅雷下载线程'),
            subtitle: Text('单任务最大 ${app.xunleiConnections} 线程'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editXunleiConnections(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.low_priority_rounded,
                color: AppColors.accent),
            title: const Text('同时下载任务数'),
            subtitle: Text('最多 ${app.maxRunning} 个任务并发，其余排队'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editMaxRunning(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.tune_rounded, color: AppColors.accent),
            title: const Text('连接预算'),
            subtitle: Text('所有任务总连接数上限 ${app.connectionBudget}，防系统卡顿'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editConnectionBudget(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.storage_rounded, color: AppColors.accent),
            title: const Text('存储权限'),
            subtitle: const Text('访问下载目录所需权限'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => app.openAllFilesAccess(),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.bug_report_rounded,
                color: AppColors.accent),
            title: const Text('日志'),
            subtitle: const Text('查看/复制运行日志，排查下载问题'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _showLog(context),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded,
                color: AppColors.accent),
            title: const Text('关于'),
            subtitle: const Text('Quarklite v1.3.1  ·  基于 Gopeed 下载引擎'),
            onTap: () => _showAbout(context),
          ),
        ],
      ),
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
              const Text('日志文件位置：',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              SelectableText(path,
                  style: const TextStyle(fontSize: 12, color: AppColors.accent)),
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
                  style: const TextStyle(
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
          style: const TextStyle(color: AppColors.textPrimary),
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
          const Padding(
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
