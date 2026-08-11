import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'quark_client.dart';

class QuarkQrLogin {
  static const _base = 'https://uop.quark.cn/cas/ajax';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  String? _token;

  Map<String, dynamic> _headers() => {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'User-Agent': QuarkClient.uaPc,
        'Referer': 'https://pan.quark.cn/',
      };

  /// 获取二维码（返回二维码 URL）
  Future<String> fetchQrUrl() async {
    final requestId = _uuid();
    final resp = await _dio.get('$_base/getTokenForQrcodeLogin',
        queryParameters: {'client_id': '532', 'v': '1.2', 'request_id': requestId},
        options: Options(headers: _headers(), validateStatus: (_) => true));
    final body = _decode(resp);
    final members = body['data']?['members'];
    final token = members?['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('获取登录二维码失败: ${body['message'] ?? '未知错误'}');
    }
    _token = token;
    final params = {
      'token': token,
      'client_id': '532',
      'ssb': 'weblogin',
      'uc_param_str': '',
      'uc_biz_str': 'S:custom|OPT:SAREA@0|OPT:IMMERSIVE@1|OPT:BACK_BTN_STYLE@0',
    };
    final qs = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'https://su.quark.cn/4_eMHBJ?$qs';
  }

  /// 轮询扫码结果，成功后返回 cookie 字符串，未扫码时返回 null
  Future<String?> checkOnce() async {
    final token = _token;
    if (token == null) throw Exception('请先获取二维码');
    final requestId = _uuid();
    final resp = await _dio.get('$_base/getServiceTicketByQrcodeToken',
        queryParameters: {
          'client_id': '532',
          'v': '1.2',
          'token': token,
          'request_id': requestId,
        },
        options: Options(headers: _headers(), validateStatus: (_) => true));
    final body = _decode(resp);
    final status = toInt(body['status'], fallback: -1);
    final serviceTicket =
        body['data']?['members']?['service_ticket']?.toString();
    if (status == 2000000 &&
        serviceTicket != null &&
        serviceTicket.isNotEmpty) {
      return _exchangeTicket(serviceTicket);
    }
    return null;
  }

  /// 用 service ticket 换取 pan.quark.cn 的登录 cookie
  Future<String> _exchangeTicket(String ticket) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
    ));
    final resp = await dio.get('https://pan.quark.cn/account/info',
        queryParameters: {'st': ticket, 'lw': 'scan'},
        options: Options(headers: {
          'User-Agent': QuarkClient.uaPc,
          'Referer': 'https://pan.quark.cn/',
        }, validateStatus: (_) => true));
    final setCookies = resp.headers['set-cookie'] ?? [];
    final entries = <String, String>{};
    for (final raw in setCookies) {
      final seg = raw.split(';').first.trim();
      final eq = seg.indexOf('=');
      if (eq <= 0) continue;
      final k = seg.substring(0, eq).trim();
      if (k == 'push_vurl' || k == 'logout_id') continue;
      entries[k] = seg.substring(eq + 1).trim();
    }
    if (entries.isEmpty) {
      throw Exception('登录失败：未获取到有效会话');
    }
    return entries.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Map<String, dynamic> _decode(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      return jsonDecode(body) as Map<String, dynamic>;
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }

  String _uuid() {
    final r = Random();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
        '-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
