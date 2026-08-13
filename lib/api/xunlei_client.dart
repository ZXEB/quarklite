import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

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
  final String? updatedAt;

  const XunleiFile({
    required this.id,
    required this.parentId,
    required this.name,
    required this.size,
    required this.isDir,
    this.webContentLink = '',
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
      updatedAt: json['modified_time']?.toString(),
    );
  }
}

/// 迅雷云盘客户端（逆向接口，见 docs/xunlei_api.md）。
/// 凭据使用「迅雷 App」客户端（文档推荐，UA 完整）。
class XunleiClient {
  // ---------------- 客户端凭据（迅雷 App） ----------------
  static const clientId = 'Xp6vsxz_7IYVw2BB';
  static const clientSecret = 'Xp6vsy4tN9toTVdMSpomVdXpRmES';
  static const clientVersion = '8.31.0.9726';
  static const packageName = 'com.xunlei.downloadprovider';

  static const _authBase = 'https://xluser-ssl.xunlei.com/v1';
  static const _coreLoginBase = 'https://xluser-ssl.xunlei.com/xluser.core.login/v3';
  static const _driveBase = 'https://api-pan.xunlei.com/drive/v1';

  static const appId = '40';
  static const appKey = '34a062aaa22f906fca4fefe9fb3a3021';

  static const requestUa =
      'ANDROID-com.xunlei.downloadprovider/8.31.0.9726 netWorkType/5G appid/40 '
      'deviceName/Xiaomi_M2004j7ac deviceModel/M2004J7AC OSVersion/12 '
      'protocolVersion/301 platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 '
      '(Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)';

  /// 下载直链必须使用客户端下载 UA（影响限速档位）
  static const downloadUa =
      'Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC Build/SP1A.210812.016)';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String accessToken = '';
  String refreshToken = '';
  String userId = '';
  String deviceId = '';
  String captchaToken = '';

  bool get hasLogin => accessToken.isNotEmpty;

  void setTokens(
      {String access = '', String refresh = '', String user = '', String device = ''}) {
    accessToken = access;
    refreshToken = refresh;
    userId = user;
    if (device.isNotEmpty) deviceId = device;
  }

  // ---------------- 工具 ----------------

  static String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  static String _sha1Hex(String s) => sha1.convert(utf8.encode(s)).toString();

  /// 生成随机 32 位 hex device_id
  static String randomDeviceId() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 设备签名：md5(sha1hex(deviceID + packageName + APPID + APPKey))
  static String generateDeviceSign(String deviceId, String packageName) =>
      _md5(_sha1Hex('$deviceId$packageName$appId$appKey'));

  Map<String, dynamic> _authHeaders() => {
        'user-agent': requestUa,
        'accept': 'application/json;charset=UTF-8',
        'x-device-id': deviceId,
        'x-client-id': clientId,
        'x-client-version': clientVersion,
        if (accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
        if (captchaToken.isNotEmpty) 'X-Captcha-Token': captchaToken,
      };

  Future<Map<String, dynamic>> _post(
      String url, Map<String, dynamic> body,
      {Map<String, dynamic>? headers}) async {
    final resp = await _dio.post<dynamic>(url,
        data: body,
        options: Options(
            headers: {..._authHeaders(), ...?headers},
            validateStatus: (_) => true));
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
      throw XunleiException(code, toStr(map['error_description'], fallback: err));
    }
    return map;
  }

  // ---------------- 认证 ----------------

  /// 第一步：CoreLogin（v3），返回 sessionID
  Future<String> coreLogin(String username, String password) async {
    final map = await _post('$_coreLoginBase/login', {
      'protocolVersion': '301',
      'sequenceNo': '1000012',
      'platformVersion': '10',
      'isCompressed': '0',
      'appid': appId,
      'clientVersion': clientVersion,
      'peerID': '00000000000000000000000000000000',
      'appName': packageName,
      'sdkVersion': '512000',
      'devicesign': generateDeviceSign(deviceId, packageName),
      'netWorkType': 'WIFI',
      'providerName': 'NONE',
      'deviceModel': 'M2004J7AC',
      'deviceName': 'Xiaomi_M2004j7ac',
      'OSVersion': '12',
      'creditkey': '',
      'hl': 'zh-CN',
      'userName': username,
      'passWord': password,
      'verifyKey': '',
      'verifyCode': '',
      'isMd5Pwd': '0',
    }, headers: {
      'user-agent': 'android-ok-http-client/xl-acc-sdk/version-5.0.12.512000',
    });
    final sessionId = toStr(map['sessionID']);
    if (sessionId.isEmpty) {
      throw XunleiException(
          -1, '登录失败: ${toStr(map['error_description'], fallback: toStr(map['error']))}');
    }
    return sessionId;
  }

  /// 第二步：获取验证码 token（登录时 meta 只放账号字段，不带签名）
  Future<void> initCaptcha(String username) async {
    final meta = <String, dynamic>{};
    if (username.contains('@')) {
      meta['email'] = username;
    } else if (username.length >= 11 && username.length <= 18) {
      meta['phone_number'] = username;
    } else {
      meta['username'] = username;
    }
    final map = await _post('$_authBase/shield/captcha/init', {
      'action': 'POST:/v1/auth/signin/token',
      'captcha_token': '',
      'client_id': clientId,
      'device_id': deviceId,
      'meta': meta,
      'redirect_uri': 'xlaccsdk01://xunlei.com/callback?state=harbor',
    });
    final url = toStr(map['url']);
    if (url.isNotEmpty) {
      throw XunleiException(-1, '触发风控，需要人工验证');
    }
    captchaToken = toStr(map['captcha_token']);
  }

  /// 第三步：用 sessionID 换取 access_token
  Future<void> signinWithSession(String sessionId) async {
    final map = await _post('$_authBase/auth/signin/token', {
      'client_id': clientId,
      'client_secret': clientSecret,
      'provider': 'access_end_point_token',
      'signin_token': sessionId,
    });
    final access = toStr(map['access_token']);
    if (access.isEmpty) {
      throw XunleiException(
          -1, '登录失败: ${toStr(map['error_description'], fallback: toStr(map['error']))}');
    }
    accessToken = access;
    refreshToken = toStr(map['refresh_token']);
    userId = toStr(map['user_id'], fallback: toStr(map['sub']));
  }

  /// 完整登录流程，返回 null 表示成功
  Future<String?> signin(String username, String password) async {
    try {
      final sessionId = await coreLogin(username, password);
      await initCaptcha(username);
      await signinWithSession(sessionId);
      return null;
    } on XunleiException catch (e) {
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

  /// 文件列表（自动翻页）
  Future<List<XunleiFile>> listFiles(String parentId,
      {int limit = 100}) async {
    final files = <XunleiFile>[];
    var pageToken = '';
    for (var page = 0; page < 100; page++) {
      final map = await _authGet('$_driveBase/files', params: {
        'space': '',
        '__type': 'drive',
        'refresh': true,
        '__sync': true,
        'parent_id': parentId,
        'page_token': pageToken,
        'with_audit': true,
        'limit': limit,
        'with': 'url',
        'thumbnail_size': 'SIZE_LARGE',
        'filters': jsonEncode({
          'phase': {'eq': 'PHASE_TYPE_COMPLETE'},
          'trashed': {'eq': false},
        }),
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
  Future<XunleiFile> getFileDetail(String id) async {
    final map = await _authGet('$_driveBase/files/$id', params: {
      '_magic': '2021',
      'space': '',
      'thumbnail_size': 'SIZE_LARGE',
      'with': 'url',
    });
    return XunleiFile.fromJson(map);
  }

  /// 批量获取直链（逐文件请求，失败项跳过）
  Future<Map<String, String>> getDownloadLinks(List<String> ids) async {
    final result = <String, String>{};
    for (final id in ids) {
      try {
        final f = await getFileDetail(id);
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
