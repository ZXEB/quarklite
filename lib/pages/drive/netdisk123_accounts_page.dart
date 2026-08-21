import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/file_list_anim.dart';
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
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()));
                  if (mounted) setState(() {});
                },
                icon: Icon(Icons.person_add_rounded, color: AppColors.accent),
                tooltip: '添加账号',
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.divider, width: 0.5)),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text('请选择账号进入文件 · 不同账号流量独立 · 右上角可添加', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4))),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: BodySwitcher(
                  child: s.accounts.isEmpty
                      ? Center(
                          key: const ValueKey('empty'),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 88, height: 88, decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(28)), child: Icon(Icons.account_circle_outlined, size: 42, color: AppColors.textSecondary)),
                            const SizedBox(height: 16),
                            Text('暂无账号', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                            const SizedBox(height: 6),
                            Text('添加后可在不同账号间切换下载', style: TextStyle(color: AppColors.divider, fontSize: 12)),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage())),
                              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
                              icon: const Icon(Icons.person_add_rounded, size: 18),
                              label: const Text('添加账号'),
                            ),
                          ]),
                        )
                      : ListView.separated(
                          key: ValueKey('list-${s.accounts.length}-${s.activeId}'),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: s.accounts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final a = s.accounts[i];
                            final isActive = s.activeId == a.id;
                            return StaggeredFileItem(
                              index: i,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () async {
                                  if (!isActive) await Netdisk123State.I.setActive(a.id);
                                  if (!context.mounted) return;
                                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123DrivePage()));
                                  if (mounted) setState(() {});
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(color: isActive ? AppColors.accentDeep : AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: isActive ? AppColors.accent : Colors.transparent, width: 1)),
                                  child: ListTile(
                                    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: isActive ? AppColors.accent : AppColors.cardLight, borderRadius: BorderRadius.circular(12)), child: Icon(isActive ? Icons.check_circle_rounded : Icons.account_circle_rounded, color: isActive ? Colors.white : AppColors.textSecondary, size: 22)),
                                    title: Text(a.username, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                                    subtitle: Text(isActive ? '当前账号 · 点击进入文件' : '点击切换并进入文件', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () async {
                                          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('移除账号'), content: Text('确定移除「${a.username}」？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移除'))]));
                                          if (ok == true) { await Netdisk123State.I.removeAccount(a.id); if (mounted) setState(() {}); }
                                        },
                                        child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary, size: 18)),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(color: AppColors.bottomBar, border: Border(top: BorderSide(color: AppColors.divider, width: 0.5))),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage())); if (mounted) setState(() {}); },
                      style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: Text(s.accounts.isEmpty ? '添加第一个账号' : '添加账号'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
