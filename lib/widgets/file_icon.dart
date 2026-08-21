import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../theme/app_theme.dart';

class FileIcon extends StatelessWidget {
  final bool isDir;
  final String name;
  final double size;

  const FileIcon({
    super.key,
    required this.isDir,
    required this.name,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _icon();
    final color = isDir ? AppColors.accent : _color();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: MiuixIcon(icon: icon, tint: color, size: size * 0.52),
    );
  }

  IconData _icon() {
    if (isDir) return Icons.folder_rounded;
    final lower = name.toLowerCase();
    if (lower.endsWith('.torrent') || lower.startsWith('magnet:')) {
      return Icons.wifi_tethering_rounded;
    }
    if (_any(lower, ['mp4', 'mkv', 'avi', 'mov', 'rmvb', 'flv', 'wmv', 'webm', 'ts'])) {
      return Icons.movie_rounded;
    }
    if (_any(lower, ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'])) {
      return Icons.music_note_rounded;
    }
    if (_any(lower, ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'])) {
      return Icons.image_rounded;
    }
    if (_any(lower, ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'])) {
      return Icons.archive_rounded;
    }
    if (_any(lower, ['apk'])) {
      return Icons.android_rounded;
    }
    if (_any(lower, ['txt', 'md', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'])) {
      return Icons.description_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  bool _any(String name, List<String> exts) =>
      exts.any((e) => name.endsWith('.$e'));

  Color _color() {
    final lower = name.toLowerCase();
    if (_any(lower, ['mp4', 'mkv', 'avi'])) return AppColors.orange;
    if (_any(lower, ['mp3', 'flac'])) return const Color(0xFFB57BFF);
    if (_any(lower, ['zip', 'rar', '7z'])) return const Color(0xFF43C6AC);
    if (lower.endsWith('.torrent')) return AppColors.green;
    return AppColors.accent;
  }
}
