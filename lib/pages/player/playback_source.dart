import '../../api/netdisk123_client.dart';
import '../../api/quark_client.dart';
import '../../api/xunlei_client.dart';
import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/xunlei_state.dart';

/// 解析完成的播放媒体：直链 + 该直链所需的请求头。
class ResolvedMedia {
  final String url;
  final Map<String, String> headers;

  const ResolvedMedia({required this.url, this.headers = const {}});

  bool get isEmpty => url.isEmpty;
}

/// 外挂字幕候选：按需解析（选中时才请求直链）。
class ExternalSubtitle {
  final String name;
  final Future<ResolvedMedia> Function() resolve;

  const ExternalSubtitle({required this.name, required this.resolve});
}

/// 候选播放源/规格（如迅雷的「原画 / 流媒体」双源）。
class MediaVariant {
  final String key;
  final String label;
  final Future<ResolvedMedia> Function() resolve;

  /// 清晰度排序权重（2160/1080/720…，越大越清晰）；null 表示未知。
  final int? rank;

  const MediaVariant({
    required this.key,
    required this.label,
    required this.resolve,
    this.rank,
  });
}

/// 从清晰度 label 解析排序权重（如 2160/1080P/4K/蓝光），与夸克
/// video_preview 的 _qualityRank 规则一致，用于跨网盘统一选默认源。
int variantRank(String label) {
  final m = RegExp(r'(\d{3,4})').firstMatch(label);
  if (m != null) return int.tryParse(m.group(1)!) ?? 0;
  const named = {
    '4K': 2160,
    '蓝光': 1080,
    '超清': 720,
    '高清': 540,
    '标清': 360,
    '流畅': 240,
  };
  return named[label] ?? 0;
}

/// 一次在线播放请求：三个网盘的直链解析与鉴权头差异全部收敛在此。
class PlaybackRequest {
  /// 'quark' | 'xunlei' | 'netdisk123'，播放进度记忆 key 的一部分。
  final String provider;
  final String providerLabel;
  final String fileId;
  final String fileName;
  final List<MediaVariant> variants;
  final List<ExternalSubtitle> subtitles;

  /// 懒加载的扩展源（转码多清晰度等）：打开播放器后异步拉取，
  /// 合并进规格面板；失败返回空列表即可。
  final Future<List<MediaVariant>> Function()? moreVariantsLoader;

  /// true 时默认源优先选扩展源里 rank 最高的转码档（夸克下载 CDN
  /// 对非会员限速明显，转码 CDN 通常不限速）；false 保持 variants.first。
  final bool preferTranscodeDefault;

  const PlaybackRequest({
    required this.provider,
    required this.providerLabel,
    required this.fileId,
    required this.fileName,
    required this.variants,
    this.subtitles = const [],
    this.moreVariantsLoader,
    this.preferTranscodeDefault = false,
  });

  MediaVariant get defaultVariant => variants.first;

  /// 夸克网盘：下载直链绑定请求时的 Cookie 快照 + 桌面客户端 UA。
  /// [subtitleFids]：同目录下与视频同名的外挂字幕（文件名 → fid）。
  factory PlaybackRequest.quark({
    required String fid,
    required String fileName,
    Map<String, String> subtitleFids = const {},
  }) {
    Future<ResolvedMedia> resolveFid(String id) async {
      final (infos, cookie) = await AppState.I.quark.getDownloadInfo([id]);
      if (infos.isEmpty || infos.first.url.isEmpty) {
        throw Exception('未获取到播放地址');
      }
      return ResolvedMedia(url: infos.first.url, headers: {
        'Cookie': cookie,
        'Referer': 'https://pan.quark.cn/',
        'User-Agent': QuarkClient.uaDesktopClient,
      });
    }

    return PlaybackRequest(
      provider: 'quark',
      providerLabel: '夸克网盘',
      fileId: fid,
      fileName: fileName,
      variants: [
        MediaVariant(key: 'original', label: '原画', resolve: () => resolveFid(fid)),
      ],
      subtitles: [
        for (final e in subtitleFids.entries)
          ExternalSubtitle(name: e.key, resolve: () => resolveFid(e.value)),
      ],
      // 下载 CDN 限速，默认改走转码 CDN；原画仍保留在规格面板可手动切换
      preferTranscodeDefault: true,
      // 转码多清晰度（video_preview）：打开播放器后异步加载
      moreVariantsLoader: () async {
        final (qualities, cookie) = await AppState.I.quark.getVideoPreview(fid);
        return [
          for (final q in qualities)
            MediaVariant(
              key: 'q_${q.label}',
              label: q.label,
              rank: variantRank(q.label),
              resolve: () async => ResolvedMedia(url: q.url, headers: {
                'Cookie': cookie,
                'Referer': 'https://pan.quark.cn/',
                'User-Agent': QuarkClient.uaDesktopClient,
              }),
            ),
        ];
      },
    );
  }

  /// 迅雷网盘：原画（web_content_link）+ 流媒体（medias 视频专用 CDN）双源。
  factory PlaybackRequest.xunlei({
    required String id,
    required String space,
    required String fileName,
    Map<String, (String, String)> subtitleIdSpaces = const {},
  }) {
    Future<XunleiFile> detail() =>
        XunleiState.I.client.getFileDetail(id, space: space);

    return PlaybackRequest(
      provider: 'xunlei',
      providerLabel: '迅雷网盘',
      fileId: id,
      fileName: fileName,
      variants: [
        MediaVariant(key: 'original', label: '原画', resolve: () async {
          final d = await detail();
          if (d.webContentLink.isEmpty) throw Exception('该文件无原画直链');
          return ResolvedMedia(url: d.webContentLink, headers: {
            'User-Agent': XunleiClient.downloadUa,
            'Referer': 'https://pan.xunlei.com/',
          });
        }),
        MediaVariant(key: 'stream', label: '流媒体', resolve: () async {
          final d = await detail();
          if (d.mediaUrl.isEmpty) throw Exception('该文件无流媒体源');
          return ResolvedMedia(url: d.mediaUrl, headers: {
            'User-Agent': XunleiClient.downloadUa,
            'Referer': 'https://pan.xunlei.com/',
          });
        }),
      ],
      subtitles: [
        for (final e in subtitleIdSpaces.entries)
          ExternalSubtitle(name: e.key, resolve: () async {
            final (sid, sspace) = e.value;
            final d = await XunleiState.I.client.getFileDetail(sid, space: sspace);
            final url = d.webContentLink.isNotEmpty
                ? d.webContentLink
                : d.mediaUrl;
            if (url.isEmpty) throw Exception('未获取到字幕地址');
            return ResolvedMedia(url: url, headers: {
              'User-Agent': XunleiClient.downloadUa,
              'Referer': 'https://pan.xunlei.com/',
            });
          }),
      ],
      // 全部转码媒体变体（media_name 如 原画/高清/标清）：打开播放器后异步加载
      moreVariantsLoader: () async {
        final d = await detail();
        return [
          for (final m in d.mediaVariants)
            if (m.url.isNotEmpty)
              MediaVariant(
                key: 'm_${m.label}_${m.url.hashCode}',
                label: m.label,
                rank: variantRank(m.label),
                resolve: () async => ResolvedMedia(url: m.url, headers: {
                  'User-Agent': XunleiClient.downloadUa,
                  'Referer': 'https://pan.xunlei.com/',
                }),
              ),
        ];
      },
    );
  }

  /// 123 网盘：android 协议直链为免鉴权 CDN。
  factory PlaybackRequest.netdisk123({
    required Netdisk123File file,
    Map<String, Netdisk123File> subtitleFiles = const {},
  }) {
    Future<ResolvedMedia> resolveFile(Netdisk123File f) async {
      final url = await Netdisk123State.I.client.getDownloadUrl(f);
      if (url.isEmpty) throw Exception('未获取到播放地址');
      return ResolvedMedia(url: url, headers: {
        'User-Agent': '123pan/v2.4.0(Android_11;Xiaomi)',
        'Referer': 'https://www.123pan.com/',
      });
    }

    return PlaybackRequest(
      provider: 'netdisk123',
      providerLabel: '123云盘',
      fileId: file.id,
      fileName: file.name,
      variants: [
        MediaVariant(key: 'original', label: '原画', resolve: () => resolveFile(file)),
      ],
      subtitles: [
        for (final e in subtitleFiles.entries)
          ExternalSubtitle(name: e.key, resolve: () => resolveFile(e.value)),
      ],
    );
  }
}
