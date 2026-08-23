import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/miuix_common.dart';

class AppUpdate {
  final String version;
  final Uri releaseUrl;
  final String notes;

  const AppUpdate({
    required this.version,
    required this.releaseUrl,
    required this.notes,
  });
}

class UpdateChecker {
  UpdateChecker._();

  static const currentVersion = '1.3.2';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/ZXEB/quarklite/releases/latest';
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Quarklite-update-checker',
    },
  ));

  static Future<AppUpdate?> check() async {
    try {
      final response = await _dio.get<dynamic>(_latestReleaseUrl);
      final data = response.data;
      if (data is! Map) return null;
      final tag = data['tag_name']?.toString() ?? '';
      final version = _normalize(tag);
      final url = Uri.tryParse(data['html_url']?.toString() ?? '');
      if (version == null || url == null || !url.hasScheme) return null;
      if (!_isNewer(version, currentVersion)) return null;
      return AppUpdate(
        version: version,
        releaseUrl: url,
        notes: data['body']?.toString().trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> checkAndPrompt(BuildContext context) async {
    final update = await check();
    if (!context.mounted || update == null) return;
    final notes = update.notes.isEmpty ? '' : '\n\n${update.notes}';
    final open = await confirmMiuix(
      context,
      title: '发现新版本 ${update.version}',
      content: '当前版本 $currentVersion，是否打开 GitHub Release 下载更新？$notes',
      confirmText: '打开下载页',
    );
    if (!open) return;
    await launchUrl(update.releaseUrl, mode: LaunchMode.externalApplication);
  }

  static String? _normalize(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    return match == null ? null : '${match[1]}.${match[2]}.${match[3]}';
  }

  static bool _isNewer(String candidate, String current) {
    final a = candidate.split('.').map(int.parse).toList();
    final b = current.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}
