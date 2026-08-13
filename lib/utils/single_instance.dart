import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows 单实例互斥锁。
///
/// 多个应用实例同时运行时，各自的引擎启动流程都会 taskkill 掉所有
/// gopeed.exe（清残留进程），导致互相杀掉对方刚启动成功的引擎，
/// 形成「启动成功→被杀→自动重启→再被杀」的死循环，最终下载报
/// 「引擎未正常启动」。用命名 Mutex 保证同一时刻只有一个实例运行。
class SingleInstance {
  static Pointer<NativeType>? _mutex;

  /// 尝试获取单实例锁。返回 true 表示当前是唯一实例，可继续启动；
  /// 返回 false 表示已有实例在运行（调用方应提示用户并退出）。
  static bool acquire() {
    if (kIsWeb || !Platform.isWindows) return true;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final createMutex = kernel32.lookupFunction<
          Pointer<NativeType> Function(
              Pointer<NativeType>, Int32, Pointer<Uint16>),
          Pointer<NativeType> Function(
              Pointer<NativeType>, int, Pointer<Uint16>)>('CreateMutexW');
      final getLastError =
          kernel32.lookupFunction<Int32 Function(), int Function()>(
              'GetLastError');

      const name = r'Local\Quarklite_SingleInstance';
      final units = name.codeUnits;
      final namePtr = malloc<Uint16>(units.length + 1);
      for (var i = 0; i < units.length; i++) {
        namePtr[i] = units[i];
      }
      namePtr[units.length] = 0;
      _mutex = createMutex(Pointer.fromAddress(0), 0, namePtr);
      malloc.free(namePtr);
      // ERROR_ALREADY_EXISTS = 183
      return getLastError() != 183;
    } catch (_) {
      // 获取锁失败不阻塞启动，由引擎自愈逻辑兜底
      return true;
    }
  }

  /// 已有实例运行时弹窗提示（Windows）
  static void showAlreadyRunning() {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final messageBox = user32.lookupFunction<
          Int32 Function(
              Pointer<NativeType>, Pointer<Uint16>, Pointer<Uint16>, Uint32),
          int Function(
              Pointer<NativeType>, Pointer<Uint16>, Pointer<Uint16>,
              int)>('MessageBoxW');
      final text = toUtf16(
          'Quarklite 已经在运行。\n\n请勿同时打开多个窗口：多个实例会互相干扰下载引擎（引擎进程被反复终止，导致下载失败）。');
      final caption = toUtf16('Quarklite');
      messageBox(
          Pointer.fromAddress(0), text, caption, 0x10 /* MB_ICONERROR */);
      malloc.free(text);
      malloc.free(caption);
    } catch (_) {}
  }

  static Pointer<Uint16> toUtf16(String s) {
    final units = s.codeUnits;
    final p = malloc<Uint16>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    return p;
  }

  /// 释放互斥锁句柄（进程退出时系统也会自动释放）
  static void release() {
    final m = _mutex;
    if (m == null) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final closeHandle = kernel32.lookupFunction<
          Int32 Function(Pointer<NativeType>),
          int Function(Pointer<NativeType>)>('CloseHandle');
      closeHandle(m);
    } catch (_) {}
    _mutex = null;
  }
}