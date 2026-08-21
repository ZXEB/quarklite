import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';

import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_common.dart';
import 'xunlei_review_page.dart';

/// 迅雷云盘账号密码登录页（含风控短信验证流程）
class XunleiLoginPage extends StatefulWidget {
  const XunleiLoginPage({super.key});

  @override
  State<XunleiLoginPage> createState() => _XunleiLoginPageState();
}

class _XunleiLoginPageState extends State<XunleiLoginPage> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = _account.text.trim();
    final password = _password.text;
    if (account.isEmpty || password.isEmpty) {
      _toast('请输入账号和密码');
      return;
    }
    setState(() => _submitting = true);
    final err = await XunleiState.I.login(account, password);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    // 风控：应用内完成短信/滑块验证
    if (XunleiState.I.client.reviewPending) {
      await _startInAppReview(account, password);
      return;
    }
    _toast('登录失败: $err');
  }

  /// 应用内验证：WebView 打开验证页，验证成功后自动带 creditkey 重试登录
  Future<void> _startInAppReview(String account, String password) async {
    final client = XunleiState.I.client;
    if (!mounted) return;
    final key = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => XunleiReviewPage(
          reviewUrl: client.reviewUrl,
          creditKey: client.creditKey,
          deviceId: client.deviceId,
        ),
      ),
    );
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      // 取消/失败：兜底手动输入 creditkey
      _showReviewDialog(account, password);
      return;
    }
    setState(() => _submitting = true);
    final err = await XunleiState.I.loginWithCreditKey(account, password, key);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      Navigator.of(context).pop(true);
    } else if (XunleiState.I.client.reviewPending) {
      _toast('仍需验证，请重新完成验证');
    } else {
      _toast('登录失败: $err');
    }
  }

  /// 风控验证对话框：打开验证页 → 完成短信验证 → 粘贴 creditkey → 重新登录
  Future<void> _showReviewDialog(String account, String password) async {
    final reviewUrl = XunleiState.I.client.reviewUrl;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ReviewKeyDialog(
        reviewUrl: reviewUrl,
        controller: controller,
        onCopy: () {
          Clipboard.setData(ClipboardData(text: reviewUrl));
          _toast('验证链接已复制');
        },
        onOpenBrowser: () async {
          try {
            await Process.start('cmd', ['/c', 'start', '', reviewUrl]);
          } catch (_) {}
        },
        onSubmit: () async {
          final key = controller.text.trim();
          if (key.isEmpty) {
            _toast('请先粘贴验证密钥');
            return;
          }
          Navigator.pop(ctx);
          setState(() => _submitting = true);
          final err = await XunleiState.I
              .loginWithCreditKey(account, password, key);
          if (!mounted) return;
          setState(() => _submitting = false);
          if (err == null) {
            Navigator.of(context).pop(true);
          } else if (XunleiState.I.client.reviewPending) {
            _toast('仍需验证，请重新完成短信验证');
          } else {
            _toast('登录失败: $err');
          }
        },
      ),
    );
    controller.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    MiuixToast.show(msg);
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '登录迅雷云盘',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            MiuixText(
              '使用迅雷账号（手机号/邮箱）登录，登录后可浏览网盘文件并使用多线程不限速下载。',
              color: colors.onSurfaceSecondary,
              fontSize: 12,
            ),
            const SizedBox(height: 20),
            MiuixTextField(
              controller: _account,
              keyboardType: TextInputType.emailAddress,
              label: '手机号 / 邮箱',
              useLabelAsPlaceholder: true,
              singleLine: true,
              leadingIcon: MiuixIcon(icon: Icons.person_outline_rounded,
                  tint: colors.onSurfaceSecondary, size: 20),
            ),
            const SizedBox(height: 14),
            MiuixTextField(
              controller: _password,
              obscureText: _obscure,
              label: '密码',
              useLabelAsPlaceholder: true,
              singleLine: true,
              onSubmitted: (_) => _submit(),
              leadingIcon: MiuixIcon(icon: Icons.lock_outline_rounded,
                  tint: colors.onSurfaceSecondary, size: 20),
              trailingIcon: MiuixIconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                child: MiuixIcon(
                  icon: _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  tint: colors.onSurfaceSecondary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 24),
            MiuixButton(
              onPressed: _submitting ? null : _submit,
              colors: MiuixButtonColors(
                color: colors.primary,
                disabledColor: colors.primary,
                contentColor: Colors.white,
                disabledContentColor: Colors.white,
              ),
              child: _submitting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: MiuixCircularProgressIndicator(
                          size: 16,
                          colors: MiuixProgressIndicatorColors(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            backgroundColor: Colors.white24,
                          )),
                    )
                  : MiuixText('登录', color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 14),
            MiuixText(
              '提示：登录仅用于获取迅雷云盘下载直链，账号信息仅保存在本机。',
              color: colors.onSurfaceSecondary,
              fontSize: 11,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 风控短信验证密钥输入对话框（MiuixOverlayDialog 声明式包裹在 Navigator 弹层中）
class _ReviewKeyDialog extends StatefulWidget {
  final String reviewUrl;
  final TextEditingController controller;
  final VoidCallback onCopy;
  final VoidCallback onOpenBrowser;
  final VoidCallback onSubmit;

  const _ReviewKeyDialog({
    super.key,
    required this.reviewUrl,
    required this.controller,
    required this.onCopy,
    required this.onOpenBrowser,
    required this.onSubmit,
  });

  @override
  State<_ReviewKeyDialog> createState() => _ReviewKeyDialogState();
}

class _ReviewKeyDialogState extends State<_ReviewKeyDialog> {
  final MiuixPopupController _controller = MiuixPopupController(visible: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.show());
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixDialogLayout(
      controller: _controller,
      renderInRoot: false,
      content: (_) => MiuixOverlayDialog(
        show: true,
        title: '需要短信验证',
        onDismissRequest: _close,
        content: MiuixDismissScope(
          onDismissRequest: _close,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(
                  '本次登录触发了风控，请按以下步骤完成验证：',
                  color: colors.onSurfaceSecondary,
                  fontSize: 13,
                ),
                const SizedBox(height: 10),
                MiuixText('① 打开下面的验证链接（在浏览器中完成短信/滑块验证）',
                    fontSize: 13),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          widget.reviewUrl,
                          style:
                              TextStyle(fontSize: 11, color: colors.primary),
                        ),
                      ),
                      MiuixIconButton(
                        onPressed: widget.onCopy,
                        child: MiuixIcon(icon: Icons.copy_rounded,
                            tint: colors.primary, size: 18),
                      ),
                      if (!kIsWeb && Platform.isWindows)
                        MiuixIconButton(
                          onPressed: widget.onOpenBrowser,
                          child: MiuixIcon(icon: Icons.open_in_browser_rounded,
                              tint: colors.primary, size: 18),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MiuixText('② 验证完成后，复制页面显示的验证密钥（creditkey），粘贴到下面',
                    fontSize: 13),
                const SizedBox(height: 8),
                MiuixTextField(
                  controller: widget.controller,
                  label: '粘贴验证密钥 creditkey',
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: MiuixTextButton(
                        '取消',
                        onPressed: _close,
                        insideMargin: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MiuixTextButton(
                        '完成验证并登录',
                        onPressed: widget.onSubmit,
                        colors: MiuixButtonColors(
                          color: colors.primary,
                          disabledColor: colors.primary,
                          contentColor: Colors.white,
                          disabledContentColor: Colors.white,
                        ),
                        insideMargin: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
