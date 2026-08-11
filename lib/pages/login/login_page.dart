import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/quark_auth.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
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
      appBar: AppBar(
        title: const Text('登录夸克账号'),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(text: '扫码登录'),
              Tab(text: 'Cookie 登录'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _QrLoginView(),
                _CookieLoginView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrLoginView extends StatefulWidget {
  const _QrLoginView();

  @override
  State<_QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends State<_QrLoginView> {
  final _auth = QuarkQrLogin();
  String? _qrUrl;
  String? _status;
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
      final url = await _auth.fetchQrUrl();
      if (!mounted) return;
      setState(() {
        _qrUrl = url;
        _loading = false;
        _status = '请使用夸克 App 扫码登录';
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
      String? cookie;
      try {
        cookie = await _auth.checkOnce();
      } catch (_) {
        return;
      }
      if (cookie == null || !mounted) return;
      _pollTimer?.cancel();
      _loginDone = true;
      setState(() => _status = '登录成功，正在验证…');
      final err = await AppState.I.login(cookie);
      if (!mounted) return;
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _status = '验证失败: $err';
          _loginDone = false;
        });
        _startPolling();
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
              const Icon(Icons.qr_code_2_rounded,
                  size: 120, color: AppColors.cardLight),
            const SizedBox(height: 20),
            Text(
              _status ?? '',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '二维码 5 分钟内有效，请用夸克 App「扫一扫」登录',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _refresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
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

class _CookieLoginView extends StatefulWidget {
  const _CookieLoginView();

  @override
  State<_CookieLoginView> createState() => _CookieLoginViewState();
}

class _CookieLoginViewState extends State<_CookieLoginView> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '从浏览器登录 pan.quark.cn 后，复制 Cookie 粘贴到这里（登录二维码失效时的备用方式）',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 Cookie，形如 __pus=xxx; __puus=xxx; ...',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final cookie = _controller.text.trim();
    if (cookie.isEmpty) {
      _toast('请先粘贴 Cookie');
      return;
    }
    setState(() => _submitting = true);
    final err = await AppState.I.login(cookie);
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
}
