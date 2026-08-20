import 'package:flutter/material.dart';

import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';
import '../login/netdisk123_login_page.dart';
import 'netdisk123_drive_page.dart';

class Netdisk123AccountsPage extends StatefulWidget {
  const Netdisk123AccountsPage({super.key});

  @override
  State<Netdisk123AccountsPage> createState() => _Netdisk123AccountsPageState();
}

class _Netdisk123AccountsPageState extends State<Netdisk123AccountsPage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Netdisk123State.I,
      builder: (_, __) {
        final s = Netdisk123State.I;
        return Scaffold(
          appBar: AppBar(
            title: const Text('选择 123 网盘账号'),
            actions: [
              IconButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()),
                  );
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.person_add_rounded, color: AppColors.accent),
                tooltip: '添加账号',
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
                child: const Text('请选择一个账号进入网盘；右上角可添加新账号。不同账号的下载流量独立计算。',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
              ),
              Expanded(
                child: s.accounts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.account_circle_outlined, size: 56, color: AppColors.textSecondary),
                            const SizedBox(height: 12),
                            const Text('暂无账号', style: TextStyle(color: AppColors.textSecondary)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()),
                              ),
                              icon: const Icon(Icons.person_add_rounded),
                              label: const Text('添加账号'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: s.accounts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final a = s.accounts[i];
                          final isActive = s.activeId == a.id;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              if (!isActive) await Netdisk123State.I.setActive(a.id);
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const Netdisk123DrivePage()),
                              );
                              if (mounted) setState(() {});
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isActive ? AppColors.accentDeep : AppColors.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isActive ? AppColors.accent : Colors.transparent, width: 1),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isActive ? Icons.check_circle_rounded : Icons.account_circle_rounded,
                                  color: isActive ? AppColors.accent : AppColors.textSecondary,
                                ),
                                title: Text(a.username,
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                                subtitle: Text(isActive ? '当前账号 · 点击进入文件' : '点击切换并进入文件',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary, size: 20),
                                      tooltip: '移除',
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('移除账号'),
                                            content: Text('确定移除「${a.username}」？'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移除')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await Netdisk123State.I.removeAccount(a.id);
                                          if (mounted) setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()),
                  );
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('添加账号'),
              ),
            ),
          ),
        );
      },
    );
  }
}
