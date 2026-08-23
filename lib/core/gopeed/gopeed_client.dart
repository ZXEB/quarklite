import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/types.dart';
import 'download_client.dart';
import 'gopeed_models.dart';

class GopeedClient implements DownloadClient {
  final Dio _dio;

  GopeedClient(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: '$baseUrl/api/v1',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ));

  dynamic _check(Response<dynamic> resp) {
    final body = resp.data;
    if (body is Map) {
      final code = toInt(body['code'], fallback: -1);
      if (code != 0) {
        throw Exception(body['msg']?.toString() ?? 'Gopeed 请求失败');
      }
      return body['data'];
    }
    return body;
  }

  /// 创建任务，返回任务 id
  @override
  Future<String> create({
    required String url,
    required String path,
    String? name,
    Map<String, String> headers = const {},
    int connections = 16,
  }) async {
    final resp = await _dio.post('/tasks', data: {
      'req': {
        'url': url,
        if (headers.isNotEmpty)
          'extra': {
            'method': 'GET',
            'header': headers,
            'body': '',
          },
      },
      'opts': {
        'name': name ?? '',
        'path': path,
        'selectFiles': <int>[],
        'extra': {'connections': connections},
      },
    });
    return _check(resp)?.toString() ?? '';
  }

  @override
  Future<List<GopeedTask>> list({List<GopeedStatus>? statuses}) async {
    final qs = statuses == null || statuses.isEmpty
        ? ''
        : '?${statuses.map((e) => 'status=${e.name}').join('&')}';
    final resp = await _dio.get('/tasks$qs');
    final data = _check(resp);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => GopeedTask.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> pause(String id) async {
    await _dio.put('/tasks/$id/pause');
  }

  @override
  Future<void> resume(String id) async {
    await _dio.put('/tasks/$id/continue');
  }

  @override
  Future<void> remove(String id, {bool force = true}) async {
    await _dio.delete('/tasks/$id', queryParameters: {'force': force});
  }

  @override
  Future<void> removeAll({List<String>? ids, bool force = true}) async {
    await _dio.delete('/tasks',
        queryParameters: {'id': ids, 'force': force});
  }

  @override
  Future<void> pauseAll({List<String>? ids}) async {
    await _dio.put('/tasks/pause', queryParameters: {'id': ids});
  }

  /// 全局配置：下载目录 / 并发任务数 / HTTP 连接数（先读取再合并，避免覆盖其他设置）
  @override
  Future<void> updateConfig({
    String? downloadDir,
    int? maxRunning,
    int? connections,
  }) async {
    var data = await getConfig();
    if (downloadDir != null) data['downloadDir'] = downloadDir;
    if (maxRunning != null) data['maxRunning'] = maxRunning;
    if (connections != null) {
      final protocol = (data['protocolConfig'] as Map?)?.cast<String, dynamic>() ?? {};
      final http = (protocol['http'] as Map?)?.cast<String, dynamic>() ?? {};
      http['connections'] = connections;
      protocol['http'] = http;
      data['protocolConfig'] = protocol;
    }
    final resp = await _dio.put('/config', data: data);
    _check(resp);
  }

  @override
  Future<Map<String, dynamic>> getConfig() async {
    final resp = await _dio.get('/config');
    final data = _check(resp);
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  String toStringSafe() => jsonEncode({'ok': true});
}
