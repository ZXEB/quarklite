#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>
#include <shellapi.h>

#include "resource.h"
#include "win32_window.h"

// 窗口级文件拖放：一次最多收集的路径数
constexpr int kMaxDropPaths = 2000;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Window control channel: Dart 决定关闭/最小化行为。
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;

  // 系统托盘图标（关闭窗口最小化到托盘后，从这里恢复/退出）。
  NOTIFYICONDATAW tray_icon_{};

  // 托盘图标是否已成功添加（失败时最小化回退到任务栏）。
  bool tray_added_ = false;

  // 托盘回调消息号（WM_APP + 1）。
  static constexpr UINT kTrayCallbackMessage = WM_APP + 1;

  // 窗口级文件拖放通道：Dart 端注册监听获取拖入的文件/文件夹路径。
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      drop_channel_;

  // 从托盘恢复窗口（SW_RESTORE + 置前）。
  void RestoreFromTray();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
