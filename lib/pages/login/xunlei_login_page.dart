import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
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
      builder: (ctx) => AlertDialog(
        title: const Text('需要短信验证'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本次登录触发了风控，请按以下步骤完成验证：',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              const Text(
                '① 打开下面的验证链接（在浏览器中完成短信/滑块验证）',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cardLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        reviewUrl,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.accent),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: reviewUrl));
                        _toast('验证链接已复制');
                      },
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: AppColors.accent),
                      tooltip: '复制链接',
                    ),
                    if (!kIsWeb && Platform.isWindows)
                      IconButton(
                        onPressed: () async {
                          try {
                            await Process.start(
                                'cmd', ['/c', 'start', '', reviewUrl]);
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.open_in_browser_rounded,
                            size: 18, color: AppColors.accent),
                        tooltip: '打开浏览器',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '② 验证完成后，复制页面显示的验证密钥（creditkey），粘贴到下面',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '粘贴验证密钥 creditkey',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
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
            child: const Text('完成验证并登录'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录迅雷云盘')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '使用迅雷账号（手机号/邮箱）登录，登录后可浏览网盘文件并使用多线程不限速下载。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _account,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '手机号 / 邮箱',
              prefixIcon: Icon(Icons.person_outline_rounded,
                  color: AppColors.textSecondary, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: _obscure,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded,
                  color: AppColors.textSecondary, size: 20),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
          const SizedBox(height: 14),
          const Text(
            '提示：登录仅用于获取迅雷云盘下载直链，账号信息仅保存在本机。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
