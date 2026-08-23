import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/netdisk123_client.dart';
import '../utils/app_logger.dart';

/// 单个 123 网盘账号
class Netdisk123Account {
  final String id; // 归一化 username，作为唯一键
  String username; // 展示用原始账号
  String password; // 记住的密码（扫码登录为空）
  String token;

  Netdisk123Account({
    required this.id,
    required this.username,
    this.password = '',
    this.token = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password': password,
        'token': token,
      };

  factory Netdisk123Account.fromJson(Map<String, dynamic> j) =>
      Netdisk123Account(
        id: (j['id'] ?? j['username'] ?? '').toString(),
        username: (j['username'] ?? j['id'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
      );
}

/// 123 网盘登录态管理（多账号持久化 + 兼容旧单账号迁移）
class Netdisk123State extends ChangeNotifier {
  // 新键
  static const _kAccounts = 'netdisk123_accounts_json';
  static const _kActiveId = 'netdisk123_active_id';
  // 旧单账号键（仅迁移用）
  static const _kToken = 'netdisk123_token';
  static const _kPassword = 'netdisk123_password';
  static const _kUsername = 'netdisk123_username';

  static Netdisk123State? _instance;
  static Netdisk123State get I => _instance ??= Netdisk123State._();

  final Netdisk123Client client = Netdisk123Client();
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  List<Netdisk123Account> accounts = [];
  String? _activeId;
  bool _ready = false;

  /// 当前活跃账号的容量信息（-1 表示未拉取/不可用）
  int _totalSize = -1;
  int _usedSize = -1;

  Netdisk123State._();

  int get totalSize => _totalSize;
  int get usedSize => _usedSize;

  /// 是否已拿到有效容量数据
  bool get hasQuota => _totalSize > 0 && _usedSize >= 0;

  String? get activeId => _activeId;
  Netdisk123Account? get active {
    if (_activeId != null) {
      for (final a in accounts) {
        if (a.id == _activeId) return a;
      }
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  /// 兼容旧调用：当前活跃账号的展示名
  String? get username => active?.username;

  bool get isLoggedIn => client.hasLogin;
  bool get hasMultiple => accounts.length > 1;

  /// 未登录或容量数据不可用
  bool get noQuota => !isLoggedIn || !hasQuota;

  String _normalizeId(String raw) => raw.trim().toLowerCase();

  /// 应用启动时恢复登录态
  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _loadAccounts();
      // 兼容旧单账号迁移
      if (accounts.isEmpty) {
        final legacyToken = await _read(_kToken);
        final legacyPassword = await _read(_kPassword);
        final legacyUsername = await _read(_kUsername);
        if (legacyToken.isNotEmpty && legacyUsername.isNotEmpty) {
          final id = _normalizeId(legacyUsername);
          accounts = [
            Netdisk123Account(
              id: id,
              username: legacyUsername,
              password: legacyPassword,
              token: legacyToken,
            )
          ];
          _activeId = id;
          await _persistAccounts();
        } else if (legacyToken.isNotEmpty) {
          final id = 'legacy_${DateTime.now().millisecondsSinceEpoch}';
          accounts = [
            Netdisk123Account(
              id: id,
              username: legacyUsername.isNotEmpty ? legacyUsername : id,
              password: legacyPassword,
              token: legacyToken,
            )
          ];
          _activeId = id;
          await _persistAccounts();
        }
      }
      if (accounts.isNotEmpty) {
        _activeId ??= accounts.first.id;
        final a = active;
        if (a != null) {
          client.setToken(a.token);
          if (a.username.isNotEmpty && a.password.isNotEmpty) {
            client.setCredentials(a.username, a.password);
          }
          if (a.token.isNotEmpty) {
            final ok = await client.validate();
            if (!ok && a.password.isNotEmpty) {
              AppLogger.I.i('netdisk123', 'token 失效，尝试自动重登 ${a.username}');
              final err = await client.signIn(a.username, a.password);
              if (err == null) {
                a.token = client.token;
                await _persistAccounts();
              }
            } else if (!ok) {
              AppLogger.I.w('netdisk123', 'active token 失效且无密码，保留账号但未登录');
              client.clear();
            } else {
              // validate 成功，同步 token（可能被刷新）
              a.token = client.token;
            }
          }
          if (client.hasLogin) await refreshQuota();
        }
      }
    } catch (e) {
      AppLogger.I.e('netdisk123', '恢复登录态失败: $e');
    }
    notifyListeners();
  }

  /// 密码登录：新增或更新账号，并切为活跃
  Future<String?> login(String account, String password) async {
    final err = await client.signIn(account, password);
    if (err != null) {
      AppLogger.I.e('netdisk123', '登录失败: $err');
      return err;
    }
    final id = _normalizeId(account);
    final idx = accounts.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      accounts[idx].username = account.trim();
      accounts[idx].password = password;
      accounts[idx].token = client.token;
    } else {
      accounts.add(Netdisk123Account(
        id: id,
        username: account.trim(),
        password: password,
        token: client.token,
      ));
    }
    _activeId = id;
    if (account.trim().isNotEmpty && password.isNotEmpty) {
      client.setCredentials(account.trim(), password);
    }
    await _persistAccounts();
    AppLogger.I.i('netdisk123', '登录成功 account=$account 账号数=${accounts.length}');
    await refreshQuota();
    notifyListeners();
    return null;
  }

  /// 扫码登录成功：写入 token，关联到活跃账号或新建
  Future<void> loginByToken(String token, {String? usernameHint}) async {
    client.setToken(token);
    // 尝试获取用户名（尽力，不阻塞失败）
    String? resolvedName = usernameHint;
    if (resolvedName == null || resolvedName.isEmpty) {
      try {
        final info = await client.fetchUserInfo();
        resolvedName = (info['username'] ?? info['passport'] ?? info['mail'] ?? info['nickname'] ?? '').toString();
      } catch (_) {}
    }
    if (resolvedName != null && resolvedName.isNotEmpty) {
      final id = _normalizeId(resolvedName);
      final idx = accounts.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        accounts[idx].token = token;
        _activeId = id;
      } else {
        accounts.add(Netdisk123Account(
          id: id,
          username: resolvedName,
          token: token,
        ));
        _activeId = id;
      }
    } else if (active != null) {
      // 无用户名时复用当前活跃账号（若有）
      active!.token = token;
    } else {
      final id = 'qr_${DateTime.now().millisecondsSinceEpoch}';
      accounts.add(Netdisk123Account(
        id: id,
        username: '扫码账号',
        token: token,
      ));
      _activeId = id;
    }
    await _persistAccounts();
    AppLogger.I.i('netdisk123', '扫码登录成功 active=$_activeId');
    await refreshQuota();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    final exists = accounts.any((e) => e.id == id);
    if (!exists) return;
    _activeId = id;
    final a = active;
    if (a != null) {
      client.setToken(a.token);
      if (a.username.isNotEmpty && a.password.isNotEmpty) {
        client.setCredentials(a.username, a.password);
      } else if (a.username.isNotEmpty) {
        client.setCredentials(a.username, a.password);
      }
      // 校验
      if (a.token.isNotEmpty) {
        final ok = await client.validate();
        if (!ok && a.password.isNotEmpty) {
          final err = await client.signIn(a.username, a.password);
          if (err == null) {
            a.token = client.token;
            await _persistAccounts();
          }
        }
      }
      if (client.hasLogin) await refreshQuota();
    }
    await _persistAccounts();
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    accounts.removeWhere((e) => e.id == id);
    if (_activeId == id) {
      _activeId = accounts.isEmpty ? null : accounts.first.id;
      final a = active;
      if (a != null) {
        client.setToken(a.token);
        if (a.username.isNotEmpty) client.setCredentials(a.username, a.password);
      } else {
        client.clear();
        _totalSize = -1;
        _usedSize = -1;
      }
    }
    await _persistAccounts();
    if (client.hasLogin) await refreshQuota();
    notifyListeners();
  }

  /// 拉取当前活跃账号的容量信息并缓存（供网盘页/我的页展示）
  Future<void> refreshQuota() async {
    if (!client.hasLogin) {
      _totalSize = -1;
      _usedSize = -1;
      notifyListeners();
      return;
    }
    try {
      final q = await client.fetchQuota();
      _totalSize = q.totalSize;
      _usedSize = q.usedSize;
    } catch (_) {
      // 失败保留旧值，不提示
    }
    notifyListeners();
  }

  /// 退出当前活跃账号
  Future<void> logoutActive() async {
    final a = active;
    if (a == null) {
      client.clear();
      notifyListeners();
      return;
    }
    await removeAccount(a.id);
  }

  /// 退出全部
  Future<void> logout() async {
    client.clear();
    accounts = [];
    _activeId = null;
    for (final k in [_kAccounts, _kActiveId, _kToken, _kPassword, _kUsername]) {
      try {
        await _secure.delete(key: k);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(k);
      } catch (_) {}
    }
    AppLogger.I.i('netdisk123', '已退出全部登录');
    notifyListeners();
  }

  // ------------- 持久化 -------------

  Future<void> _loadAccounts() async {
    final raw = await _read(_kAccounts);
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        accounts = decoded
            .whereType<Map>()
            .map((e) => Netdisk123Account.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    final aid = await _read(_kActiveId);
    if (aid.isNotEmpty && accounts.any((e) => e.id == aid)) {
      _activeId = aid;
    } else if (accounts.isNotEmpty) {
      _activeId = accounts.first.id;
    }
  }

  Future<void> _persistAccounts() async {
    final jsonStr = jsonEncode(accounts.map((e) => e.toJson()).toList());
    await _write(_kAccounts, jsonStr);
    if (_activeId != null && _activeId!.isNotEmpty) {
      await _write(_kActiveId, _activeId!);
    }
    // 同步当前活跃账号的 token/password 到旧键（兼容旧版本回退）
    final a = active;
    if (a != null) {
      await _write(_kToken, a.token);
      await _write(_kUsername, a.username);
      if (a.password.isNotEmpty) await _write(_kPassword, a.password);
    }
  }

  Future<String> _read(String key) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) ?? '';
    } catch (_) {}
    return '';
  }

  Future<void> _write(String key, String value) async {
    if (value.isEmpty) return;
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }
}
