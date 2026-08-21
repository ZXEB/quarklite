import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('流量包充值'),
        actions: [
          IconButton(
            onPressed: () => _controller?.reload(),
            icon: Icon(Icons.refresh_rounded, color: AppColors.accent),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_loading) LinearProgressIndicator(minHeight: 2, color: AppColors.accent),
        ],
      ),
    );
  }
}
