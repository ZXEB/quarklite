import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../widgets/miuix_common.dart';

/// 应用内风控验证页：WebView 加载迅雷验证页（图形/短信验证），
/// 注入 JS bridge 桥接原生通信，验证成功后自动拿到新 creditkey。
///
/// 返回值为新 creditkey（String?）；用户取消或失败返回 null。
class XunleiReviewPage extends StatefulWidget {
  final String reviewUrl;
  final String creditKey;
  final String deviceId;

  const XunleiReviewPage({
    super.key,
    required this.reviewUrl,
    required this.creditKey,
    required this.deviceId,
  });

  @override
  State<XunleiReviewPage> createState() => _XunleiReviewPageState();
}

class _XunleiReviewPageState extends State<XunleiReviewPage> {
  WebViewController? _controller;
  Timer? _pollTimer;
  bool _done = false;
  String _status = '正在加载验证页面…';
  int _injectCount = 0;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _setup() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          // 页面脚本执行前注入 bridge（多次导航都会注入，容错）
          _injectBridge();
        },
        onPageFinished: (url) {
          // 兜底：页面加载完成后确认 bridge 生效，未生效再补一次注入
          _injectBridge();
        },
      ))
      ..loadRequest(Uri.parse(widget.reviewUrl));
    _controller = controller;
    // 轮询验证结果
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  /// 注入原生通信桥：mock XLJSWebViewBridge + 写入初始 review 数据
  void _injectBridge() {
    final c = _controller;
    if (c == null || _done) return;
    _injectCount++;
    final data = jsonEncode({
      'creditkey': widget.creditKey,
      'reviewurl': widget.reviewUrl,
      'deviceid': widget.deviceId,
      'devicesign': widget.deviceId,
    });
    final js = '''
(function(){
  if (!window.__XL_BRIDGE_INSTALLED__) {
    window.__XL_BRIDGE_INSTALLED__ = true;
    window.__XL_OPERATION_RESULT__ = '';
    window.__XL_REVIEW_DATA__ = ${jsonEncode(data)};
    if (!window.XLJSWebViewBridge) {
      window.XLJSWebViewBridge = {
        sendMessage: function(name, data, cb) {
          if (name === 'nativeGetUserDeviceInfo') {
            var payload = window.__XL_REVIEW_DATA__ || '';
            var obj = null;
            try { obj = JSON.parse(payload); } catch(e) { obj = payload; }
            if (cb && window[cb]) {
              try { window[cb](obj); } catch(e) {}
            }
          } else if (name === 'nativeRecvOperationResult') {
            window.__XL_OPERATION_RESULT__ = data;
          }
        }
      };
    }
  }
})();
''';
    c.runJavaScript(js).catchError((Object e) {
      AppLogger.I.w('xunlei', 'bridge 注入失败: $e');
      return '';
    });
  }

  /// 轮询验证结果：nativeRecvOperationResult 回调
  Future<void> _poll() async {
    final c = _controller;
    if (c == null || _done) return;
    try {
      final obj = await c.runJavaScriptReturningResult(
          'window.__XL_OPERATION_RESULT__ || ""');
      if (obj is! String || obj.isEmpty) return;
      final text = obj;
      _done = true;
      _pollTimer?.cancel();
      AppLogger.I.i('xunlei', '验证结果: $text');
      Map<String, dynamic> result;
      try {
        result = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        result = <String, dynamic>{};
      }
      final roCode = result['roErrorCode']?.toString() ?? '';
      final roData = result['roData'];
      if (roCode == '0' && roData is Map && roData['creditkey'] != null) {
        final key = roData['creditkey'].toString();
        if (key.isNotEmpty) {
          if (mounted) Navigator.of(context).pop(key);
          return;
        }
      }
      // 取消或失败
      if (mounted) Navigator.of(context).pop(null);
    } catch (e) {
      // 页面未就绪等，继续轮询
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '账号验证',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
        actions: [
          MiuixTextButton(
            '取消',
            onPressed: () => Navigator.of(context).pop(null),
            colors: MiuixButtonColors(color: colors.onSurfaceSecondary, disabledColor: colors.onSurfaceSecondary, contentColor: Colors.white, disabledContentColor: Colors.white),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: colors.surface,
              child: MiuixText(
                '请在下方完成短信/滑块验证，验证通过后自动登录',
                color: colors.onSurfaceSecondary,
                fontSize: 12,
              ),
            ),
            Expanded(
              child: _controller == null
                  ? const Center(child: MiuixCircularProgressIndicator())
                  : WebViewWidget(controller: _controller!),
            ),
          ],
        ),
      ),
    );
  }
}
