import 'package:flutter/material.dart';

import '../api/quark_client.dart';
import '../state/app_state.dart';

/// 夸克图片/缩略图加载所需的请求头（缩略图 URL 带签名，需携带登录 Cookie）
Map<String, String> quarkImageHeaders() {
  return {
    if (AppState.I.quark.cookie.isNotEmpty) 'Cookie': AppState.I.quark.cookie,
    'Referer': 'https://pan.quark.cn/',
    'User-Agent': QuarkClient.uaPc,
  };
}

/// 检查存储权限，未授权时弹窗引导去系统设置；返回是否已可用
Future<bool> ensureStoragePermission(BuildContext context) async {
  final app = AppState.I;
  if (await app.canWriteDownload()) return true;
  if (!context.mounted) return false;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('需要存储权限'),
      content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            app.openAllFilesAccess();
          },
          child: const Text('去授权'),
        ),
      ],
    ),
  );
  return false;
}

void toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}
