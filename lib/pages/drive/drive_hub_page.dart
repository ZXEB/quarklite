import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/storage_capacity.dart';
import '../login/login_page.dart';
import '../login/netdisk123_login_page.dart';
import '../login/xunlei_login_page.dart';
import 'drive_page.dart';
import 'netdisk123_accounts_page.dart';
import 'xunlei_drive_page.dart';

class DriveHubPage extends StatelessWidget {
  const DriveHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, XunleiState.I, Netdisk123State.I]),
      builder: (context, _) {
        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 16, 20, 12),
                child: Text('网盘',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _buildQuarkCard(context),
                    const SizedBox(height: 14),
                    _buildXunleiCard(context),
                    const SizedBox(height: 14),
                    _buildNetdisk123Card(context),
                    const SizedBox(height: 20),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '更多网盘陆续接入中…',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
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
    return _DriveCard(
      icon: Icons.folder_special_rounded,
      iconBg: const Color(0xFF1E3D75),
      title: '夸克网盘',
      subtitle: logged ? (nickname.isNotEmpty ? '$nickname · 已连接' : '已连接') : '未登录，点击登录',
      statusColor: logged ? AppColors.green : AppColors.textSecondary,
      trailing: logged && app.user != null && app.user!.totalSize > 0
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StorageCapacityRow(totalSize: app.user!.totalSize, usedSize: app.user!.usedSize),
            )
          : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrivePage()));
      },
    );
  }

  Widget _buildXunleiCard(BuildContext context) {
    final x = XunleiState.I;
    final logged = x.isLoggedIn;
    final account = x.username ?? '';
    return _DriveCard(
      icon: Icons.bolt_rounded,
      iconBg: const Color(0xFF1E3D75),
      title: '迅雷云盘',
      subtitle: logged ? (account.isNotEmpty ? '$account · 已连接' : '已连接') : '未登录，点击登录',
      statusColor: logged ? AppColors.green : AppColors.textSecondary,
      trailing: logged && x.hasQuota
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StorageCapacityRow(totalSize: x.totalSize, usedSize: x.usedSize),
            )
          : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XunleiLoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XunleiDrivePage()));
      },
      onLongPress: logged
          ? () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('退出迅雷云盘'),
                  content: Text('确定退出账号${account.isEmpty ? '' : '「$account」'}吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
                  ],
                ),
              );
              if (ok == true) await XunleiState.I.logout();
            }
          : null,
    );
  }

  Widget _buildNetdisk123Card(BuildContext context) {
    final n = Netdisk123State.I;
    final logged = n.isLoggedIn;
    final count = n.accounts.length;
    final activeName = n.active?.username ?? n.username ?? '';
    final subtitle = !logged
        ? '未登录，点击登录'
        : count > 1
            ? '已登录 $count 个账号 · 点击选择账号进入'
            : (activeName.isNotEmpty ? '$activeName · 点击选择账号进入' : '已登录 · 点击选择账号');
    return _DriveCard(
      icon: Icons.cloud_upload_rounded,
      iconBg: const Color(0xFF1677FF),
      title: '123 网盘',
      subtitle: subtitle,
      statusColor: logged ? AppColors.green : AppColors.textSecondary,
      trailing: logged && n.hasQuota
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StorageCapacityRow(totalSize: n.totalSize, usedSize: n.usedSize),
            )
          : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123AccountsPage()));
      },
    );
  }
}

class _DriveCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const _DriveCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.statusColor,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(title,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700));
    final subtitleWidget = Text(subtitle,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: statusColor, fontSize: 12));
    final iconBox = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: Colors.white, size: 28),
    );
    final chevron = Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 22);
    return MiuixCard(
      onPressed: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            iconBox,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                titleWidget,
                const SizedBox(height: 4),
                subtitleWidget,
                if (trailing != null) ...[const SizedBox(height: 10), trailing!],
              ]),
            ),
            chevron,
          ],
        ),
      ),
    );
  }
}
