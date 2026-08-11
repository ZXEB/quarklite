import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/file_icon.dart';
import 'permission.dart';

/// 夸克图片组件：带 Cookie 请求头 + 磁盘缓存 + 占位/错误兜底
class QuarkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final String? fileName;
  final double? width;
  final double? height;
  final Widget Function(BuildContext)? placeholder;

  const QuarkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.fileName,
    this.width,
    this.height,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: quarkImageHeaders(),
      placeholder: (_, _) =>
          placeholder?.call(context) ??
          Container(
            color: AppColors.card,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      errorWidget: (_, _, _) => Container(
        color: AppColors.card,
        child: Center(
          child: FileIcon(isDir: false, name: fileName ?? '', size: 36),
        ),
      ),
    );
  }
}
