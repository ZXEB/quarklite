import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';

/// 123 网盘接口异常
class Netdisk123Exception implements Exception {
  final int code;
  final String message;

  Netdisk123Exception(this.code, this.message);

  @override
  String toString() => message;
}

/// 123 网盘账号容量信息（/b/api/user/info 响应，未登录/未初始化时返回 0）
class Netdisk123Quota {
  /// 网盘总容量 / 已用容量（字节）
  final int totalSize;
  final int usedSize;

  const Netdisk123Quota({required this.totalSize, required this.usedSize});

  factory Netdisk123Quota.fromJson(Map<String, dynamic> json) {
    // 不同协议版本字段名不一，做多键兜底
    int pick(String key) {
      final v = json[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return Netdisk123Quota(
      totalSize: pick('total_size') != 0
          ? pick('total_size')
          : (pick('totalSize') != 0
              ? pick('totalSize')
              : pick('capacity')),
      usedSize: pick('used_size') != 0
          ? pick('used_size')
          : (pick('usedSize') != 0 ? pick('usedSize') : pick('usage')),
    );
  }

  bool get valid => totalSize > 0 && usedSize >= 0;
}

/// 123 网盘文件/文件夹
class Netdisk123File {
  final String id;
  final String name;
  final int size;
  final bool isDir;
  final String etag;
  final String s3KeyFlag;
  final String downloadUrl;

  const Netdisk123File({
    required this.id,
    required this.name,
    required this.size,
    required this.isDir,
    this.etag = '',
    this.s3KeyFlag = '',
    this.downloadUrl = '',
  });

  factory Netdisk123File.fromJson(Map<String, dynamic> json) {
    return Netdisk123File(
      id: toStr(json['FileId']),
      name: toStr(json['FileName']),
      size: toInt(json['Size']),
      isDir: toInt(json['Type']) == 1,
      etag: toStr(json['Etag']),
      s3KeyFlag: toStr(json['S3KeyFlag']),
      downloadUrl: toStr(json['DownloadUrl']),
    );
  }
}

/// 123 网盘月度下载流量状态（`POST file/download/traffic/check` 响应）
///
/// 实测（2026-10，免费账号）：服务端按「文件大小 vs 剩余额度」判定，
/// 文件大于剩余额度就整单拒绝（download_info 返回 5113），
/// 提示语「本月免费流量已用完」是误导，真实情况是这一单超额。
class Netdisk123Traffic {
  /// 是否被拦截
  final bool blocked;

  /// 是否超额
  final bool exceeded;

  /// 本次要下载的文件总大小（字节）
  final int fileSize;

  /// 账号剩余下载流量（字节）
  final int remain;

  /// 收银台场景标识：a/b/c/d 表示要弹付费框，e1 表示走 Scheme E
  final String cashierEnv;

  /// 服务端给的流量包档位（如 10GB / 20GB / 50GB）
  final String tier1;
  final String tier2;
  final String tier3;

  const Netdisk123Traffic({
    required this.blocked,
    required this.exceeded,
    required this.fileSize,
    required this.remain,
    this.cashierEnv = '',
    this.tier1 = '',
    this.tier2 = '',
    this.tier3 = '',
  });

  /// 还差多少字节才能下这一单
  int get shortage => fileSize > remain ? fileSize - remain : 0;

  factory Netdisk123Traffic.fromJson(Map<String, dynamic> json) {
    int pick(String k) {
      final v = json[k];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return Netdisk123Traffic(
      blocked: json['isBlocked'] == true,
      exceeded: json['isTrafficExceeded'] == true,
      fileSize: pick('originalFileSize'),
      remain: pick('originalRemainTraffic'),
      cashierEnv: toStr(json['cashierEnv']),
      tier1: toStr(json['desc1']),
      tier2: toStr(json['desc2']),
      tier3: toStr(json['desc3']),
    );
  }
}

/// 扫码登录客户端（新版 user.123pan.cn 流程）
///
/// 步骤：qr-code/generate → 轮询 qr-code/result → qr-code/wx_code → sign_in(type=4) 拿到 token。
class Netdisk123QrLogin {
  static const _base = 'https://user.123pan.cn/api/user';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  String _serverUniId = '';

  /// 64 位十六进制设备指纹（生成一次即可，随最终 sign_in 请求带 loginuuid）
  final String _deviceFingerprint = _randomHex(64);

  static String _randomHex(int n) {
    final r = Random.secure();
    final b = List<int>.generate(n, (_) => r.nextInt(16));
    return b.map((x) => x.toRadixString(16)).join();
  }

  static String _uuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
        '-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Map<String, dynamic> _headers() => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
        'Origin': 'https://user.123pan.cn',
        'Referer': 'https://user.123pan.cn/',
        'platform': 'web',
        'app-version': '132',
        'loginuuid': _deviceFingerprint,
      };

  /// 获取二维码，返回 (二维码内容, 服务器 uniID)
  Future<String> fetchQrUrl() async {
    final uniId = _uuid();
    final resp = await _dio.get<dynamic>('$_base/qr-code/generate',
        queryParameters: {'uniID': uniId},
        options: Options(headers: _headers(), validateStatus: (_) => true));
    final data = _data(resp);
    final url = toStr(data['url']);
    final serverUniId = toStr(data['uniID']);
    if (url.isEmpty || serverUniId.isEmpty) {
      throw Exception('获取登录二维码失败: ${_message(resp)}');
    }
    _serverUniId = serverUniId;
    return '$url?uniID=$serverUniId&env=production';
  }

  /// 轮询扫码结果：返回 0 等待 / 1 已扫 / 2 确认 / 3 过期 / 4 无会话
  Future<int> pollStatus() async {
    if (_serverUniId.isEmpty) throw Exception('请先获取二维码');
    final resp = await _dio.get<dynamic>('$_base/qr-code/result',
        queryParameters: {
          'uniID': _serverUniId,
          'remember': 'true',
          'gray': 'true',
        },
        options: Options(headers: _headers(), validateStatus: (_) => true));
    if (resp.statusCode == 401) return 3; // 过期
    final data = _data(resp);
    return toInt(data['loginStatus'], fallback: 0);
  }

  /// 扫码确认后换取 code，再完成登录，返回 token
  Future<String> login() async {
    if (_serverUniId.isEmpty) throw Exception('请先获取二维码');
    var resp = await _dio.post<dynamic>('$_base/qr-code/wx_code',
        data: {'uniID': _serverUniId},
        options: Options(headers: _headers(), validateStatus: (_) => true));
    final wxCode = toStr(_data(resp)['wxCode']);
    if (wxCode.isEmpty) {
      throw Exception('换取登录凭证失败: ${_message(resp)}');
    }
    resp = await _dio.post<dynamic>('$_base/sign_in',
        data: {
          'from': 'web',
          'wechat_code': wxCode,
          'type': 4,
          'remember': true,
          'gray': true,
        },
        options: Options(headers: _headers(), validateStatus: (_) => true));
    final token = toStr(_data(resp)['token']);
    if (token.isEmpty) {
      throw Exception('登录失败: ${_message(resp)}');
    }
    return token;
  }

  Map<String, dynamic> _data(Response<dynamic> resp) {
    final map = _decode(resp);
    final data = map['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  dynamic _message(Response<dynamic> resp) {
    final map = _decode(resp);
    return map['message'] ?? map['msg'] ?? '未知错误';
  }

  Map<String, dynamic> _decode(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }
}

/// 123 网盘客户端。
///
/// 下载链路已按 123pan_3242.apk + 网页端 app.js 的逆向结论重写：
///
/// 月度流量限制的判定完全在**客户端**——前端先单独请求
/// `POST /b/api/file/download/traffic/check`（body `{fids:[...]}`），
/// 拿返回的 `cashierEnv`：落在 {a,b,c,d} 就弹付费框，否则直接
/// `continueDownload` 去取下载地址。取地址的接口和流量校验是两条独立通道，
/// 并且官方前端对 `selfDownload/info` / `shareDownload/info` 显式传了
/// `suppressDownloadGate: true`（跳过下载门禁拦截器）。
///
/// 所以这里**不再调用 traffic/check**，直接按通道顺序取直链；
/// traffic/check 仅保留为诊断接口（[trafficCheck]），不参与任何判定。
class Netdisk123Client {
  /// 现网主接口域名（网页/PC 客户端同源，来自前端 hosts 表 prod.interface）
  static const _apiBase = 'https://api.123278.com/b/api';

  /// 老域名兜底（alist 一直在用，仍可用）
  static const _apiBaseLegacy = 'https://yun.123pan.com/b/api';

  static const _loginBase = 'https://login.123pan.com/api';

  /// 根目录 parentFileId / driveId（alist 现行硬编码 0）
  static const rootParentId = '0';

  /// 平台与版本（随每个 API 请求）
  static const platform = 'web';
  static const appVersion = '3';

  /// 请求 UA（与下载直链一致，无特殊档位 UA）
  static const ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)';

  /// signPath 用 26 字符替换表（translated from alist）
  static const _table = 'adefghlmyijnopkqrstubcvwsz';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String token = '';
  String username = '';

  /// 记住的密码（仅本机，用于 token 过期后自动重登）
  String _password = '';

  /// 仅供 state 层持久化使用
  String get passwordSnapshot => _password;

  bool get hasLogin => token.isNotEmpty;

  void setToken(String t) {
    token = t.trim();
  }

  void setCredentials(String user, String password) {
    username = user;
    _password = password;
  }

  void clear() {
    token = '';
    username = '';
    _password = '';
  }

  // ---------------- 工具 ----------------

  static String _crc32(String s) {
    var crc = 0xFFFFFFFF & 0xFFFFFFFF;
    for (final byte in utf8.encode(s)) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ (((crc & 1) != 0) ? 0xEDB88320 : 0);
      }
    }
    return (crc ^ 0xFFFFFFFF).toUnsigned(32).toString();
  }

  /// signPath：生成 (key=timeSign, value=timestamp-random-dataSign)
  ///
  /// 逆向自前端模块 38823：key 是"日期数字按字母表替换"后的串，
  /// value 是 `crc32("ts|rand|path|platform|appVersion|key")`。
  /// 实测服务端并未强制校验，带上只为与官方请求同构。
  static (String, String) _signPath(String path) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8)); // CST
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    final random = (1e7 * Random().nextDouble()).round().toString();
    String two(int n) => n.toString().padLeft(2, '0');
    final nowStr = '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}';
    final nowMapped =
        nowStr.split('').map((c) => _table[c.codeUnitAt(0) - 48]).join();
    final timeSign = _crc32(nowMapped);
    final data = '$timestamp|$random|$path|$platform|$appVersion|$timeSign';
    final dataSign = _crc32(data);
    return (timeSign, '$timestamp-$random-$dataSign');
  }

  /// 给 API URL 附加签名查询参数
  String _signUrl(String url) {
    final uri = Uri.parse(url);
    final (key, value) = _signPath(uri.path);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      key: value,
    }).toString();
  }

  Map<String, dynamic> _apiHeaders() => {
        'accept': 'application/json, text/plain, */*',
        'origin': 'https://www.123pan.com',
        'referer': 'https://www.123pan.com/',
        'user-agent': ua,
        'platform': platform,
        'app-version': appVersion,
        if (token.isNotEmpty) 'authorization': 'Bearer $token',
      };

  // ---------------- 认证 ----------------

  /// 密码登录，返回 null 表示成功
  Future<String?> signIn(String account, String password) async {
    final isEmail = account.contains('@');
    final body = isEmail
        ? {'mail': account, 'password': password, 'type': 2}
        : {'passport': account, 'password': password, 'remember': true};
    try {
      final resp = await _dio.post<dynamic>('$_loginBase/user/sign_in',
          data: body,
          options: Options(
              headers: {
                'origin': 'https://www.123pan.com',
                'referer': 'https://www.123pan.com/',
                'platform': platform,
                'app-version': appVersion,
                'user-agent': ua,
              },
              validateStatus: (_) => true));
      final map = _decode(resp);
      final code = toInt(map['code'], fallback: -1);
      if (code != 200 && code != 0) {
        return toStr(map['message'], fallback: '登录失败');
      }
      final t = toStr((map['data'] is Map)
          ? (map['data'] as Map)['token']
          : map['data']);
      if (t.isEmpty) return '登录失败: 未获取到 token';
      token = t;
      username = account;
      _password = password;
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// 流量包充值页（0.5 元档，内置 WebView）。仅在四条下载通道都被服务端
  /// 明确拒绝（code 5113）时才需要——正常情况下走不到这里。
  static const kPayUrl = 'https://www.123pan.com/buy/traffic';

  Future<Map<String, dynamic>> fetchUserInfo() async {
    return _get('$_apiBase/user/info');
  }

  /// 拉取账号容量信息（total_size / used_size）
  Future<Netdisk123Quota> fetchQuota() async {
    final map = await _get('$_apiBase/user/info');
    return Netdisk123Quota.fromJson(map);
  }

  /// 校验 token 是否仍有效（失败时抛出异常，由调用方决定是否重登）
  Future<bool> validate() async {
    if (token.isEmpty) return false;
    try {
      await _get('$_apiBase/user/info');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 通用 GET（带签名 + token 过期自动重登重试），返回 data
  Future<Map<String, dynamic>> _get(String url,
      {Map<String, dynamic>? params}) async {
    return _request('GET', url, null, params: params);
  }

  Future<Map<String, dynamic>> _request(String method, String url, Object? body,
      {Map<String, dynamic>? params}) async {
    final signed = _signUrl(url);
    var resp = await _dio.request<dynamic>(signed,
        data: body,
        queryParameters: params,
        options: Options(
            method: method,
            headers: _apiHeaders(),
            validateStatus: (_) => true));
    var map = _decode(resp);
    var code = toInt(map['code'], fallback: -1);
    // token 过期(401)：若有记住的密码则自动重登并重试一次
    if (code == 401 && _password.isNotEmpty) {
      AppLogger.I.w('netdisk123', 'token 失效，尝试自动重登');
      final err = await signIn(username, _password);
      if (err == null) {
        resp = await _dio.request<dynamic>(signed,
            data: body,
            queryParameters: params,
            options: Options(
                method: method,
                headers: _apiHeaders(),
                validateStatus: (_) => true));
        map = _decode(resp);
        code = toInt(map['code'], fallback: -1);
      }
    }
    if (code != 0) {
      throw Netdisk123Exception(code, toStr(map['message'], fallback: '请求失败'));
    }
    final data = map['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  // ---------------- 云盘 ----------------

  /// 文件列表（自动翻页，Next == "-1" 结束）
  Future<List<Netdisk123File>> listFiles(String parentId) async {
    final files = <Netdisk123File>[];
    var page = 1;
    for (var i = 0; i < 100; i++) {
      final map = await _get('$_apiBase/file/list/new',
          params: {
            'driveId': '0',
            'limit': '100',
            'next': '0',
            'orderBy': 'file_id',
            'orderDirection': 'desc',
            'parentFileId': parentId,
            'trashed': 'false',
            'SearchData': '',
            'Page': '$page',
            'OnlyLookAbnormalFile': '0',
            'event': 'homeListFile',
            'operateType': '4',
            'inDirectSpace': 'false',
          });
      final list = map['InfoList'];
      if (list is List) {
        for (final item in list.whereType<Map>()) {
          files.add(Netdisk123File.fromJson(item.cast<String, dynamic>()));
        }
      }
      final next = toStr(map['Next']);
      page++;
      if (next == '-1' || (list is List && list.isEmpty)) break;
    }
    return files;
  }

  // ---------------- 下载（多通道回退，不经过客户端流量门禁） ----------------

  /// 诊断用：查询本月剩余流量 / 门禁状态。
  ///
  /// **不参与下载判定**——失败、超限都不影响 [getDownloadUrl]。
  /// 返回值里的 `cashierEnv` 落在 {a,b,c,d} 只是官方前端弹付费框的依据。
  Future<Map<String, dynamic>> trafficCheck(List<String> fileIds) async {
    try {
      return await _apiPostRaw(
          '$_apiBase/file/download/traffic/check',
          {
            'fids':
                fileIds.map((e) => int.tryParse(e)).whereType<int>().toList()
          });
    } catch (e) {
      AppLogger.I.w('netdisk123', 'traffic/check 失败(忽略): $e');
      return const <String, dynamic>{};
    }
  }

  /// 结构化流量状态：文件大小、剩余额度、差额、档位
  Future<Netdisk123Traffic?> checkTraffic(List<String> fileIds) async {
    try {
      final map = await _apiPostRaw(
          '$_apiBase/file/download/traffic/check',
          {
            'fids':
                fileIds.map((e) => int.tryParse(e)).whereType<int>().toList()
          });
      return Netdisk123Traffic.fromJson(map);
    } catch (e) {
      AppLogger.I.w('netdisk123', 'traffic/check 失败(忽略): $e');
      return null;
    }
  }

  /// 直链流量额度（与网页月度下载流量是两条独立的账）
  Future<Map<String, dynamic>> directLinkTraffic() async {
    return _apiPostRaw(
        '$_apiBase/restful/goapi/v1/directLink/traffic/limit', {});
  }

  /// 获取文件下载直链：四通道依次回退，第一个拿到 URL 的即返回。
  ///
  /// 1. `v2/file/download_info`        —— 网页端主通道
  /// 2. `restful/goapi/v1/file/selfDownload/info` —— 官方前端带
  ///    suppressDownloadGate 的通道
  /// 3. `file/download_info`(android)  —— 老协议，命中 APP 免费额度
  /// 4. `v2/file/batch_download_info`  —— 批量通道
  Future<String> getDownloadUrl(Netdisk123File f) async {
    final body = {
      'driveId': 0,
      'etag': f.etag,
      'fileId': f.id,
      's3keyFlag': f.s3KeyFlag,
      'type': f.isDir ? 1 : 0,
      'fileName': f.name,
      'size': f.size,
    };

    final channels = <String, Future<Map<String, dynamic>> Function()>{
      'v2/download_info': () =>
          _apiPostRaw('$_apiBase/v2/file/download_info', body),
      'selfDownload/info': () => _apiPostRaw(
          '$_apiBase/restful/goapi/v1/file/selfDownload/info', body),
      'download_info(android)': () =>
          _apiPostRaw('$_apiBase/file/download_info', body, platform: 'android'),
      'batch_download_info': () => _apiPostRaw(
          '$_apiBase/v2/file/batch_download_info',
          {
            'fileIdList': [
              {'fileId': int.tryParse(f.id) ?? f.id}
            ]
          }),
    };

    Netdisk123Exception? trafficError;
    Object? lastError;
    for (final entry in channels.entries) {
      try {
        final map = await entry.value();
        final url = _extractUrl(map);
        if (url.isNotEmpty) {
          AppLogger.I.i('netdisk123', '直链命中通道 ${entry.key}: ${f.name}');
          return url;
        }
        AppLogger.I.w('netdisk123', '通道 ${entry.key} 未返回直链');
      } catch (e) {
        lastError = e;
        if (e is Netdisk123Exception && e.code == 5113) trafficError ??= e;
        AppLogger.I.w('netdisk123', '通道 ${entry.key} 失败: $e');
      }
    }
    // 四条通道全挂：优先抛"流量不足"，让上层弹充值页
    if (trafficError != null) throw trafficError;
    if (lastError != null) throw lastError;
    return '';
  }

  /// 从各种 download_info 响应里挖出直链
  ///
  /// 两条通道的返回结构不同：
  ///  * `file/download_info`  → `DownloadUrl`（web-pro2 中转，base64 包一层）
  ///  * `v2/file/download_info` → `downloadPath`（相对路径）+ `dispatchList`
  ///    里的 `prefix`，两者拼接才是真实 CDN 地址
  String _extractUrl(Map<String, dynamic> map) {
    for (final key in const [
      'DownloadUrl',
      'downloadUrl',
      'Url',
      'url',
      'RedirectUrl',
    ]) {
      final v = toStr(map[key]);
      if (v.isNotEmpty) return _unwrap(v);
    }

    // v2 通道：downloadPath 是相对路径，需要拼 dispatchList 的 prefix
    final path = toStr(map['downloadPath']);
    if (path.isNotEmpty) {
      if (path.startsWith('http')) return path;
      final prefix = _firstPrefix(map);
      if (prefix.isNotEmpty) return '$prefix$path';
    }

    final list = map['InfoList'] ?? map['list'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) return _extractUrl(first.cast<String, dynamic>());
    }
    return '';
  }

  String _firstPrefix(Map<String, dynamic> map) {
    final list = map['dispatchList'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) return toStr(first['prefix']);
    }
    return '';
  }

  /// web-pro2 中转直链带 `params=base64` 载荷，解出真实 CDN 地址
  String _unwrap(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final params = uri.queryParameters['params'];
      if (params != null && params.isNotEmpty) {
        final decoded =
            utf8.decode(base64Url.decode(base64Url.normalize(params)));
        if (Uri.parse(decoded).host.isNotEmpty) return decoded;
      }
    } catch (_) {
      // 解码失败则用原始 URL
    }
    return rawUrl;
  }

  /// 带平台覆盖的 POST（返回 data）。platform 覆盖默认为 web 的 _apiHeaders。
  Future<Map<String, dynamic>> _apiPostRaw(String url, Object body,
      {String? platform}) async {
    final signed = _signUrl(url);
    var resp = await _dio.request<dynamic>(signed,
        data: body,
        options: Options(
            method: 'POST',
            headers: _androidHeaders(platform),
            validateStatus: (_) => true));
    var map = _decode(resp);
    var code = toInt(map['code'], fallback: -1);
    if (code == 401 && _password.isNotEmpty) {
      AppLogger.I.w('netdisk123', 'token 失效，尝试自动重登');
      final err = await signIn(username, _password);
      if (err == null) {
        resp = await _dio.request<dynamic>(signed,
            data: body,
            options: Options(
                method: 'POST',
                headers: _androidHeaders(platform),
                validateStatus: (_) => true));
        map = _decode(resp);
        code = toInt(map['code'], fallback: -1);
      }
    }
    if (code != 0) {
      throw Netdisk123Exception(code, toStr(map['message'], fallback: '请求失败'));
    }
    final data = map['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// 用于 download_info 的请求头。platform='android' 时模拟安卓协议命中 APP 免费额度。
  Map<String, dynamic> _androidHeaders(String? platform) {
    final isAndroid = platform == 'android';
    return {
      'accept': 'application/json, text/plain, */*',
      'origin': 'https://www.123pan.com',
      'referer': 'https://www.123pan.com/',
      'user-agent': isAndroid ? '123pan/v2.4.0(Android_11;Xiaomi)' : ua,
      'platform': platform ?? Netdisk123Client.platform,
      if (isAndroid) 'devicetype': 'M2007J20CI',
      if (isAndroid) 'devicename': 'Xiaomi',
      if (isAndroid) 'osversion': 'Android_11',
      if (isAndroid) 'app-version': '61',
      if (isAndroid) 'x-app-version': '2.4.0',
      if (!isAndroid) 'app-version': appVersion,
      if (token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  // ---------------- 通道诊断 ----------------

  /// 原始请求：不抛业务异常，原样返回解码后的响应体
  Future<Map<String, dynamic>> rawRequest(String method, String path,
      {Object? body, Map<String, dynamic>? params, String? platform}) async {
    final url = '$_apiBase/$path';
    final signed = _signUrl(url);
    final resp = await _dio.request<dynamic>(signed,
        data: body,
        queryParameters: params,
        options: Options(
            method: method,
            headers: _androidHeaders(platform),
            validateStatus: (_) => true));
    return _decode(resp);
  }

  /// 把每条可能取到直链的通道都打一遍，用于定位服务端到底在哪一步拦。
  ///
  /// 返回每项：name / code / message / hasUrl / urlHost / ms
  Future<List<Map<String, dynamic>>> diagnose(Netdisk123File f) async {
    final body = <String, dynamic>{
      'driveId': 0,
      'etag': f.etag,
      'fileId': f.id,
      's3keyFlag': f.s3KeyFlag,
      'type': f.isDir ? 1 : 0,
      'fileName': f.name,
      'size': f.size,
    };
    final fid = int.tryParse(f.id) ?? 0;
    final probes = <Map<String, dynamic>>[
      {'name': 'user/info', 'method': 'GET', 'path': 'user/info'},
      {
        'name': 'traffic/check',
        'method': 'POST',
        'path': 'file/download/traffic/check',
        'body': {
          'fids': [fid]
        }
      },
      {
        'name': 'download_info(web)',
        'method': 'POST',
        'path': 'file/download_info',
        'body': body
      },
      {
        'name': 'download_info(android)',
        'method': 'POST',
        'path': 'file/download_info',
        'body': body,
        'platform': 'android'
      },
      {
        'name': 'v2/download_info',
        'method': 'POST',
        'path': 'v2/file/download_info',
        'body': body
      },
      {
        'name': 'batch_download_info',
        'method': 'POST',
        'path': 'v2/file/batch_download_info',
        'body': {
          'fileIdList': [
            {'fileId': fid}
          ]
        }
      },
      {
        'name': 'selfDownload/info',
        'method': 'POST',
        'path': 'restful/goapi/v1/file/selfDownload/info',
        'body': body
      },
      {
        'name': 'directLink/traffic',
        'method': 'POST',
        'path': 'restful/goapi/v1/directLink/traffic/limit',
        'body': <String, dynamic>{}
      },
      {
        'name': 'cdnLink/links',
        'method': 'POST',
        'path': 'restful/goapi/v1/cdnLink/links',
        'body': <String, dynamic>{}
      },
      {
        'name': 'webdav',
        'method': 'GET',
        'path': 'restful/goapi/v1/webdav'
      },
      {
        'name': 'file/belong/info',
        'method': 'POST',
        'path': 'restful/goapi/v1/file/belong/info',
        'body': body
      },
      {'name': '3rd/app-id', 'method': 'GET', 'path': 'v3/3rd/app-id'},
    ];

    final out = <Map<String, dynamic>>[];
    for (final p in probes) {
      final sw = Stopwatch()..start();
      try {
        final map = await rawRequest(
          p['method'] as String,
          p['path'] as String,
          body: p['body'],
          platform: p['platform'] as String?,
        );
        final url = _extractUrl(map);
        out.add({
          'name': p['name'],
          'code': toInt(map['code'], fallback: -1),
          'message': toStr(map['message']),
          'hasUrl': url.isNotEmpty,
          'urlHost': url.isEmpty ? '' : (Uri.tryParse(url)?.host ?? ''),
          'ms': sw.elapsedMilliseconds,
        });
      } catch (e) {
        out.add({
          'name': p['name'],
          'code': -999,
          'message': e.toString(),
          'hasUrl': false,
          'urlHost': '',
          'ms': sw.elapsedMilliseconds,
        });
      }
    }
    return out;
  }

  Map<String, dynamic> _decode(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }
}

/// 123 网盘**分享**解析（免登录）。
///
/// 实测：`GET /b/api/share/download-list?uniID=...` 在完全没有 token 的情况下
/// 返回的是业务错误（"分享不存在"），而不是 `20101 未登录` —— 说明分享通道
/// 本身不需要登录，只要拿到有效的 uniID（分享 ID）+ 提取码即可。
///
/// 注意：这只适用于**别人分享出来的链接**。自己网盘里的文件必须带 token，
/// 因为 list/new 与 download_info 都会校验账号归属。
class Netdisk123Share {
  static const _apiBase = 'https://api.123278.com/b/api';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Map<String, dynamic> _headers() => {
        'accept': 'application/json, text/plain, */*',
        'origin': 'https://www.123pan.com',
        'referer': 'https://www.123pan.com/',
        'user-agent': Netdisk123Client.ua,
        'platform': Netdisk123Client.platform,
        'app-version': Netdisk123Client.appVersion,
      };

  /// 从分享链接里取 uniID。
  /// 支持 `https://www.123pan.com/s/abc-def`、`https://www.123pan.cn/s/abc-def`
  /// 以及直接给 `abc-def` 的情况。
  static String parseUniId(String url) {
    final s = url.trim();
    final m = RegExp(r'/s/([A-Za-z0-9_\-]+)').firstMatch(s);
    if (m != null) return m.group(1)!;
    final m2 = RegExp(r'^([A-Za-z0-9]{3,}-[A-Za-z0-9]{2,})$').firstMatch(s);
    return m2?.group(1) ?? '';
  }

  /// 从分享链接里取提取码：`?pwd=abcd` / `&pwd=abcd`
  static String parsePwd(String url) {
    final m = RegExp(r'[?&]pwd=([A-Za-z0-9]+)').firstMatch(url);
    return m?.group(1) ?? '';
  }

  /// 列出分享内容（无需登录）
  Future<List<Netdisk123File>> list(String uniId,
      {String pwd = '', String parentId = '0'}) async {
    final files = <Netdisk123File>[];
    for (var page = 1; page <= 50; page++) {
      final params = <String, dynamic>{
        'limit': '100',
        'next': '0',
        'orderBy': 'file_name',
        'orderDirection': 'asc',
        'parentFileId': parentId,
        'trashed': 'false',
        'SearchData': '',
        'Page': '$page',
        'OnlyLookAbnormalFile': '0',
        'uniID': uniId,
        if (pwd.isNotEmpty) 'passcode': pwd,
      };
      final resp = await _dio.get<dynamic>('$_apiBase/share/download-list',
          queryParameters: params,
          options: Options(headers: _headers(), validateStatus: (_) => true));
      final map = _decode(resp);
      final code = toInt(map['code'], fallback: -1);
      if (code != 0) {
        throw Netdisk123Exception(
            code, toStr(map['message'], fallback: '分享解析失败'));
      }
      final data = map['data'];
      final inner = data is Map ? data.cast<String, dynamic>() : map;
      final infoList = inner['InfoList'];
      if (infoList is List) {
        for (final item in infoList.whereType<Map>()) {
          files.add(Netdisk123File.fromJson(item.cast<String, dynamic>()));
        }
      }
      final next = toStr(inner['Next']);
      if (next == '-1' || infoList is! List || infoList.isEmpty) break;
    }
    return files;
  }

  /// 分享文件直链。优先用列表里带的 DownloadUrl，否则请求 shareDownload/info。
  Future<String> getDownloadUrl(Netdisk123File f, String uniId,
      {String pwd = ''}) async {
    if (f.downloadUrl.isNotEmpty) return f.downloadUrl;

    final body = <String, dynamic>{
      'driveId': 0,
      'etag': f.etag,
      'fileId': f.id,
      's3keyFlag': f.s3KeyFlag,
      'type': f.isDir ? 1 : 0,
      'fileName': f.name,
      'size': f.size,
      'shareKey': uniId,
      if (pwd.isNotEmpty) 'sharePwd': pwd,
    };

    for (final path in const [
      'restful/goapi/v1/file/shareDownload/info',
      'file/download_info',
    ]) {
      try {
        final resp = await _dio.post<dynamic>('$_apiBase/$path',
            data: body,
            options: Options(headers: _headers(), validateStatus: (_) => true));
        final map = _decode(resp);
        if (toInt(map['code'], fallback: -1) != 0) {
          AppLogger.I.w('netdisk123',
              'share $path 失败: ${toStr(map['message'])}');
          continue;
        }
        final data = map['data'];
        final inner = data is Map ? data.cast<String, dynamic>() : map;
        final url = toStr(inner['DownloadUrl']).isNotEmpty
            ? toStr(inner['DownloadUrl'])
            : toStr(inner['downloadUrl']);
        if (url.isNotEmpty) return url;
      } catch (e) {
        AppLogger.I.w('netdisk123', 'share $path 异常: $e');
      }
    }
    return '';
  }

  Map<String, dynamic> _decode(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }
}
