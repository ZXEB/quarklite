import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/netdisk123_client.dart';
import '../../theme/app_theme.dart';

/// 123 网盘流量包充值页（内置 WebView，默认 0.5 元流量包）
class Netdisk123PayPage extends StatefulWidget {
  final String url;
  const Netdisk123PayPage({super.key, this.url = Netdisk123Client.kPayUrl});

  @override
  State<Netdisk123PayPage> createState() => _Netdisk123PayPageState();
}

class _Netdisk123PayPageState extends State<Netdisk123PayPage> {
  WebViewController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
      ))
      ..loadRequest(Uri.parse(widget.url));
    _controller = c;
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '流量包充值',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
        actions: [
          MiuixIconButton(
            onPressed: () => _controller?.reload(),
            child: MiuixIcon(icon: Icons.refresh_rounded, tint: colors.primary),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Stack(
          children: [
            if (_controller != null) WebViewWidget(controller: _controller!),
            if (_loading)
              MiuixLinearProgressIndicator(
                progress: null,
                height: 2,
                colors: MiuixProgressIndicatorColors(
                  foregroundColor: colors.primary,
                  disabledForegroundColor: colors.primary,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
