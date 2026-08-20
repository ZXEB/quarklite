import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/netdisk123_client.dart';
import '../utils/app_logger.dart';

/// 123 网盘登录态管理（token 持久化 + 密码自动重登）
class Netdisk123State extends ChangeNotifier {
  static const _kToken = 'netdisk123_token';
  static const _kPassword = 'netdisk123_password';
  static const _kUsername = 'netdisk123_username';

  static Netdisk123State? _instance;
  static Netdisk123State get I => _instance ??= Netdisk123State._();

  final Netdisk123Client client = Netdisk123Client();
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? username; // 登录账号，仅本机展示
  bool _ready = false;

  Netdisk123State._();

  bool get isLoggedIn => client.hasLogin;

  /// 应用启动时恢复登录态；token 失效且记住密码时自动重登
  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final token = await _read(_kToken);
      final password = await _read(_kPassword);
      username = await _read(_kUsername);
      client.setToken(token);
      if (username != null && password.isNotEmpty) {
        client.setCredentials(username!, password);
      }
      if (token.isNotEmpty) {
        final ok = await client.validate();
        if (!ok && password.isNotEmpty && username != null) {
          AppLogger.I.i('netdisk123', 'token 失效，使用记住的密码自动重登');
          final err = await client.signIn(username!, password);
          if (err == null) await _persist();
        }
      }
    } catch (e) {
      AppLogger.I.e('netdisk123', '恢复登录态失败: $e');
    }
  }

  /// 密码登录
  Future<String?> login(String account, String password) async {
    final err = await client.signIn(account, password);
    if (err != null) {
      AppLogger.I.e('netdisk123', '登录失败: $err');
      return err;
    }
    username = account;
    await _persist();
    AppLogger.I.i('netdisk123', '登录成功 account=$account');
    notifyListeners();
    return null;
  }

  /// 扫码登录成功：写入 token（不记住密码）
  Future<void> loginByToken(String token) async {
    client.setToken(token);
    username = await _read(_kUsername); // 复用既有账号展示（若有）
    await _write(_kToken, token);
    AppLogger.I.i('netdisk123', '扫码登录成功');
    notifyListeners();
  }

  Future<void> logout() async {
    client.clear();
    username = null;
    for (final k in [_kToken, _kPassword, _kUsername]) {
      try {
        await _secure.delete(key: k);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(k);
      } catch (_) {}
    }
    AppLogger.I.i('netdisk123', '已退出登录');
    notifyListeners();
  }

  Future<void> _persist() async {
    await _write(_kToken, client.token);
    await _write(_kPassword, client.passwordSnapshot);
    if (username != null) await _write(_kUsername, username!);
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
