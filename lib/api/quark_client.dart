import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  /// 官方分类接口：按分类分页拉取（相册数据源）。
  /// [labels] 为 AI 识别标签（仅对已被夸克 AI 打标的照片生效）
  Future<List<QuarkFile>> listCategory(String cat,
      {int page = 1, int size = 100, String labels = ''}) async {
    final data = await _get('$drivePcApi/file/category', params: {
      'pr': 'ucpro',
      'fr': 'pc',
      'cat': cat,
      '_page': page,
      '_size': size,
      '_fetch_total': 1,
      if (labels.isNotEmpty) 'labels': labels,
    });
    final list = data['list'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => QuarkFile.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<QuarkFile>> listCategoryImages(
          {int page = 1, int size = 100, String labels = ''}) =>
      listCategory('image', page: page, size: size, labels: labels);

  Future<List<QuarkFile>> listCategoryVideos(
          {int page = 1, int size = 100}) =>
      listCategory('video', page: page, size: size);

  /// 获取下载直链。返回 (下载信息列表, 请求时使用的 cookie 快照)
  /// 使用桌面客户端 UA 请求并绑定签名（网页 UA 易触发限速）
  Future<(List<QuarkDownloadInfo>, String)> getDownloadInfo(
      List<String> fids) async {
    final snapshot = downloadCookieSnapshot;
    dynamic data;
    try {
      data = await _post('$driveApi/file/download',
          params: {'pr': 'ucpro', 'fr': 'pc', 'uc_param_str': ''},
          data: {'fids': fids},
          userAgent: uaDesktopClient);
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

  /// 获取视频转码清晰度列表（社区逆向的 video_preview 接口，在线播放多清晰度用）。
  /// 返回 (清晰度列表按高到低, 请求时 cookie 快照)；任一异常返回空列表，
  /// 调用方回落「仅原画」。转码 CDN 与下载 CDN 限速策略不同，通常更流畅。
  Future<(List<QuarkVideoQuality>, String)> getVideoPreview(String fid) async {
    const params = {'pr': 'ucpro', 'fr': 'pc'};
    List? list;
    try {
      dynamic data = await _post('$driveApi/file/video_preview',
          params: params,
          data: {
            'fids': [fid]
          },
          userAgent: uaDesktopClient);
      list = _extractVideoList(data);
      if (list == null) {
        // 部分实现使用 {"fid": ...} 请求体
        data = await _post('$driveApi/file/video_preview',
            params: params,
            data: {'fid': fid},
            userAgent: uaDesktopClient);
        list = _extractVideoList(data);
      }
    } catch (_) {
      return (const <QuarkVideoQuality>[], downloadCookieSnapshot);
    }
    final snapshot = downloadCookieSnapshot;
    if (list == null) return (const <QuarkVideoQuality>[], snapshot);
    final qualities = <QuarkVideoQuality>[];
    for (final e in list.whereType<Map>()) {
      final url = (e['url'] ?? e['video_url'] ?? '').toString();
      if (url.isEmpty) continue;
      var label = (e['resolution'] ?? e['quality'] ?? '').toString().trim();
      if (label.isEmpty) {
        final vi = e['video_info'];
        if (vi is Map && vi['height'] != null) label = '${vi['height']}P';
      }
      if (label.isEmpty) label = '转码';
      qualities.add(QuarkVideoQuality(label: label, url: url));
    }
    qualities.sort((a, b) => _qualityRank(b).compareTo(_qualityRank(a)));
    final seen = <String>{};
    return (
      qualities.where((q) => seen.add(q.label)).toList(),
      snapshot
    );
  }

  static List? _extractVideoList(dynamic data) {
    if (data is Map) {
      final v = data['video_list'] ?? data['video_lists'];
      if (v is List) return v;
      return null;
    }
    if (data is List) return data;
    return null;
  }

  static int _qualityRank(QuarkVideoQuality q) {
    final m = RegExp(r'(\d{3,4})').firstMatch(q.label);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    const named = {
      '4K': 2160,
      '2K': 1440,
      '蓝光': 1080,
      '超清': 720,
      '高清': 540,
      '标清': 360,
      '流畅': 240,
    };
    return named[q.label] ?? 0;
  }

  // ---------------- upload ----------------
  // 上传协议对齐 alist quark_uc 驱动 + QuarkPan / idv-login 等社区实现：
  // upload/pre 预申请 → update/hash 秒传校验 → upload/auth 取 OSS 签名 →
  // 直传 OSS 分片（PUT）→ 合并（POST CompleteMultipartUpload）→ upload/finish。

  static const _ucParams = {'pr': 'ucpro', 'fr': 'pc'};
  static const _ossUserAgent =
      'aliyun-sdk-js/6.6.1 Chrome 98.0.4758.80 on Windows 10 64-bit';

  /// 创建文件夹，返回新文件夹 fid。
  /// 同名已存在等错误时回退：列出父目录复用同名文件夹。
  Future<String> createFolder(String pdirFid, String fileName) async {
    try {
      final data = await _post('$driveApi/file',
          params: _ucParams,
          data: {
            'dir_init_lock': false,
            'dir_path': '',
            'file_name': fileName,
            'pdir_fid': pdirFid,
          });
      final fid = data is Map ? (data['fid']?.toString() ?? '') : '';
      if (fid.isNotEmpty) return fid;
    } on QuarkException {
      // 同名冲突等错误：走回退查找
    }
    final files = await listFiles(pdirFid);
    for (final f in files) {
      if (f.isDir && f.fileName == fileName) return f.fid;
    }
    throw QuarkException(-1, '创建文件夹失败: $fileName');
  }

  // ---------------- manage ----------------

  /// 批量删除文件/文件夹（移入回收站）
  Future<void> deleteFiles(List<String> fids) async {
    if (fids.isEmpty) return;
    await _post('$driveApi/file/delete',
        params: _ucParams,
        data: {'action_type': 1, 'exclude_fids': <String>[], 'filelist': fids});
  }

  /// 批量移动到指定目录（根目录 fid 为 '0'）
  Future<void> moveFiles(List<String> fids, String toPdirFid) async {
    if (fids.isEmpty) return;
    await _post('$driveApi/file/move',
        params: _ucParams,
        data: {
          'action_type': 1,
          'exclude_fids': <String>[],
          'filelist': fids,
          'to_pdir_fid': toPdirFid,
        });
  }

  /// 重命名文件/文件夹
  Future<void> renameFile(String fid, String newName) async {
    await _post('$driveApi/file/rename',
        params: _ucParams, data: {'fid': fid, 'file_name': newName});
  }

  /// 上传预申请：返回 OSS 分片上传会话（含秒传标记）
  Future<QuarkUploadSession> uploadPre({
    required String pdirFid,
    required String fileName,
    required int size,
    required String mime,
    required int createdAt,
    required int updatedAt,
  }) async {
    final resp = await _request('POST', '$driveApi/file/upload/pre',
        params: _ucParams,
        data: {
          'ccp_hash_update': true,
          'dir_name': '',
          'file_name': fileName,
          'format_type': mime,
          'l_created_at': createdAt,
          'l_updated_at': updatedAt,
          'pdir_fid': pdirFid,
          'size': size,
        });
    final body = _parseBody(resp);
    _check(body);
    return QuarkUploadSession.fromJson(body);
  }

  /// 秒传校验：文件哈希命中服务端已有文件时返回 true（无需分片上传）
  Future<bool> uploadHash({
    required String md5,
    required String sha1,
    required String taskId,
  }) async {
    final data = await _post('$driveApi/file/update/hash',
        params: _ucParams,
        data: {'md5': md5, 'sha1': sha1, 'task_id': taskId});
    return data is Map && data['finish'] == true;
  }

  /// 获取 OSS 直传授权（auth_meta 为 OSS V1 签名串，需与直传请求头完全一致）
  Future<String> uploadAuth({
    required String authInfo,
    required String authMeta,
    required String taskId,
  }) async {
    final data = await _post('$driveApi/file/upload/auth',
        params: _ucParams,
        data: {'auth_info': authInfo, 'auth_meta': authMeta, 'task_id': taskId});
    final key = data is Map ? (data['auth_key']?.toString() ?? '') : '';
    if (key.isEmpty) {
      throw QuarkException(-1, '获取上传授权失败');
    }
    return key;
  }

  /// 直传单个分片到 OSS（先取签名再 PUT，保证 auth_meta 与请求头同秒一致），
  /// 返回响应头 ETag（不带引号）
  Future<String> uploadPart({
    required QuarkUploadSession session,
    required int partNumber,
    required Uint8List bytes,
    required String mime,
    CancelToken? cancelToken,
  }) async {
    final timeStr = _httpDate();
    final authKey = await uploadAuth(
      authInfo: session.authInfo,
      authMeta: partAuthMeta(session, partNumber, mime, timeStr),
      taskId: session.taskId,
    );
    return uploadPartPut(
      session: session,
      partNumber: partNumber,
      bytes: bytes,
      mime: mime,
      authKey: authKey,
      timeStr: timeStr,
      cancelToken: cancelToken,
    );
  }

  /// 分片直传 OSS
  Future<String> uploadPartPut({
    required QuarkUploadSession session,
    required int partNumber,
    required Uint8List bytes,
    required String mime,
    required String authKey,
    required String timeStr,
    CancelToken? cancelToken,
  }) async {
    final base = _ossBase(session);
    final resp = await _dio.put(
      base,
      queryParameters: {'partNumber': partNumber, 'uploadId': session.uploadId},
      data: bytes,
      options: Options(
        headers: {
          'Authorization': authKey,
          'Content-Type': mime,
          'Referer': 'https://pan.quark.cn/',
          'x-oss-date': timeStr,
          'x-oss-user-agent': _ossUserAgent,
        },
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 60),
      ),
      cancelToken: cancelToken,
    );
    if (resp.statusCode != 200) {
      throw QuarkException(resp.statusCode ?? -1,
          '上传分片 $partNumber 失败 (HTTP ${resp.statusCode})');
    }
    final etag = (resp.headers.value('etag') ?? '').replaceAll('"', '');
    if (etag.isEmpty) {
      throw QuarkException(-1, '上传分片 $partNumber 未返回 ETag');
    }
    return etag;
  }

  /// 分片 PUT 的 OSS V1 签名串（与直传请求头逐字一致）
  static String partAuthMeta(
      QuarkUploadSession s, int partNumber, String mime, String timeStr) {
    return 'PUT\n'
        '\n'
        '$mime\n'
        '$timeStr\n'
        'x-oss-date:$timeStr\n'
        'x-oss-user-agent:$_ossUserAgent\n'
        '/${s.bucket}/${s.objKey}?partNumber=$partNumber&uploadId=${s.uploadId}';
  }

  /// 合并分片：POST CompleteMultipartUpload 到 OSS（含网盘回调登记）
  /// 200 与 203（回调失败但文件已上传成功）均视为成功
  Future<void> uploadCommit({
    required QuarkUploadSession session,
    required List<String> etags,
    required String mime,
  }) async {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<CompleteMultipartUpload>');
    for (var i = 0; i < etags.length; i++) {
      buffer
        ..writeln('<Part>')
        ..writeln('<PartNumber>${i + 1}</PartNumber>')
        ..writeln('<ETag>"${etags[i]}"</ETag>')
        ..writeln('</Part>');
    }
    buffer.writeln('</CompleteMultipartUpload>');
    final xml = buffer.toString();

    final contentMd5 = base64Encode(md5.convert(utf8.encode(xml)).bytes);
    final callback = jsonEncode({
      if (session.callbackUrl.isNotEmpty) 'callbackUrl': session.callbackUrl,
      if (session.callbackBody.isNotEmpty) 'callbackBody': session.callbackBody,
    });
    final callbackBase64 = base64Encode(utf8.encode(callback));

    final timeStr = _httpDate();
    final authMeta = 'POST\n'
        '$contentMd5\n'
        'application/xml\n'
        '$timeStr\n'
        'x-oss-callback:$callbackBase64\n'
        'x-oss-date:$timeStr\n'
        'x-oss-user-agent:$_ossUserAgent\n'
        '/${session.bucket}/${session.objKey}?uploadId=${session.uploadId}';
    final authKey = await uploadAuth(
        authInfo: session.authInfo, authMeta: authMeta, taskId: session.taskId);

    final base = _ossBase(session);
    final resp = await _dio.post(
      base,
      queryParameters: {'uploadId': session.uploadId},
      data: xml,
      options: Options(
        headers: {
          'Authorization': authKey,
          'Content-MD5': contentMd5,
          'Content-Type': 'application/xml',
          'Referer': 'https://pan.quark.cn/',
          'x-oss-callback': callbackBase64,
          'x-oss-date': timeStr,
          'x-oss-user-agent': _ossUserAgent,
        },
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    if (resp.statusCode != 200 && resp.statusCode != 203) {
      throw QuarkException(resp.statusCode ?? -1,
          '合并分片失败 (HTTP ${resp.statusCode})');
    }
  }

  /// 完成上传（通知服务端登记文件）
  Future<void> uploadFinish({
    required String objKey,
    required String taskId,
  }) async {
    await _post('$driveApi/file/upload/finish',
        params: _ucParams, data: {'obj_key': objKey, 'task_id': taskId});
  }

  /// OSS 直传基础 URL：https://{bucket}.{upload_url去协议}/{obj_key}
  String _ossBase(QuarkUploadSession s) {
    var host = s.uploadUrl;
    if (host.startsWith('https://')) {
      host = host.substring(8);
    } else if (host.startsWith('http://')) {
      host = host.substring(7);
    }
    return 'https://${s.bucket}.$host/${s.objKey}';
  }

  /// RFC1123 GMT 时间（auth_meta 与直传请求头必须同秒一致）
  static String _httpDate() => HttpDate.format(DateTime.now().toUtc());

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
