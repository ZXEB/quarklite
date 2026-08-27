import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/md3/md3_account_card.dart';
import '../../widgets/miuix_common.dart';
import '../login/login_page.dart';
import '../login/netdisk123_login_page.dart';
import '../login/xunlei_login_page.dart';
import 'drive_page.dart';
import 'netdisk123_accounts_page.dart';
import 'netdisk123_drive_page.dart';
import 'xunlei_drive_page.dart';

class DriveHubPage extends StatelessWidget {
  const DriveHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, XunleiState.I, Netdisk123State.I]),
      builder: (context, _) {
        final colors = MiuixTheme.of(context).colors;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              MiuixText('网盘',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface),
              const SizedBox(height: 8),
              MiuixText(
                '登录后即可自动携带凭证解析与下载',
                fontSize: 12,
                color: colors.onSurfaceSecondary,
              ),
              const SizedBox(height: 20),
              _buildQuarkCard(context),
              const SizedBox(height: 12),
              _buildXunleiCard(context),
              const SizedBox(height: 12),
              _buildNetdisk123Card(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuarkCard(BuildContext context) {
    final app = AppState.I;
    final logged = app.isLoggedIn;
    final nickname = app.user?.nickname ?? '';
    final hasQuota = logged && app.user != null && app.user!.totalSize > 0;
    final ratio = hasQuota
        ? (app.user!.usedSize / app.user!.totalSize).clamp(0.0, 1.0).toDouble()
        : null;
    return Md3AccountCard(
      badge: '夸',
      title: '夸克网盘',
      subtitle: logged ? (nickname.isNotEmpty ? nickname : '已登录') : '未登录，点击登录',
      usageText: hasQuota
          ? '已用 ${formatBytes(app.user!.usedSize)} / ${formatBytes(app.user!.totalSize)}'
          : null,
      usageValue: ratio,
      usageColor: (ratio != null && ratio >= 0.9) ? AppColors.orange : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrivePage()));
      },
      onMenu: logged ? () => _showQuarkMenu(context) : null,
    );
  }

  Widget _buildXunleiCard(BuildContext context) {
    final x = XunleiState.I;
    final logged = x.isLoggedIn;
    final account = x.username ?? '';
    final hasQuota = logged && x.hasQuota && x.totalSize > 0;
    final ratio =
        hasQuota ? (x.usedSize / x.totalSize).clamp(0.0, 1.0).toDouble() : null;
    return Md3AccountCard(
      badge: '迅',
      title: '迅雷网盘',
      subtitle: logged ? (account.isNotEmpty ? account : '已登录') : '未登录，点击登录',
      usageText: hasQuota
          ? '已用 ${formatBytes(x.usedSize)} / ${formatBytes(x.totalSize)}'
          : null,
      usageValue: ratio,
      usageColor: _usageColor(ratio),
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XunleiLoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XunleiDrivePage()));
      },
      onMenu: logged ? () => _showXunleiMenu(context) : null,
    );
  }

  Widget _buildNetdisk123Card(BuildContext context) {
    final n = Netdisk123State.I;
    final logged = n.isLoggedIn;
    final activeName = n.active?.username ?? n.username ?? '';
    final count = n.accounts.length;
    final subtitle = logged
        ? (count > 1 ? '$activeName 等 $count 个账号' : activeName)
        : '未登录，点击登录';
    final hasQuota = logged && n.hasQuota && n.totalSize > 0;
    final ratio =
        hasQuota ? (n.usedSize / n.totalSize).clamp(0.0, 1.0).toDouble() : null;
    return Md3AccountCard(
      badge: '123',
      title: '123云盘',
      subtitle: subtitle,
      usageText: hasQuota
          ? '已用 ${formatBytes(n.usedSize)} / ${formatBytes(n.totalSize)}'
          : null,
      usageValue: ratio,
      usageColor: _usageColor(ratio),
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => count > 1
                ? const Netdisk123AccountsPage()
                : const Netdisk123DrivePage()));
      },
      onMenu: logged ? () => _showNetdisk123Menu(context, count) : null,
    );
  }

  Color? _usageColor(double? ratio) {
    if (ratio == null) return null;
    return ratio >= 0.9 ? AppColors.orange : null;
  }

  Future<void> _showQuarkMenu(BuildContext context) async {
    final app = AppState.I;
    final nickname = app.user?.nickname ?? '';
    final action = await MiuixActionSheet.show<String>(
      context,
      title: '夸克网盘',
      actions: [
        (
          icon: Icons.folder_open_rounded,
          text: '进入文件',
          value: 'open',
          color: null,
        ),
        (
          icon: Icons.logout_rounded,
          text: '退出登录',
          value: 'logout',
          color: AppColors.red,
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == 'open') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrivePage()));
    } else if (action == 'logout') {
      final ok = await confirmMiuix(
        context,
        title: '退出夸克网盘',
        content: '确定退出账号${nickname.isEmpty ? '' : '「$nickname」'}吗？',
        confirmText: '退出',
        danger: true,
      );
      if (ok == true) await app.logout();
    }
  }

  Future<void> _showXunleiMenu(BuildContext context) async {
    final x = XunleiState.I;
    final account = x.username ?? '';
    final action = await MiuixActionSheet.show<String>(
      context,
      title: '迅雷网盘',
      actions: [
        (
          icon: Icons.folder_open_rounded,
          text: '进入文件',
          value: 'open',
          color: null,
        ),
        (
          icon: Icons.logout_rounded,
          text: '退出登录',
          value: 'logout',
          color: AppColors.red,
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == 'open') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const XunleiDrivePage()));
    } else if (action == 'logout') {
      final ok = await confirmMiuix(
        context,
        title: '退出迅雷网盘',
        content: '确定退出账号${account.isEmpty ? '' : '「$account」'}吗？',
        confirmText: '退出',
        danger: true,
      );
      if (ok == true) await x.logout();
    }
  }

  Future<void> _showNetdisk123Menu(BuildContext context, int count) async {
    final n = Netdisk123State.I;
    final activeName = n.active?.username ?? n.username ?? '';
    final action = await MiuixActionSheet.show<String>(
      context,
      title: '123云盘',
      actions: [
        (
          icon: Icons.folder_open_rounded,
          text: '进入文件',
          value: 'open',
          color: null,
        ),
        (
          icon: Icons.people_alt_rounded,
          text: count > 1 ? '管理账号（$count 个）' : '管理账号',
          value: 'accounts',
          color: null,
        ),
        (
          icon: Icons.logout_rounded,
          text: '退出登录',
          value: 'logout',
          color: AppColors.red,
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'open':
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const Netdisk123DrivePage()));
      case 'accounts':
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const Netdisk123AccountsPage()));
      case 'logout':
        final ok = await confirmMiuix(
          context,
          title: '退出123云盘',
          content: '确定退出账号${activeName.isEmpty ? '' : '「$activeName」'}吗？',
          confirmText: '退出',
          danger: true,
        );
        if (ok == true) await n.logout();
    }
  }
}
