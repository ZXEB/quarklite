/// 视频与字幕文件扩展名判断（网盘文件点击播放与图标展示共用）。
const Set<String> kVideoExtensions = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'm2ts',
  'mts', 'rmvb', 'rm', 'mpg', 'mpeg', 'mpe', 'vob', '3gp', 'ogv', 'divx',
  'f4v', 'asf', 'mxf',
};

const Set<String> kSubtitleExtensions = {
  'srt', 'ass', 'ssa', 'vtt', 'sub', 'idx',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

bool isVideoFileName(String name) => kVideoExtensions.contains(_extensionOf(name));

bool isSubtitleFileName(String name) =>
    kSubtitleExtensions.contains(_extensionOf(name));

/// 文件名去掉扩展名（外挂字幕与视频同名匹配用）。
String fileNameWithoutExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}
