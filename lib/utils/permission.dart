import 'package:flutter/material.dart';

import '../api/quark_client.dart';
import '../state/app_state.dart';
import '../widgets/miuix_common.dart';

/// 夸克图片/缩略图加载所需的请求头（缩略图 URL 带签名，需携带登录 Cookie）
Map<String, String> quarkImageHeaders() {
  return {
    if (AppState.I.quark.cookie.isNotEmpty) 'Cookie': AppState.I.quark.cookie,
    'Referer': 'https://pan.quark.cn/',
    'User-Agent': QuarkClient.uaPc,
  };
}

/// 检查存储权限，未授权时弹窗引导去系统设置；返回是否已可用。
/// [purpose] 用于定制弹窗文案（如「上传文件夹」）。
Future<bool> ensureStoragePermission(BuildContext context,
    {String purpose = '下载文件'}) async {
  final app = AppState.I;
  if (await app.canWriteDownload()) return true;
  if (!context.mounted) return false;
  final granted = await confirmMiuix(
    context,
    title: '需要存储权限',
    content: '$purpose需要「所有文件访问」权限，请授权后继续。',
    confirmText: '去授权',
  );
  if (granted == true) app.openAllFilesAccess();
  return false;
}

void toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  MiuixToast.show(msg);
}
