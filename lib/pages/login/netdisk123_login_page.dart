import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/netdisk123_client.dart';
import '../../state/netdisk123_state.dart';
import '../../theme/app_theme.dart';

/// 123 网盘登录页（密码登录 + 扫码登录 Tab 切换）
class Netdisk123LoginPage extends StatefulWidget {
  const Netdisk123LoginPage({super.key});

  @override
  State<Netdisk123LoginPage> createState() => _Netdisk123LoginPageState();
}

class _Netdisk123LoginPageState extends State<Netdisk123LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 123 网盘')),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(text: '密码登录'),
              Tab(text: '扫码登录'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _PasswordLoginView(),
                _QrLoginView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordLoginView extends StatefulWidget {
  const _PasswordLoginView();

  @override
  State<_PasswordLoginView> createState() => _PasswordLoginViewState();
}

class _PasswordLoginViewState extends State<_PasswordLoginView> {
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
    final err = await Netdisk123State.I.login(account, password);
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '使用 123 网盘账号（手机号 / 邮箱）登录，登录后可浏览网盘文件并使用多线程不限速下载。',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _account,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
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
            prefixIcon: Icon(Icons.lock_outline_rounded,
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
        Text(
          '提示：登录仅用于获取 123 网盘下载直链，账号信息仅保存在本机。',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _QrLoginView extends StatefulWidget {
  const _QrLoginView();

  @override
  State<_QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends State<_QrLoginView> {
  final _qr = Netdisk123QrLogin();
  String? _qrUrl;
  String _status = '正在获取二维码…';
  bool _loading = true;
  Timer? _pollTimer;
  bool _loginDone = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _qrUrl = null;
      _status = '正在获取二维码…';
    });
    try {
      final url = await _qr.fetchQrUrl();
      if (!mounted) return;
      setState(() {
        _qrUrl = url;
        _loading = false;
        _status = '请使用 123 网盘 App 扫码登录';
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '获取二维码失败: $e';
      });
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_loginDone) return;
      int status;
      try {
        status = await _qr.pollStatus();
      } catch (_) {
        return;
      }
      if (!mounted) return;
      // 0 等待 / 1 已扫 / 2 确认 / 3 过期 / 4 无会话
      if (status == 1) {
        setState(() => _status = '已扫码，请确认登录');
      } else if (status == 3) {
        _pollTimer?.cancel();
        setState(() => _status = '二维码已过期，请刷新');
      } else if (status == 2) {
        _pollTimer?.cancel();
        _loginDone = true;
        setState(() => _status = '登录成功，正在验证…');
        try {
          final token = await _qr.login();
          await Netdisk123State.I.loginByToken(token);
          if (!mounted) return;
          Navigator.of(context).pop(true);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _status = '登录失败: $e';
            _loginDone = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              const CircularProgressIndicator()
            else if (_qrUrl != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: _qrUrl!,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              )
            else
              Icon(Icons.qr_code_2_rounded,
                  size: 120, color: AppColors.cardLight),
            const SizedBox(height: 20),
            Text(
              _status,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '二维码有效期约 5 分钟，请用 123 网盘 App「扫一扫」登录',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _refresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              ),
              child: const Text('刷新二维码'),
            ),
          ],
        ),
      ),
    );
  }
}
