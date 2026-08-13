import 'package:flutter/material.dart';

import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';

/// 迅雷云盘账号密码登录页
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
    } else {
      _toast('登录失败: $err');
    }
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
