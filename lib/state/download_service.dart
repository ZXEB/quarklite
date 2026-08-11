import '../api/quark_client.dart';
import '../core/gopeed/gopeed_boot.dart';
import '../state/app_state.dart';

class DownloadService {
  /// 把直链加入 Gopeed 下载队列，返回错误信息（null 表示成功）
  static Future<String?> addDirectUrl({
    required String url,
    required String fileName,
    required String cookie,
    int connections = 16,
  }) async {
    try {
      final dir = await AppState.I.effectiveDownloadDir();
      await GopeedEngine.client.create(
        url: url,
        path: dir,
        name: fileName,
        headers: {
          if (cookie.isNotEmpty) 'Cookie': cookie,
          'Referer': 'https://pan.quark.cn/',
          'User-Agent': QuarkClient.uaPc,
        },
        connections: connections,
      );
      return null;
    } catch (e) {
      return '创建下载任务失败: $e';
    }
  }

  /// 把 magnet 链接加入下载队列
  static Future<String?> addMagnet({
    required String url,
    String? name,
  }) async {
    try {
      final dir = await AppState.I.effectiveDownloadDir();
      await GopeedEngine.client.create(
        url: url,
        path: dir,
        name: name ?? '',
      );
      return null;
    } catch (e) {
      return '创建 BT 任务失败: $e';
    }
  }
}
