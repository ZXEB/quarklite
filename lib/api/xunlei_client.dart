import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';

/// 迅雷云盘接口异常
class XunleiException implements Exception {
  final int code;
  final String message;

  XunleiException(this.code, this.message);

  @override
  String toString() => message;
}

/// 迅雷云盘文件/文件夹
class XunleiFile {
  final String id;
  final String parentId;
  final String name;
  final int size;
  final bool isDir;
  final String webContentLink;
  final String space;
  final String? updatedAt;

  const XunleiFile({
    required this.id,
    required this.parentId,
    required this.name,
    required this.size,
    required this.isDir,
    this.webContentLink = '',
    this.space = '',
    this.updatedAt,
  });

  factory XunleiFile.fromJson(Map<String, dynamic> json) {
    return XunleiFile(
      id: toStr(json['id']),
      parentId: toStr(json['parent_id']),
      name: toStr(json['name']),
      size: toInt(json['size']),
      isDir: toStr(json['kind']) == 'drive#folder',
      webContentLink: toStr(json['web_content_link']),
      space: toStr(json['space']),
      updatedAt: json['modified_time']?.toString(),
    );
  }
}

/// 迅雷云盘客户端（按 AList thunder_browser 驱动实现，2026-08 现行可用流程）：
/// captcha init（meta 只放账号字段）→ /v1/auth/signin（账号密码）→ refresh_token 续期。
class XunleiClient {
  // ---------------- 客户端凭据（迅雷浏览器） ----------------
  static const clientId = 'ZUBzD9J_XPXfn7f7';
  static const clientSecret = 'yESVmHecEe6F0aou69vl-g';
  static const clientVersion = '1.10.0.2633';
  static const packageName = 'com.xunlei.browser';
  static const sdkVersion = '233100';
  static const appId = '22062';

  static const _authBase = 'https://xluser-ssl.xunlei.com/v1';
  static const _driveBase = 'https://x-api-pan.xunlei.com/drive/v1';

  /// 浏览器网盘根目录 space
  static const rootSpace = 'SPACE_BROWSER';

  /// 下载直链必须使用客户端下载 UA（影响限速档位）
  static const downloadUa =
      'AndroidDownloadManager/13 (Linux; U; Android 13; M2004J7AC Build/SP1A.210812.016)';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String accessToken = '';
  String refreshToken = '';
  String userId = '';
  String deviceId = '';
  String captchaToken = '';

  /// 风控验证：验证链接与人工验证后的密钥（review_panel 流程）
  String reviewUrl = '';
  String creditKey = '';

  bool get hasLogin => accessToken.isNotEmpty;
  bool get reviewPending => reviewUrl.isNotEmpty;

  void setTokens(
      {String access = '', String refresh = '', String user = '', String device = ''}) {
    accessToken = access;
    refreshToken = refresh;
    userId = user;
    if (device.isNotEmpty) deviceId = device;
  }

  // ---------------- 工具 ----------------

  static String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  /// 设备 ID：与登录凭据绑定（md5(账号+密码) / md5(refresh_token)），对照 AList 实现
  static String deviceIdFor(String seed) => _md5(seed);

  /// 账号规范化：去掉 +86/空格/横线，服务端只接受纯手机号/邮箱
  static String normalizeAccount(String account) {
    var a = account.trim();
    a = a.replaceAll(RegExp(r'[\s-]'), '');
    if (a.startsWith('+86')) a = a.substring(3);
    return a;
  }

  /// 请求 UA（与设备 ID 绑定，格式对照 AList BuildCustomUserAgent）
  static String buildUserAgent(String deviceId) =>
      'ANDROID-com.xunlei.browser/$clientVersion networkType/WIFI appid/$appId '
      'deviceName/Xiaomi_M2004j7ac deviceModel/M2004J7AC OSVersion/13 '
      'protocolVersion/301 platformversion/10 sdkVersion/$sdkVersion '
      'Oauth2Client/0.9 (Linux 4_9_337-perf-sn-uotan-gd9d488809c3d) (JAVA 0)';

  Map<String, dynamic> _authHeaders() => {
        'user-agent': buildUserAgent(deviceId),
        'accept': 'application/json;charset=UTF-8',
        'x-device-id': deviceId,
        'x-client-id': clientId,
        'x-client-version': clientVersion,
        if (accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
        if (captchaToken.isNotEmpty) 'X-Captcha-Token': captchaToken,
      };

  Future<Map<String, dynamic>> _post(
      String url, Map<String, dynamic> body) async {
    final resp = await _dio.post<dynamic>(url,
        data: body,
        options: Options(headers: _authHeaders(), validateStatus: (_) => true));
    return _parse(resp);
  }

  Future<Map<String, dynamic>> _get(String url,
      {Map<String, dynamic>? params}) async {
    final resp = await _dio.get<dynamic>(url,
        queryParameters: params,
        options: Options(
            headers: _authHeaders(), validateStatus: (_) => true));
    return _parse(resp);
  }

  Map<String, dynamic> _parse(Response<dynamic> resp) {
    final body = resp.data;
    final map = body is Map
        ? body.cast<String, dynamic>()
        : body is String && body.isNotEmpty
            ? (jsonDecode(body) as Map<String, dynamic>)
            : <String, dynamic>{};
    final code = toInt(map['error_code'], fallback: -1);
    final err = toStr(map['error']);
    if (code != 0 && err != 'success' && err.isNotEmpty) {
      final desc = toStr(map['error_description'], fallback: err);
      // 风控 review：提取验证链接与 creditkey 供用户完成人工验证
      if (err == 'review_panel' ||
          err == 'review' ||
          desc.contains('result:review') ||
          desc.contains('review_panel')) {
        reviewUrl = toStr(map['reviewurl'], fallback: toStr(map['url']));
        if (map['creditkey'] != null) creditKey = toStr(map['creditkey']);
        AppLogger.I.w('xunlei', '触发风控 review: $desc url=$reviewUrl');
      }
      throw XunleiException(code, desc);
    }
    return map;
  }

  // ---------------- 认证 ----------------

  /// 第一步：获取验证码 token（meta 固定用 username 字段，
  /// 服务端校验 meta.username，传 phone_number/email 会报错）
  Future<void> initCaptcha(String username) async {
    final map = await _post('$_authBase/shield/captcha/init', {
      'action': 'POST:/v1/auth/signin',
      'captcha_token': '',
      'client_id': clientId,
      'device_id': deviceId,
      if (creditKey.isNotEmpty) 'creditkey': creditKey,
      'meta': {
        'username': username,
      },
      'redirect_uri': 'xlaccsdk01://xunlei.com/callback?state=harbor',
    });
    final url = toStr(map['url']);
    if (url.isNotEmpty) {
      // 需要人工验证：记录验证链接
      reviewUrl = url;
      if (map['creditkey'] != null) creditKey = toStr(map['creditkey']);
      AppLogger.I.w('xunlei', 'captcha init 需要验证: $url');
      throw XunleiException(-1, '需要短信验证');
    }
    captchaToken = toStr(map['captcha_token']);
  }

  /// 第二步：账号密码登录，返回 null 表示成功
  Future<String?> signin(String username, String password) async {
    try {
      username = normalizeAccount(username);
      await initCaptcha(username);
      final map = await _post('$_authBase/auth/signin', {
        'captcha_token': captchaToken,
        'client_id': clientId,
        'client_secret': clientSecret,
        'username': username,
        'password': password,
        if (creditKey.isNotEmpty) 'creditkey': creditKey,
      });
      final access = toStr(map['access_token']);
      if (access.isEmpty) {
        final err = toStr(map['error']);
        if (err == 'review_panel') {
          return '需要短信验证';
        }
        return '登录失败: ${toStr(map['error_description'], fallback: err)}';
      }
      accessToken = access;
      refreshToken = toStr(map['refresh_token']);
      userId = toStr(map['user_id'], fallback: toStr(map['sub']));
      reviewUrl = '';
      creditKey = '';
      return null;
    } on XunleiException catch (e) {
      if (e.message == '需要短信验证' ||
          e.message.contains('review') ||
          reviewPending) {
        return '需要短信验证';
      }
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// refresh_token 续期，返回 null 表示成功
  Future<String?> refresh() async {
    if (refreshToken.isEmpty) return 'refresh_token 缺失，请重新登录';
    try {
      final map = await _post('$_authBase/auth/token', {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
      });
      final access = toStr(map['access_token']);
      if (access.isEmpty) return '续期失败，请重新登录';
      accessToken = access;
      final rt = toStr(map['refresh_token']);
      if (rt.isNotEmpty) refreshToken = rt; // 服务端可能不轮换
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// 带 token 续期的请求包装：过期错误码自动续期重试一次
  Future<Map<String, dynamic>> _authGet(String url,
      {Map<String, dynamic>? params}) async {
    try {
      return await _get(url, params: params);
    } on XunleiException catch (e) {
      if (e.code == 4122 || e.code == 4121 || e.code == 10 || e.code == 16) {
        final err = await refresh();
        if (err != null) rethrow;
        return _get(url, params: params);
      }
      rethrow;
    }
  }

  // ---------------- 云盘 ----------------

  /// 文件列表（自动翻页）。根目录 space 为 SPACE_BROWSER，子目录沿用文件自身的 space。
  Future<List<XunleiFile>> listFiles(String parentId,
      {String space = rootSpace}) async {
    final files = <XunleiFile>[];
    var pageToken = '';
    for (var page = 0; page < 100; page++) {
      final map = await _authGet('$_driveBase/files', params: {
        'parent_id': parentId,
        'page_token': pageToken,
        'space': space,
        'filters': jsonEncode({
          'trashed': {'eq': false},
        }),
        'with': 'url',
        'with_audit': true,
        'thumbnail_size': 'SIZE_LARGE',
      });
      final list = map['files'];
      if (list is! List) break;
      for (final item in list.whereType<Map>()) {
        files.add(XunleiFile.fromJson(item.cast<String, dynamic>()));
      }
      final next = toStr(map['next_page_token']);
      if (next.isEmpty) break;
      pageToken = next;
    }
    return files;
  }

  /// 获取文件详情（含高速下载直链）
  Future<XunleiFile> getFileDetail(String id, {String space = ''}) async {
    final map = await _authGet('$_driveBase/files/$id', params: {
      '_magic': '2021',
      'space': space,
      'thumbnail_size': 'SIZE_LARGE',
      'with': 'url',
    });
    return XunleiFile.fromJson(map);
  }

  /// 批量获取直链（逐文件请求，失败项跳过）
  Future<Map<String, String>> getDownloadLinks(
      List<(String, String)> idAndSpace) async {
    final result = <String, String>{};
    for (final (id, space) in idAndSpace) {
      try {
        final f = await getFileDetail(id, space: space);
        if (f.webContentLink.isNotEmpty) {
          result[id] = f.webContentLink;
        }
      } catch (_) {
        // 单个失败跳过
      }
    }
    return result;
  }
}
