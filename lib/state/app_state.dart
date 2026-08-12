import 'dart:async';
import 'dart:convert';

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
  static const _kCookieBackup = 'quark_cookie_backup';
  static const _kUserCache = 'quark_user_cache';
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
  int connections = 8;

  Timer? _sessionTimer;

  bool get isLoggedIn => user != null;

  Future<void> init() async {
    _loadSettings();
    final cookie = await _loadCookie();
    if (cookie == null || cookie.isEmpty) return;
    quark.setCookie(cookie);
    _startSessionRefresher();
    user = await _readCachedUser();
    await refreshUser();
  }

  /// 读取持久化 cookie：优先安全存储，读取失败时回退到普通存储
  Future<String?> _loadCookie() async {
    try {
      final cookie = await _secure.read(key: _kCookie);
      if (cookie != null && cookie.isNotEmpty) return cookie;
    } catch (_) {
      // 部分设备 Keystore 异常导致安全存储不可读，走兜底存储
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kCookieBackup);
    } catch (_) {
      return null;
    }
  }

  /// 双写持久化：安全存储 + 普通存储兜底
  Future<void> _saveCookie() async {
    final cookie = quark.cookie;
    if (cookie.isEmpty) return;
    try {
      await _secure.write(key: _kCookie, value: cookie);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCookieBackup, cookie);
    } catch (_) {}
  }

  Future<void> _clearCookie() async {
    try {
      await _secure.delete(key: _kCookie);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCookieBackup);
      await prefs.remove(_kUserCache);
    } catch (_) {}
  }

  Future<void> _cacheUser(QuarkUserInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kUserCache,
        jsonEncode({
          'nickname': info.nickname,
          'avatar': info.avatar,
          'user_id': info.userId,
        }),
      );
    } catch (_) {}
  }

  Future<QuarkUserInfo?> _readCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUserCache);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return QuarkUserInfo(
        nickname: map['nickname']?.toString() ?? '',
        avatar: map['avatar']?.toString() ?? '',
        userId: map['user_id']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  void _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      downloadDir =
          prefs.getString(_kDownloadDir) ?? '/storage/emulated/0/Download/Quarklite';
      connections = prefs.getInt(_kConnections) ?? 8;
      notifyListeners();
    });
  }

  Future<void> refreshUser() async {
    loading = true;
    notifyListeners();
    try {
      user = await quark.getUserInfo();
      loginError = null;
      await _cacheUser(user!);
      await _saveCookie();
    } catch (e) {
      // 网络等临时错误不登出：保留已登录状态，避免每次启动都被迫重新登录
      if (user == null) loginError = e.toString();
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
      _startSessionRefresher();
      await _saveCookie();
      await _cacheUser(info);
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
    await _clearCookie();
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

  /// 每 100 分钟刷新一次会话并持久化最新 cookie
  void _startSessionRefresher() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(minutes: 100), (_) async {
      await quark.refreshSession();
      await _saveCookie();
    });
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
