import 'package:flutter/material.dart';

import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';
import '../login/netdisk123_login_page.dart';

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
            title: const Text('123 网盘账号'),
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
          body: s.accounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_circle_outlined,
                          size: 56, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      const Text('暂无账号', style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()),
                        ),
                        child: const Text('去登录'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: s.accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final a = s.accounts[i];
                    final isActive = s.activeId == a.id;
                    return Container(
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.accentDeep : AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: Icon(
                          isActive ? Icons.check_circle_rounded : Icons.account_circle_rounded,
                          color: isActive ? AppColors.accent : AppColors.textSecondary,
                        ),
                        title: Text(a.username,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                        subtitle: Text(isActive ? '当前使用' : '点击切换为当前',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.textSecondary),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('移除账号'),
                                content: Text('确定移除「${a.username}」？'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('取消')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('移除')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await Netdisk123State.I.removeAccount(a.id);
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                        onTap: isActive
                            ? null
                            : () async {
                                await Netdisk123State.I.setActive(a.id);
                                if (mounted) setState(() {});
                              },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
