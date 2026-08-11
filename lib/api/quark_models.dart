import '../utils/types.dart';

class QuarkUserInfo {
  final String nickname;
  final String avatar;
  final String userId;

  QuarkUserInfo({
    required this.nickname,
    required this.avatar,
    required this.userId,
  });

  factory QuarkUserInfo.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return QuarkUserInfo(
      nickname: _s(data, 'nickname'),
      avatar: _s(data, 'avatar'),
      userId: _s(data, 'user_id'),
    );
  }

  static String _s(dynamic obj, String key) {
    if (obj is Map) {
      final v = obj[key];
      return v == null ? '' : v.toString();
    }
    return '';
  }
}

class QuarkFile {
  final String fid;
  final String fileName;
  final String fileType;
  final bool isDir;
  final int size;
  final String pdirFid;
  final String fileExt;
  final int updatedAt;
  final int category;
  final String objCategory;
  final String thumbnail;
  final String bigThumbnail;
  final String previewUrl;
  final int duration;
  final int shotAt;

  QuarkFile({
    required this.fid,
    required this.fileName,
    required this.fileType,
    required this.isDir,
    required this.size,
    required this.pdirFid,
    required this.fileExt,
    required this.updatedAt,
    required this.category,
    required this.objCategory,
    required this.thumbnail,
    required this.bigThumbnail,
    required this.previewUrl,
    required this.duration,
    required this.shotAt,
  });

  /// 相册展示用的拍摄/修改时间（毫秒）
  int get albumTime => shotAt > 0 ? shotAt : updatedAt;

  bool get isImage =>
      objCategory == 'image' ||
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
          .contains(fileExt.toLowerCase());

  /// 动态照片（手机 live photo，短时长视频片段，duration 单位为秒）
  bool get isLivePhoto =>
      !isDir &&
      (objCategory == 'video' || fileExt.toLowerCase() == 'mp4') &&
      duration > 0 &&
      duration <= 5;

  /// 截图（文件名特征识别）
  bool get isScreenshot {
    final n = fileName.toLowerCase();
    return n.startsWith('screenshot') ||
        n.startsWith('screencap') ||
        n.startsWith('screen_shot') ||
        n.startsWith('screenrecord') ||
        n.contains('screencapture') ||
        n.contains('截图') ||
        n.contains('屏幕截图');
  }

  factory QuarkFile.fromJson(Map<String, dynamic> json) {
    final type = json['file_type']?.toString() ?? '';
    final dirFlag = json['dir'] == true;
    return QuarkFile(
      fid: json['fid']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: toInt(json['size']),
      pdirFid: json['pdir_fid']?.toString() ?? '',
      fileExt: json['file_ext']?.toString() ?? '',
      updatedAt: toInt(json['updated_at']),
      category: toInt(json['category']),
      objCategory: json['obj_category']?.toString() ?? '',
      thumbnail:
          json['thumbnail']?.toString() ?? json['preview_url']?.toString() ?? json['cover']?.toString() ?? '',
      bigThumbnail: json['big_thumbnail']?.toString() ?? '',
      previewUrl: json['preview_url']?.toString() ?? '',
      duration: toInt(json['duration']),
      shotAt: toInt(json['l_shot_at']),
    );
  }
}

class QuarkShareFile {
  final String fid;
  final String fileName;
  final String fileType;
  final bool isDir;
  final int size;
  final String pdirFid;
  final String shareFidToken;

  QuarkShareFile({
    required this.fid,
    required this.fileName,
    required this.fileType,
    required this.isDir,
    required this.size,
    required this.pdirFid,
    required this.shareFidToken,
  });

  factory QuarkShareFile.fromJson(Map<String, dynamic> json) {
    final type = json['file_type']?.toString() ?? '';
    final dirFlag = json['dir'] == true;
    return QuarkShareFile(
      fid: json['fid']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: toInt(json['size']),
      pdirFid: json['pdir_fid']?.toString() ?? '',
      shareFidToken: json['share_fid_token']?.toString() ?? '',
    );
  }
}

class QuarkDownloadInfo {
  final String url;
  final String fileName;
  final int size;
  final String fid;

  QuarkDownloadInfo({
    required this.url,
    required this.fileName,
    required this.size,
    required this.fid,
  });

  factory QuarkDownloadInfo.fromJson(Map<String, dynamic> json) {
    return QuarkDownloadInfo(
      url: json['download_url']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      size: toInt(json['size']),
      fid: json['fid']?.toString() ?? '',
    );
  }
}
