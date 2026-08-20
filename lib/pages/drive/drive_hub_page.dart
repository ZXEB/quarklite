import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../login/login_page.dart';
import '../login/netdisk123_login_page.dart';
import '../login/xunlei_login_page.dart';
import 'drive_page.dart';
import 'netdisk123_accounts_page.dart';
import 'xunlei_drive_page.dart';

/// 多网盘入口页：列出所有支持的网盘，点击进入对应文件浏览；
/// 未登录时点击先进入登录页。
class DriveHubPage extends StatelessWidget {
  const DriveHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [AppState.I, XunleiState.I, Netdisk123State.I]),
      builder: (context, _) {
        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 16, 20, 12),
                child: Text('网盘',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '更多网盘陆续接入中…',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
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
      subtitle: logged
          ? (nickname.isNotEmpty ? '$nickname · 已连接' : '已连接')
          : '未登录，点击登录',
      statusColor: logged ? AppColors.green : AppColors.textSecondary,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DrivePage()),
        );
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
      subtitle: logged
          ? (account.isNotEmpty ? '$account · 已连接' : '已连接')
          : '未登录，点击登录',
      statusColor: logged ? AppColors.green : AppColors.textSecondary,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const XunleiLoginPage()),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const XunleiDrivePage()),
        );
      },
      onLongPress: logged
          ? () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('退出迅雷云盘'),
                  content: Text('确定退出账号${account.isEmpty ? '' : '「$account」'}吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('退出'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await XunleiState.I.logout();
              }
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
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const Netdisk123AccountsPage()),
        );
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

  const _DriveCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.statusColor,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.accent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: statusColor, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}
