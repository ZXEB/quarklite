import '../api/quark_client.dart';
import '../core/gopeed/gopeed_boot.dart';
import '../core/gopeed/gopeed_client.dart';
import '../state/app_state.dart';
import '../utils/app_logger.dart';

class DownloadService {
  /// 把直链加入 Gopeed 下载队列，返回错误信息（null 表示成功）
  /// [batchTotal] 为本次批量下载的任务总数，用于按预算分摊连接数（默认单任务）。
  static Future<String?> addDirectUrl({
    required String url,
    required String fileName,
    required String cookie,
    String? path,
    int? connections,
    int batchTotal = 1,
  }) async {
    try {
      var client = await GopeedEngine.ensureStarted();
      final dir = path ?? await AppState.I.effectiveDownloadDir();
      final app = AppState.I;
      final actualConnections =
          connections ?? app.effectiveConnections(batchTotal);
      AppLogger.I.i('download',
          '创建任务 name=$fileName connections=$actualConnections batch=$batchTotal dir=$dir url=${_briefUrl(url)}');
      try {
        await _createTask(client,
            url: url,
            path: dir,
            name: fileName,
            cookie: cookie,
            connections: actualConnections);
        AppLogger.I.i('download', '创建任务成功 name=$fileName');
      } catch (e) {
        // 引擎进程可能在等待目录等异步操作期间退出（如被杀软终止），
        // 导致引擎状态被清空：重启引擎并重试一次，而不是直接报“引擎尚未启动”
        if (e.toString().contains('下载引擎尚未启动') || !GopeedEngine.started) {
          AppLogger.I.w('download', '引擎失效（$e），重启引擎并重试创建任务 name=$fileName');
          client = await GopeedEngine.ensureStarted();
          await _createTask(client,
              url: url,
              path: dir,
              name: fileName,
              cookie: cookie,
              connections: actualConnections);
          AppLogger.I.i('download', '重试创建任务成功 name=$fileName');
        } else {
          rethrow;
        }
      }
      return null;
    } catch (e) {
      AppLogger.I.e('download', '创建任务最终失败 name=$fileName: $e');
      return '创建下载任务失败: $e';
    }
  }

  /// 日志脱敏：URL 只保留前 120 字符，避免直链签名参数刷屏
  static String _briefUrl(String url) =>
      url.length <= 120 ? url : '${url.substring(0, 120)}…(${url.length})';

  /// 创建 Gopeed 下载任务（附带夸克直链所需的请求头）
  static Future<void> _createTask(
    GopeedClient client, {
    required String url,
    required String path,
    required String name,
    required String cookie,
    required int connections,
  }) {
    return client.create(
      url: url,
      path: path,
      name: name,
      headers: {
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'Referer': 'https://pan.quark.cn/',
        'User-Agent': QuarkClient.uaDesktopClient,
      },
      connections: connections,
    );
  }

  /// 根据 fid 直接下载网盘文件，返回错误信息（null 表示已加入队列）
  static Future<String?> downloadQuarkFile(String fid,
      {String? fileName}) async {
    try {
      final app = AppState.I;
      final (infos, cookie) = await app.quark.getDownloadInfo([fid]);
      if (infos.isEmpty) return '未获取到下载地址';
      final info = infos.first;
      return addDirectUrl(
        url: info.url,
        fileName:
            info.fileName.isNotEmpty ? info.fileName : (fileName ?? ''),
        cookie: cookie,
        batchTotal: 1,
      );
    } catch (e) {
      return '下载失败: $e';
    }
  }

  /// 把 magnet 链接加入下载队列
  static Future<String?> addMagnet({
    required String url,
    String? name,
  }) async {
    try {
      var client = await GopeedEngine.ensureStarted();
      final dir = await AppState.I.effectiveDownloadDir();
      AppLogger.I.i('download', '创建 BT 任务 name=${name ?? ''} dir=$dir');
      try {
        await client.create(
          url: url,
          path: dir,
          name: name ?? '',
        );
        AppLogger.I.i('download', '创建 BT 任务成功 name=${name ?? ''}');
      } catch (e) {
        if (e.toString().contains('下载引擎尚未启动') || !GopeedEngine.started) {
          AppLogger.I.w('download', '引擎失效（$e），重启引擎并重试 BT 任务 name=${name ?? ''}');
          client = await GopeedEngine.ensureStarted();
          await client.create(
            url: url,
            path: dir,
            name: name ?? '',
          );
          AppLogger.I.i('download', '重试 BT 任务成功 name=${name ?? ''}');
        } else {
          rethrow;
        }
      }
      return null;
    } catch (e) {
      AppLogger.I.e('download', '创建 BT 任务失败 name=${name ?? ''}: $e');
      return '创建 BT 任务失败: $e';
    }
  }
}
