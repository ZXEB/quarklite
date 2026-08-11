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
  });

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
