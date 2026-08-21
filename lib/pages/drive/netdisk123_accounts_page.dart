import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
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
        final colors = MiuixTheme.of(context).colors;
        return MiuixScaffold(
          topBar: MiuixTopAppBar(
            title: '选择 123 网盘账号',
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: MiuixIcon(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tint: colors.onSurfaceContainer,
                  size: 20),
            ),
            actions: [
              MiuixIconButton(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()));
                  if (mounted) setState(() {});
                },
                child: MiuixIcon(icon: Icons.person_add_rounded, tint: colors.primary),
              ),
            ],
          ),
          content: (padding) => Padding(
            padding: padding,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: MiuixSurface(
                    color: colors.surface,
                    cornerRadius: 18,
                    border: Border.all(color: colors.dividerLine, width: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          MiuixIcon(icon: Icons.info_outline_rounded,
                              tint: colors.primary, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: MiuixText('请选择账号进入文件 · 不同账号流量独立 · 右上角可添加',
                                color: colors.onSurfaceSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: BodySwitcher(
                    child: s.accounts.isEmpty
                        ? Center(
                            key: const ValueKey('empty'),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              MiuixSurface(
                                color: colors.surface,
                                cornerRadius: 28,
                                child: SizedBox(
                                  width: 88,
                                  height: 88,
                                  child: Center(
                                    child: MiuixIcon(icon: Icons.account_circle_outlined,
                                        size: 42, tint: colors.onSurfaceSecondary),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              MiuixText('暂无账号', color: colors.onSurfaceSecondary, fontSize: 14),
                              const SizedBox(height: 6),
                              MiuixText('添加后可在不同账号间切换下载',
                                  color: colors.outline, fontSize: 12),
                              const SizedBox(height: 18),
                              MiuixButton(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage())),
                                colors: MiuixButtonColors(
                                  color: colors.primary,
                                  disabledColor: colors.primary,
                                  contentColor: Colors.white,
                                  disabledContentColor: Colors.white,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const MiuixIcon(icon: Icons.person_add_rounded,
                                        tint: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    MiuixText('添加账号', color: Colors.white, fontSize: 14),
                                  ],
                                ),
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
                                child: MiuixCard(
                                  onPressed: () async {
                                    if (!isActive) await Netdisk123State.I.setActive(a.id);
                                    if (!context.mounted) return;
                                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123DrivePage()));
                                    if (mounted) setState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: isActive ? AppColors.accent : colors.surfaceContainer,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: MiuixIcon(
                                            isActive ? Icons.check_circle_rounded : Icons.account_circle_rounded,
                                            tint: isActive ? Colors.white : colors.onSurfaceSecondary,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              MiuixText(a.username,
                                                  color: colors.onSurfaceContainer,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14),
                                              const SizedBox(height: 2),
                                              MiuixText(isActive ? '当前账号 · 点击进入文件' : '点击切换并进入文件',
                                                  color: colors.onSurfaceSecondary, fontSize: 12),
                                            ],
                                          ),
                                        ),
                                        MiuixIcon(icon: Icons.chevron_right_rounded,
                                            tint: colors.onSurfaceSecondary, size: 20),
                                        const SizedBox(width: 4),
                                        MiuixIconButton(
                                          onPressed: () async {
                                            final ok = await confirmMiuix(context,
                                                title: '移除账号',
                                                content: '确定移除「${a.username}」？',
                                                confirmText: '移除',
                                                danger: true);
                                            if (ok == true) {
                                              await Netdisk123State.I.removeAccount(a.id);
                                              if (mounted) setState(() {});
                                            }
                                          },
                                          child: MiuixIcon(icon: Icons.delete_outline_rounded,
                                              tint: colors.onSurfaceSecondary, size: 18),
                                        ),
                                      ],
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
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    border: Border(top: BorderSide(color: colors.dividerLine, width: 0.5)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: MiuixButton(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()));
                          if (mounted) setState(() {});
                        },
                        colors: MiuixButtonColors(
                          color: colors.primary,
                          disabledColor: colors.primary,
                          contentColor: Colors.white,
                          disabledContentColor: Colors.white,
                        ),
                        child: MiuixText(
                          s.accounts.isEmpty ? '添加第一个账号' : '添加账号',
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
