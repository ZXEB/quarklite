#include "flutter_window.h"

#include <cwchar>
#include <optional>
#include <shellapi.h>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 注册窗口控制通道：Dart 端通过它决定「关闭窗口」是退出还是最小化。
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "quarklite.com/window",
          &flutter::StandardMethodCodec::GetInstance());
  // 窗口级文件拖放通道：Windows 上把拖入的路径（文件/文件夹，可多个）
  // 转成 EncodableList 发给 Dart 端直接上传。
  drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "quarklite.com/drop",
          &flutter::StandardMethodCodec::GetInstance());
  // 接受文件拖放（WM_DROPFILES 来自 Explorer），不 InitializeShellHook。
  DragAcceptFiles(GetHandle(), TRUE);
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "minimize") {
          // 最小化到系统托盘：隐藏窗口（任务栏消失），托盘图标常驻，下载继续。
          // 托盘图标创建失败时回退到最小化到任务栏，保证功能可用。
          if (tray_added_) {
            ShowWindow(GetHandle(), SW_HIDE);
          } else {
            ShowWindow(GetHandle(), SW_MINIMIZE);
          }
          result->Success();
        } else if (method == "exit") {
          // 真正退出：销毁窗口 → WM_DESTROY → 结束消息循环
          DestroyWindow(GetHandle());
          result->Success();
        } else if (method == "restore") {
          // 恢复窗口（最小化/隐藏状态回到正常）
          RestoreFromTray();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // 添加系统托盘图标：常驻，供「最小化到托盘」后恢复/退出。
  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"Quarklite");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
  if (tray_added_) {
    // 声明使用 Vista+ 通知图标行为（否则托盘点击消息可能收不到）
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_);
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 移除系统托盘图标，避免残留
  if (tray_added_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_added_ = false;
  }
  // 关闭拖放接收
  DragAcceptFiles(GetHandle(), FALSE);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RestoreFromTray() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DROPFILES: {
      // 拖放文件/文件夹：收集路径并发给 Dart（一次最多 kMaxDropPaths 项）。
      // EncodableValue 的字符串槽位是 UTF-8 std::string，需把宽字符路径转码。
      HDROP hdrop = reinterpret_cast<HDROP>(wparam);
      UINT count = DragQueryFileW(hdrop, 0xFFFFFFFF, nullptr, 0);
      count = count > kMaxDropPaths ? kMaxDropPaths : count;
      std::vector<flutter::EncodableValue> paths;
      for (UINT i = 0; i < count; i++) {
        const UINT len = DragQueryFileW(hdrop, i, nullptr, 0);
        if (len == 0) continue;
        std::wstring wpath(len, L'\0');
        DragQueryFileW(hdrop, i, wpath.data(), len + 1);
        const int utf8Len = WideCharToMultiByte(
            CP_UTF8, 0, wpath.c_str(), static_cast<int>(len), nullptr, 0,
            nullptr, nullptr);
        std::string utf8(utf8Len > 0 ? utf8Len : 0, '\0');
        if (utf8Len > 0) {
          WideCharToMultiByte(CP_UTF8, 0, wpath.c_str(),
                              static_cast<int>(len), utf8.data(), utf8Len,
                              nullptr, nullptr);
        }
        paths.emplace_back(flutter::EncodableValue(std::move(utf8)));
      }
      DragFinish(hdrop);
      if (drop_channel_ != nullptr && !paths.empty()) {
        drop_channel_->InvokeMethod(
            "onDropped",
            std::make_unique<flutter::EncodableValue>(
                flutter::EncodableValue(std::move(paths))));
      }
      return 0;
    }
    case WM_CLOSE:
      // 不直接关闭：交给 Dart 端按用户设置决定「最小化」还是「退出」。
      // Dart 端通过 quarklite.com/window 通道调用 minimize / exit。
      if (window_channel_ != nullptr) {
        window_channel_->InvokeMethod("onCloseRequested", nullptr);
        return 0;
      }
      break;
    case kTrayCallbackMessage:
      // 系统托盘图标回调：单击恢复窗口，右键弹出菜单（打开 / 退出）
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          break;
        case WM_RBUTTONUP: {
          HMENU menu = CreatePopupMenu();
          AppendMenuW(menu, MF_STRING, 1, L"打开 Quarklite");
          AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
          AppendMenuW(menu, MF_STRING, 2, L"退出");
          // 先置前再弹菜单，否则菜单可能不响应点击
          SetForegroundWindow(hwnd);
          POINT pt;
          GetCursorPos(&pt);
          const int cmd = TrackPopupMenu(
              menu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, nullptr);
          DestroyMenu(menu);
          if (cmd == 1) {
            RestoreFromTray();
          } else if (cmd == 2) {
            if (tray_added_) {
              Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
              tray_added_ = false;
            }
            DestroyWindow(hwnd);
          }
          break;
        }
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
