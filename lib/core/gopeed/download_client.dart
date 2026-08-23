import 'gopeed_models.dart';

/// 平台无关的下载客户端接口。
///
/// Windows/Android 由 Gopeed 实现，iOS 由 URLSession 后台下载器实现。
abstract interface class DownloadClient {
  Future<String> create({
    required String url,
    required String path,
    String? name,
    Map<String, String> headers = const {},
    int connections = 16,
  });

  Future<List<GopeedTask>> list({List<GopeedStatus>? statuses});

  Future<void> pause(String id);

  Future<void> resume(String id);

  Future<void> remove(String id, {bool force = true});

  Future<void> removeAll({List<String>? ids, bool force = true});

  Future<void> pauseAll({List<String>? ids});

  Future<void> updateConfig({
    String? downloadDir,
    int? maxRunning,
    int? connections,
  });

  Future<Map<String, dynamic>> getConfig();
}
