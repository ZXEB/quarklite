import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/quark_client.dart';
import '../api/quark_models.dart';
import '../core/gopeed/gopeed_boot.dart';

class AppState extends ChangeNotifier {
  static const _sysChannel = MethodChannel('quarklite.com/system');
  static const _kCookie = 'quark_cookie';
  static const _kCookieBackup = 'quark_cookie_backup';
  static const _kUserCache = 'quark_user_cache';
  static const _kDownloadDir = 'download_dir';
  static const _kConnections = 'connections';
  static const _kXunleiConnections = 'xunlei_connections';
  static const _kMaxRunning = 'max_running';
  static const _kConnectionBudget = 'connection_budget';
  static const _kCloseAction = 'window_close_action';

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

  /// 夸克网盘单任务最大线程数（默认 512）
  int connections = 512;

  /// 迅雷云盘单任务最大线程数（默认 64，迅雷直链单连接限速档位更高，64 线程足够拉满）
  int xunleiConnections = 64;

  /// 全局同时运行的任务数上限（Gopeed maxRunning），超出的任务排队等待
  int maxRunning = 4;

  /// 全局活动连接预算：所有任务的总连接数不超过该值。
  /// 单任务时可拿到接近全部预算保证速度，批量任务自动分摊避免打爆网络中断。
  int connectionBudget = 256;

  /// Windows 关闭窗口行为：ask_once（首次询问后记住）/ minimize / exit / ask
  String closeAction = 'ask_once';

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
      connections = prefs.getInt(_kConnections) ?? 512;
      xunleiConnections = prefs.getInt(_kXunleiConnections) ?? 64;
      maxRunning = prefs.getInt(_kMaxRunning) ?? 4;
      connectionBudget = prefs.getInt(_kConnectionBudget) ?? 256;
      closeAction = prefs.getString(_kCloseAction) ?? 'ask_once';
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

  Future<void> setXunleiConnections(int n) async {
    xunleiConnections = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kXunleiConnections, n);
    notifyListeners();
  }

  Future<void> setMaxRunning(int n) async {
    maxRunning = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxRunning, n);
    await _applyEngineConfig(maxRunning: n);
    notifyListeners();
  }

  Future<void> setConnectionBudget(int n) async {
    connectionBudget = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConnectionBudget, n);
    await _applyEngineConfig(connections: n);
    notifyListeners();
  }

  /// 设置 Windows 关闭窗口行为（与 WindowCloseHandler 共用同一个 key）
  Future<void> setCloseAction(String action) async {
    closeAction = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCloseAction, action);
    notifyListeners();
  }

  /// 把并发配置同步到 Gopeed 引擎（引擎未启动时忽略，启动时由 app.dart 应用）
  Future<void> _applyEngineConfig({int? maxRunning, int? connections}) async {
    try {
      if (!GopeedEngine.started) return;
      await GopeedEngine.client.updateConfig(
        maxRunning: maxRunning,
        connections: connections,
      );
    } catch (_) {
      // 引擎暂不可用时不阻塞设置
    }
  }

  /// 根据批量任务数计算每个任务应分配的实际连接数：
  /// 预算按「同时运行的任务数」均摊（受 maxRunning 限制），
  /// 保证总活跃连接数 ≤ budget（避免收包软中断打爆核心）。
  /// 单任务时拿满预算保证速度，批量时自动收敛避免连接风暴。
  /// [maxPerTask] 为该网盘的单任务线程上限（夸克默认 512，迅雷默认 64）。
  int effectiveConnections(int batchTotal, {int? maxPerTask}) {
    final cap = maxPerTask ?? connections;
    final total = batchTotal <= 0 ? 1 : batchTotal;
    final concurrent = total < maxRunning ? total : maxRunning;
    final share = (connectionBudget / concurrent).ceil();
    return share.clamp(1, cap);
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
    if (!kIsWeb && Platform.isWindows) {
      // Windows：无权限概念，默认用户下载目录
      if (downloadDir.isNotEmpty) return downloadDir;
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
      final ext = await getApplicationDocumentsDirectory();
      return '${ext.path}/downloads';
    }
    final canWrite = await canWriteDownload();
    if (canWrite && downloadDir.isNotEmpty) return downloadDir;
    final ext = await getExternalStorageDirectory();
    return '${ext?.path ?? (await getApplicationDocumentsDirectory()).path}/downloads';
  }

  Future<bool> canWriteDownload() async {
    if (!kIsWeb && Platform.isWindows) return true;
    try {
      return await _sysChannel.invokeMethod<bool>('canWriteDownload') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAllFilesAccess() async {
    if (!kIsWeb && Platform.isWindows) return;
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
