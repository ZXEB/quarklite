import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/quark_client.dart';
import '../api/quark_models.dart';

class AppState extends ChangeNotifier {
  static const _sysChannel = MethodChannel('quarklite.com/system');
  static const _kCookie = 'quark_cookie';
  static const _kDownloadDir = 'download_dir';
  static const _kConnections = 'connections';

  static AppState? _instance;
  static AppState get I => _instance ??= AppState._();

  AppState._();

  final QuarkClient quark = QuarkClient();
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  QuarkUserInfo? user;
  String? loginError;
  bool loading = false;

  String downloadDir = '';
  int connections = 16;

  Timer? _sessionTimer;

  bool get isLoggedIn => user != null;

  Future<void> init() async {
    _loadSettings();
    final cookie = await _secure.read(key: _kCookie);
    if (cookie != null && cookie.isNotEmpty) {
      quark.setCookie(cookie);
      quark.startSessionRefresher();
      await refreshUser();
    }
  }

  void _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      downloadDir =
          prefs.getString(_kDownloadDir) ?? '/storage/emulated/0/Download/Quarklite';
      connections = prefs.getInt(_kConnections) ?? 16;
      notifyListeners();
    });
  }

  Future<void> refreshUser() async {
    loading = true;
    notifyListeners();
    try {
      user = await quark.getUserInfo();
      loginError = null;
    } catch (e) {
      loginError = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  /// 登录：设置 cookie 并验证
  Future<String?> login(String cookie) async {
    try {
      quark.setCookie(cookie);
      final info = await quark.getUserInfo();
      user = info;
      loginError = null;
      quark.startSessionRefresher();
      await _secure.write(key: _kCookie, value: quark.cookie);
      notifyListeners();
      return null;
    } catch (e) {
      quark.setCookie('');
      return e.toString();
    }
  }

  Future<void> logout() async {
    quark.setCookie('');
    user = null;
    await _secure.delete(key: _kCookie);
    notifyListeners();
  }

  Future<void> setDownloadDir(String dir) async {
    downloadDir = dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadDir, dir);
    notifyListeners();
  }

  Future<void> setConnections(int n) async {
    connections = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConnections, n);
    notifyListeners();
  }

  /// 当前可用的下载目录（无存储权限时回退到应用专属目录）
  Future<String> effectiveDownloadDir() async {
    final canWrite = await canWriteDownload();
    if (canWrite && downloadDir.isNotEmpty) return downloadDir;
    final ext = await getExternalStorageDirectory();
    return '${ext?.path ?? (await getApplicationDocumentsDirectory()).path}/downloads';
  }

  Future<bool> canWriteDownload() async {
    try {
      return await _sysChannel.invokeMethod<bool>('canWriteDownload') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAllFilesAccess() async {
    try {
      await _sysChannel.invokeMethod('openAllFilesAccess');
    } catch (_) {}
  }

  @override
  void dispose() {
    quark.dispose();
    _sessionTimer?.cancel();
    super.dispose();
  }
}
