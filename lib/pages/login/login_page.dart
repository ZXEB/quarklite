import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/quark_auth.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '登录夸克账号',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceVariant,
              size: 20),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: MiuixTabRow(
                tabs: const ['扫码登录', 'Cookie 登录'],
                selectedTabIndex: _tabIndex,
                onTabSelected: (i) => setState(() => _tabIndex = i),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: const [
                  _QrLoginView(),
                  _CookieLoginView(),
                ],
              ),
            ),
          ],
        ),
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
    final colors = MiuixTheme.of(context).colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              const MiuixCircularProgressIndicator()
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
              MiuixIcon(Icons.qr_code_2_rounded,
                  size: 120, tint: AppColors.cardLight),
            const SizedBox(height: 20),
            MiuixText(
              _status ?? '',
              color: colors.onSurfaceSecondary,
              fontSize: 13,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            MiuixText(
              '二维码 5 分钟内有效，请用夸克 App「扫一扫」登录',
              color: colors.onSurfaceSecondary,
              fontSize: 11,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            MiuixTextButton(
              '刷新二维码',
              onPressed: _refresh,
              colors: MiuixButtonColors(color: colors.primary),
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
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuixText(
            '从浏览器登录 pan.quark.cn 后，复制 Cookie 粘贴到这里（登录二维码失效时的备用方式）',
            color: colors.onSurfaceSecondary,
            fontSize: 12,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: MiuixTextField(
              controller: _controller,
              maxLines: null,
              minLines: 6,
              label: '粘贴 Cookie，形如 __pus=xxx; __puus=xxx; ...',
              useLabelAsPlaceholder: true,
            ),
          ),
          const SizedBox(height: 16),
          MiuixButton(
            onPressed: _submitting ? null : _submit,
            colors: MiuixButtonColors(
              color: colors.primary,
              contentColor: Colors.white,
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
    MiuixToast.show(msg);
  }
}
