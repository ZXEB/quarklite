import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';

/// 迅雷云盘接口异常
class XunleiException implements Exception {
  final int code;
  final String message;

  /// 响应里的 error 字段原文（如 captcha_invalid / space_token_invalid）
  final String rawError;

  XunleiException(this.code, this.message, {this.rawError = ''});

  @override
  String toString() => message;
}

/// 迅雷云盘容量信息（/user/me 响应，未返回容量时默认为 0）
class XunleiQuota {
  /// 总容量 / 已用容量（字节）
  final int totalSize;
  final int usedSize;

  const XunleiQuota({required this.totalSize, required this.usedSize});

  factory XunleiQuota.fromJson(Map<String, dynamic> json) {
    return XunleiQuota(
      totalSize: toInt(json['total_size'], fallback: 0),
      usedSize: toInt(json['used_size'], fallback: 0),
    );
  }

  bool get valid => totalSize > 0;
}

/// 迅雷云盘文件/文件夹
class XunleiFile {
  final String id;
  final String parentId;
  final String name;
  final int size;
  final bool isDir;
  final String webContentLink;

  /// 媒体流 CDN 链接（视频文件专用，限速策略与下载 CDN 不同）
  final String mediaUrl;

  /// 全部转码媒体变体（在线播放多清晰度选择用，label 取 media_name/清晰度名）
  final List<XunleiMediaVariant> mediaVariants;
  final String space;
  final String? updatedAt;

  const XunleiFile({
    required this.id,
    required this.parentId,
    required this.name,
    required this.size,
    required this.isDir,
    this.webContentLink = '',
    this.mediaUrl = '',
    this.mediaVariants = const [],
    this.space = '',
    this.updatedAt,
  });

  factory XunleiFile.fromJson(Map<String, dynamic> json) {
    var mediaUrl = '';
    final variants = <XunleiMediaVariant>[];
    final seenUrls = <String>{};
    final medias = json['medias'];
    if (medias is List) {
      for (final m in medias.whereType<Map>()) {
        final link = m['link'];
        if (link is Map) {
          final u = toStr(link['url']);
          if (u.isEmpty || !seenUrls.add(u)) continue;
          if (mediaUrl.isEmpty) mediaUrl = u;
          var label = toStr(m['media_name']);
          if (label.isEmpty) label = toStr(m['resolution_name']);
          if (toStr(m['whether_original']) == 'true') label = '原画';
          if (label.isEmpty) label = '流媒体 ${variants.length + 1}';
          variants.add(XunleiMediaVariant(label: label, url: u));
        }
      }
    }
    return XunleiFile(
      id: toStr(json['id']),
      parentId: toStr(json['parent_id']),
      name: toStr(json['name']),
      size: toInt(json['size']),
      isDir: toStr(json['kind']) == 'drive#folder',
      webContentLink: toStr(json['web_content_link']),
      mediaUrl: mediaUrl,
      mediaVariants: variants,
      space: toStr(json['space']),
      updatedAt: json['modified_time']?.toString(),
    );
  }

  /// 视频文件优先使用媒体 CDN 链接（限速策略不同，可能更快）
  String get bestDownloadUrl => mediaUrl.isNotEmpty ? mediaUrl : webContentLink;

  static const _videoExts = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'rmvb', 'rm',
  };

  bool get isVideo {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _videoExts.contains(name.substring(dot + 1).toLowerCase());
  }

  /// 下载用链接：视频且媒体链接可用时用媒体 CDN，否则用普通直链
  String downloadUrlFor() => isVideo ? bestDownloadUrl : webContentLink;
}

/// 转码媒体变体（在线播放清晰度选择用）
class XunleiMediaVariant {
  final String label;
  final String url;

  const XunleiMediaVariant({required this.label, required this.url});
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

  /// 根目录 parent_id（浏览器版未配置 root_folder_id，传空字符串）
  static const rootParentId = '';

  /// 下载直链必须使用客户端下载 UA（影响限速档位；迅雷 App 版实测档位更高）
  static const downloadUa =
      'Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC Build/SP1A.210812.016)';

  /// 登录后刷新验证码 token 用的签名算法链（thunder_browser 版）
  static const _algorithms = [
    'uWRwO7gPfdPB/0NfPtfQO+71',
    'F93x+qPluYy6jdgNpq+lwdH1ap6WOM+nfz8/V',
    '0HbpxvpXFsBK5CoTKam',
    'dQhzbhzFRcawnsZqRETT9AuPAJ+wTQso82mRv',
    'SAH98AmLZLRa6DB2u68sGhyiDh15guJpXhBzI',
    'unqfo7Z64Rie9RNHMOB',
    '7yxUdFADp3DOBvXdz0DPuKNVT35wqa5z0DEyEvf',
    'RBG',
    'ThTWPG5eC0UBqlbQ+04nZAptqGCdpv9o55A',
  ];

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

  /// captcha_sign：MD5 链签名（登录后刷新验证码 token 用）
  String _captchaSign(String timestamp) {
    var str = '$clientId$clientVersion$packageName$deviceId$timestamp';
    for (final alg in _algorithms) {
      str = _md5(str + alg);
    }
    return '1.$str';
  }

  /// 生成接口 action（方法:路径），对照 AList GetAction
  static String actionOf(String method, String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return '$method:$path';
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
      throw XunleiException(code, desc, rawError: err);
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
      // 登录成功后主动刷新验证码 token，避免首个云盘请求报『验证码无效』
      try {
        await _refreshCaptchaAtLogin('POST:/v1/auth/signin');
      } catch (_) {
        // 刷新失败不阻塞登录，云盘请求失败时会自动再刷
      }
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

  /// 登录后刷新验证码 token（云盘请求返回 captcha_invalid 时调用）
  Future<void> _refreshCaptchaAtLogin(String action) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final map = await _post('$_authBase/shield/captcha/init', {
        'action': action,
        'captcha_token': captchaToken,
        'client_id': clientId,
        'device_id': deviceId,
        'meta': {
          'client_version': clientVersion,
          'package_name': packageName,
          'user_id': userId,
          'timestamp': ts,
          'captcha_sign': _captchaSign(ts),
        },
        'redirect_uri': 'xlaccsdk01://xunlei.com/callback?state=harbor',
      });
      captchaToken = toStr(map['captcha_token']);
      AppLogger.I.i('xunlei', '刷新验证码 token: ${captchaToken.isNotEmpty}');
    } catch (e) {
      AppLogger.I.w('xunlei', '刷新验证码 token 失败: $e');
      rethrow;
    }
  }

  /// 带 token 续期/验证码刷新的请求包装：过期错误码自动处理并重试一次
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
      if (e.code == 9 &&
          (e.rawError == 'captcha_invalid' ||
              e.message.contains('验证码') ||
              e.message.contains('captcha'))) {
        // 验证码 token 过期：登录后刷新再重试
        await _refreshCaptchaAtLogin(actionOf('GET', url));
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

  /// 批量获取文件详情（含直链/媒体链接，失败项跳过）
  Future<Map<String, XunleiFile>> getDownloadFiles(
      List<(String, String)> idAndSpace) async {
    final result = <String, XunleiFile>{};
    for (final (id, space) in idAndSpace) {
      try {
        final f = await getFileDetail(id, space: space);
        if (f.webContentLink.isNotEmpty || f.mediaUrl.isNotEmpty) {
          result[id] = f;
        }
      } catch (_) {
        // 单个失败跳过
      }
    }
    return result;
  }

  /// 拉取账号容量信息（/user/me 响应）
  Future<XunleiQuota> fetchQuota() async {
    final map = await _authGet('$_authBase/user/me');
    return XunleiQuota.fromJson(map);
  }
}
