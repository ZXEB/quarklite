import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'quark_models.dart';

class QuarkException implements Exception {
  final int code;
  final String message;

  QuarkException(this.code, this.message);

  @override
  String toString() => message;
}

class QuarkShareSession {
  final String pwdId;
  final String passcode;
  final String shareId;
  String stoken;

  QuarkShareSession({
    required this.pwdId,
    required this.passcode,
    required this.shareId,
    required this.stoken,
  });
}

class QuarkClient {
  static const driveApi = 'https://drive.quark.cn/1/clouddrive';
  static const drivePcApi = 'https://drive-pc.quark.cn/1/clouddrive';
  static const panApi = 'https://pan.quark.cn';

  static const uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const uaDesktopClient =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.56 Chrome/100.0.4896.160 Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch';

  final Dio _dio;
  String cookie = '';
  Timer? _refreshTimer;

  QuarkClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  bool get hasLogin => cookie.isNotEmpty;

  void setCookie(String c) {
    cookie = c.trim();
  }

  String get downloadCookieSnapshot => cookie;

  Future<Response<dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final headers = <String, dynamic>{
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'Referer': 'https://pan.quark.cn/',
      'User-Agent': userAgent ?? uaPc,
      if (cookie.isNotEmpty) 'Cookie': cookie,
      ...?extraHeaders,
    };
    final resp = await _dio.request(
      url,
      data: data,
      queryParameters: params,
      options: Options(
        method: method,
        headers: headers,
        validateStatus: (_) => true,
      ),
    );
    _mergeSetCookie(resp);
    return resp;
  }

  void _mergeSetCookie(Response<dynamic> resp) {
    final setCookies = resp.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return;
    final entries = <String, String>{};
    for (final raw in setCookies) {
      final seg = raw.split(';').first.trim();
      final eq = seg.indexOf('=');
      if (eq <= 0) continue;
      entries[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
    }
    if (entries.isEmpty) return;
    final kept = <String>[];
    for (final part in cookie.split(';')) {
      final k = part.trim().split('=').first;
      if (entries.containsKey(k)) continue;
      if (part.trim().isNotEmpty) kept.add(part.trim());
    }
    for (final e in entries.entries) {
      kept.add('${e.key}=${e.value}');
    }
    cookie = kept.join('; ');
  }

  Map<String, dynamic> _parseBody(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      return jsonDecode(body) as Map<String, dynamic>;
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }

  dynamic _check(Map<String, dynamic> body) {
    final code = toInt(body['code'], fallback: -1);
    if (code != 0) {
      throw QuarkException(code, body['message']?.toString() ?? '请求失败');
    }
    return body['data'];
  }

  Future<dynamic> _get(
    String url, {
    Map<String, dynamic>? params,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final resp = await _request('GET', url,
        params: params, userAgent: userAgent, extraHeaders: extraHeaders);
    final body = _parseBody(resp);
    return _check(body);
  }

  Future<dynamic> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
  }) async {
    final resp = await _request('POST', url,
        params: params, data: data, userAgent: userAgent);
    final body = _parseBody(resp);
    return _check(body);
  }

  // ---------------- session ----------------

  /// 刷新 __puus 会话 cookie（服务端仅在请求缺失 __puus 时重新下发，见 AList 实现）
  Future<void> refreshSession() async {
    if (cookie.isEmpty) return;
    final stripped = _removeCookieKey(cookie, '__puus');
    try {
      await _request('GET', '$driveApi/config', extraHeaders: {
        if (stripped.isNotEmpty) 'Cookie': stripped,
      });
    } catch (_) {
      // 忽略刷新失败，保持旧 cookie
    }
  }

  String _removeCookieKey(String c, String key) {
    final kept = <String>[];
    for (final part in c.split(';')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      if (t.split('=').first == key) continue;
      kept.add(t);
    }
    return kept.join('; ');
  }

  /// 每 100 分钟刷新一次会话，避免下载 403
  void startSessionRefresher() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 100), (_) {
      refreshSession();
    });
  }

  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // ---------------- account ----------------

  Future<QuarkUserInfo> getUserInfo() async {
    final resp = await _request('GET', '$panApi/account/info',
        params: {'fr': 'pc', 'platform': 'pc'});
    final body = _parseBody(resp);
    final data = body['data'];
    if (data is! Map) {
      throw QuarkException(
          toInt(body['code'], fallback: -1),
          body['message']?.toString() ?? '登录状态无效，请重新登录');
    }
    return QuarkUserInfo.fromJson({'data': data});
  }

  // ---------------- own drive ----------------

  /// 列出目录内容（自动翻页拉取全部）
  Future<List<QuarkFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    final files = <QuarkFile>[];
    var total = -1;
    while (total < 0 || files.length < total) {
      final resp = await _request('GET', '$driveApi/file/sort', params: {
        'pr': 'ucpro',
        'fr': 'pc',
        'uc_param_str': '',
        'pdir_fid': pdirFid,
        '_page': page,
        '_size': size,
        '_fetch_total': 1,
        '_fetch_sub_dirs': 0,
        '_sort': 'file_type:asc,updated_at:desc',
        'fetch_all_file': 1,
        'fetch_risk_file_name': 1,
      });
      final body = _parseBody(resp);
      final data = _check(body);
      if (data is! Map) break;
      final list = data['list'];
      if (list is! List) break;
      files.addAll(list
          .whereType<Map>()
          .map((e) => QuarkFile.fromJson(e.cast<String, dynamic>())));
      total = toInt(body['metadata']?['_total'], fallback: total);
      if (total < 0 && list.length < size) break;
      if (list.isEmpty) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  /// 全局搜索。scope: 0=全部(文件名), 2=内容搜索(照片 AI 识别)
  Future<List<QuarkFile>> searchFiles(String keyword,
      {int page = 1, int size = 50, int scope = 0}) async {
    final data = await _get('$driveApi/file/search', params: {
      'pr': 'ucpro',
      'fr': 'pc',
      'uc_param_str': '',
      'q': keyword,
      '_page': page,
      '_size': size,
      '_fetch_total': 1,
      '_sort': 'file_type:asc,updated_at:desc',
      '_is_hl': 1,
      if (scope > 0) 'scope': scope,
    });
    final list = data['list'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => QuarkFile.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 获取下载直链。返回 (下载信息列表, 请求时使用的 cookie 快照)
  Future<(List<QuarkDownloadInfo>, String)> getDownloadInfo(
      List<String> fids) async {
    final snapshot = downloadCookieSnapshot;
    dynamic data;
    try {
      data = await _post('$driveApi/file/download',
          params: {'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': ''},
          data: {'fids': fids});
    } on QuarkException catch (e) {
      if (e.code == 23018) {
        data = await _post('$driveApi/file/download',
            params: {'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': ''},
            data: {'fids': fids},
            userAgent: uaDesktopClient);
      } else {
        rethrow;
      }
    }
    final list = data;
    if (list is! List) return (<QuarkDownloadInfo>[], snapshot);
    return (
      list
          .whereType<Map>()
          .map((e) => QuarkDownloadInfo.fromJson(e.cast<String, dynamic>()))
          .toList(),
      snapshot
    );
  }

  // ---------------- share ----------------

  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      final path = uri.path;
      final idx = path.lastIndexOf('/s/');
      if (idx >= 0) {
        pwdId = path.substring(idx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['pwd_code'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  Future<QuarkShareSession> getShareToken(
      String pwdId, String passcode) async {
    final data = await _post('$driveApi/share/sharepage/token',
        params: {'pr': 'ucpro', 'fr': 'pc'},
        data: {'pwd_id': pwdId, 'passcode': passcode});
    final stoken = data['stoken']?.toString() ?? '';
    final shareId = data['share_id']?.toString() ?? pwdId;
    if (stoken.isEmpty) {
      throw QuarkException(-1, '分享链接已失效或提取码错误');
    }
    return QuarkShareSession(
        pwdId: pwdId, passcode: passcode, shareId: shareId, stoken: stoken);
  }

  Future<List<QuarkShareFile>> listShare(
      QuarkShareSession session, String pdirFid,
      {int page = 1, int size = 50}) async {
    final files = <QuarkShareFile>[];
    var total = -1;
    while (total < 0 || files.length < total) {
      final resp = await _request(
          'GET', '$driveApi/share/sharepage/detail',
          params: {
            'pr': 'ucpro',
            'fr': 'pc',
            'pwd_id': session.pwdId,
            'stoken': session.stoken,
            'pdir_fid': pdirFid,
            'force': 0,
            '_page': page,
            '_size': size,
            '_fetch_banner': 0,
            '_fetch_share': 0,
            '_fetch_total': 1,
            '_sort': 'file_type:asc,updated_at:desc',
            'ver': 2,
          });
      final body = _parseBody(resp);
      final data = _check(body);
      if (data is! Map) break;
      final list = data['list'];
      if (list is! List) break;
      files.addAll(list
          .whereType<Map>()
          .map((e) => QuarkShareFile.fromJson(e.cast<String, dynamic>())));
      total = toInt(body['metadata']?['_total'], fallback: total);
      if (total < 0 && list.length < size) break;
      if (list.isEmpty) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  /// 分享文件直链下载（接口失败时上层降级为转存）
  Future<List<QuarkDownloadInfo>> getShareDownloadInfo(
      QuarkShareSession session, List<String> fidList) async {
    final data = await _post('$driveApi/share/sharepage/download',
        params: {'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': ''},
        data: {
          'fid_list': fidList,
          'pwd_id': session.pwdId,
          'share_id': session.shareId,
          'passcode': session.passcode,
        });
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => QuarkDownloadInfo.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 转存分享文件到自己的网盘
  Future<void> saveShare(
    QuarkShareSession session,
    List<QuarkShareFile> files,
    String toPdirFid,
  ) async {
    final taskId = await _saveShareRequest(session, files, toPdirFid);
    if (taskId.isNotEmpty) {
      await _waitTask(taskId);
    }
  }

  Future<String> _saveShareRequest(
      QuarkShareSession session, List<QuarkShareFile> files, String toPdirFid) async {
    final data = await _post('$driveApi/share/sharepage/save',
        params: {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
          'app': 'clouddrive',
        },
        data: {
          'fid_list': files.map((f) => f.fid).toList(),
          'fid_token_list': files.map((f) => f.shareFidToken).toList(),
          'to_pdir_fid': toPdirFid,
          'pwd_id': session.pwdId,
          'stoken': session.stoken,
          'pdir_fid': '0',
          'scene': 'link',
        });
    if (data is Map && data['task_id'] != null) {
      return data['task_id'].toString();
    }
    return '';
  }

  Future<void> _waitTask(String taskId, {int maxRetry = 120}) async {
    for (var i = 0; i < maxRetry; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      try {
        final data = await _get('$driveApi/task', params: {
          'pr': 'ucpro',
          'fr': 'pc',
          'uc_param_str': '',
          'task_id': taskId,
          'retry_index': i,
        });
        final status = toInt(data['status'], fallback: -1);
        if (status == 2) return;
        if (status == 3) throw QuarkException(-1, '转存任务失败');
      } on QuarkException {
        rethrow;
      } catch (_) {
        // 网络抖动继续等待
      }
    }
    throw QuarkException(-1, '转存任务超时');
  }
}
