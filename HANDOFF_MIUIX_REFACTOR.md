# Kuake（Quarklite）Miuix 全量 UI 重构 —— 交接提示词

> 用法：把本文件全部内容作为新会话的提示粘贴给 AI，即可无缝续接。

## 项目背景
- Flutter 项目，夸克网盘不限速下载客户端 `Kuake`/`quarklite`，仓库在 `D:\zm\工作区\coding\kuake`，git 分支 main。
- **重要**：本机无 Flutter SDK / 无 dart，无法本地编译/analyze。所有 Dart 改动只能靠「读 flutter_miuix 源码 + 静态括号检查」来压编译错误。你写完也不要跑 build，用户会自己构建验收。
- 用户偏好：不生成 C 盘任何文件、不跑 CI、改完用户自行提交 GitHub。
- 当前 `flutter_miuix` 版本 = **1.1.1**（严格按这个版本 API 写）。
- 源码包已解压在 `third_party/lib/`（下载自 pub 镜像，含完整 `miuix.dart` 导出和每个组件源码，**务必用 `grep`/`Read` 核对真实签名再写代码**）。

## 已完成并通过的第一批改动（保留，勿回退）
1. **托盘乱码修复**：`windows/CMakeLists.txt` 的 `APPLY_STANDARD_SETTINGS` 里 `target_compile_options` 加了 `/utf-8`。
2. **单实例限制**：`windows/runner/main.cpp` `wWinMain` 开头用 `CreateMutexW(L"Quarklite_SingleInstance_Mutex")` + `ERROR_ALREADY_EXISTS` + `FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW",...)` + `SetForegroundWindow`。
3. **网盘官方 logo**：`assets/icons/{quark,xunlei,netdisk123}.png`（128px，PIL 转的）；`pubspec.yaml` 加了 `assets: - assets/icons/`；新增 `lib/widgets/netdisk_logo.dart`（`NetdiskProvider` 枚举 + `NetdiskLogo` widget）；`drive_hub_page.dart` 和 `me_page.dart` 已用 `NetdiskLogo`。
4. **上传真正暂停/继续 + 批量操作**：`lib/state/upload_manager.dart` 加了 `UploadStatus.paused`、`QuarkUploadSession`/etag 断点续传字段、`pause/resume/pauseAll/resumeAll/removeAll`；分片循环按已传字节续传。`uploads_page.dart` 支持长按多选 + 底部批量暂停/继续/删除。`downloads_page.dart` 也加了长按多选 + 底部批量操作栏。

## 当前正在做的：全量 UI 重构为 Miuix（用户已批准方案）
用户要求：**不要表面换皮，整个 UI 打乱用 flutter_miuix 组件重写所有功能**，包括返回动画。方案要点：
- 根框架换 `MiuixScaffold` + `snackbarHost` + `popupHost`。
- 所有弹窗/底部菜单/SnackBar 用 Miuix 组件（`MiuixOverlayDialog`/`MiuixOverlayBottomSheet`/`MiuixSnackbar`）。
- 采用 Miuix 风格页转场（含返回动画）。
- 一次性交付全部 20+ 页面。

### 已改完的文件（本轮新写）
- `lib/theme/app_theme.dart`：新增 `MiuixPageTransitionsBuilder`（右下→左上淡入淡出+缩放返回动画）；`AppTheme.light()` 仅作 Material 文字/转场基座；`AppColors` 保留为细节常量；`UIStyle`/`AppStyleState` 是兼容存根。
- `lib/app.dart`：根用 `MiuixThemeController(colorSchemeMode: light)` 包 `MaterialApp`；新增 `SnackbarRegistry.globalHost` 全局 Snackbar host；`RootPage`/`_BootView` 用 `MiuixScaffold` + `MiuixSnackbarHost`；底栏仍是 `MiuixNavigationBar`。**注意**：`lib/app.dart` 顶部 import 了 `lib/widgets/miuix_common.dart` 但当前并未用到（可保留或删）。
- `lib/widgets/miuix_common.dart`（新增）：`MiuixToast.show(context?)`、`confirmMiuix(...)` 返回 `Future<bool>`、`MiuixActionSheet.show<T>` 底部操作单、`MiuixStatusChip`、`MiuixFilterTabs`。

### 下一步（你来完成）
1. **逐页改造成 Miuix**，替换掉这些 Material 用法（全项目当前仍大量存在，Explorer 已盘点过）：
   - `Scaffold + AppBar` → `MiuixScaffold`（注意它的 `content:` 是一个**builder**，签名是 `Widget Function(EdgeInsets contentPadding)`，内容要自行应用 padding）+ `MiuixTopAppBar`/`MiuixSmallTopAppBar`。
   - `showDialog + AlertDialog` → `confirmMiuix(context, title:, content:, confirmText:, danger:)` 返回 `Future<bool>`。
   - `showModalBottomSheet + ListTile`（文件操作菜单约 6 处）→ `MiuixActionSheet.show<T>()`。
   - `ScaffoldMessenger.showSnackBar` 的 `_toast/_toast(...)` → `MiuixToast.show(msg)`。
   - `RefreshIndicator` → `MiuixPullToRefresh(isRefreshing:, onRefresh:, child:)`。
   - `Text/Icon` → `MiuixText`/`MiuixIcon(icon:)`；`TextButton/FilledButton/IconButton` → `MiuixTextButton(text, onPressed:)`/`MiuixButton`/`MiuixIconButton`（注意 `MiuixTextButton` **是位置参数** `MiuixTextButton(text, {onPressed,...})`）。
   - `MiuixCard` 已有多处被用，可直接沿用。
   - 缩进处注意：`MiuixText` 的 `color`、`fontSize` 是可选命名参数。
2. **涉及页面清单**（`lib/pages/` 全部）：
   - 核心：`downloads_page.dart`、`uploads_page.dart`、`drive_page.dart`、`drive_hub_page.dart`、`me_page.dart`、`parse_page.dart`、`parse/share_files_page.dart`。
   - 次要：`drive/album_page.dart`、`drive/search_page.dart`、`drive/move_target_page.dart`、`drive/netdisk123_drive_page.dart`、`drive/netdisk123_accounts_page.dart`、`drive/netdisk123_pay_page.dart`、`drive/xunlei_drive_page.dart`、`login/login_page.dart`、`login/netdisk123_login_page.dart`、`login/xunlei_login_page.dart`、`login/xunlei_review_page.dart`。
   - `lib/widgets/`：`file_icon.dart`、`empty_view.dart`、`storage_capacity.dart`、`file_list_anim.dart` 也一并 Miuix 化（接口 props 不变，调用方不用改）。
3. **登录页 TabBar/TabBarView** → `MiuixTabRow`（构造：`tabs: List<String>, selectedTabIndex:, onTabSelected:`）；登录输入框 `TextField` → `MiuixTextField(controller:, hint... )`。
4. **改完自查**：全 `lib/` 不应再出现 `AlertDialog`/`SimpleDialog`/`showModalBottomSheet`/`ScaffoldMessenger`/`RefreshIndicator`/`TabBar`（`MiuixSnackbar` 内部自己用 Material 不算）。跑 python 括号/TAB 静态检查。

## flutter_miuix 1.1.1 关键 API 事实（务必核对源码，别凭记忆）
- **`MiuixScaffold`**：参数 `topBar, bottomBar, floatingActionButton, snackbarHost, popupHost, containerColor, contentWindowInsets, required Widget Function(EdgeInsets) content`。`content` 是 builder，收到的 EdgeInsets 要自己应用（如 `Padding` 包裹）。
- **`MiuixThemeController`**：`colorSchemeMode: MiuixColorSchemeMode.light`（或 system/monet*）、`lightColors/darkColors`、`keyColor`。`MiuixSystemTheme` 也能用。取色 `MiuixTheme.of(context).colors`。
- **`MiuixColors` 色板字段**（写颜色时用）：`primary, onPrimary, primaryVariant, onPrimaryVariant, secondary, onSecondary, secondaryVariant, onSecondaryVariant, background, onBackground, onBackgroundVariant, surface, onSurface, surfaceVariant, onSurfaceSecondary, onSurfaceVariantSummary, onSurfaceContainer, surfaceContainer, surfaceContainerHigh/Highest, outline, dividerLine, error, onError, errorContainer, onErrorContainer, windowDimming, 等`（共 53 个）。
- **`MiuixText(text, {color, fontSize, fontWeight, maxLines, overflow, textAlign, style, ...})`** — text 是位置参数。
- **`MiuixTextButton(String text, {onPressed, enabled, cornerRadius, minWidth, minHeight, colors, insideMargin, textStyle})`** — text 位置参数；onPressed 可空。
- **`MiuixButton({required onPressed, required child, enabled, cornerRadius, minWidth, minHeight, colors, insideMargin})`** — child 是任意 Widget。
- **`MiuixIconButton({required onPressed, required child, enabled, backgroundColor, cornerRadius, minWidth, minHeight})`**。
- **`MiuixIcon({icon, vector, child, tint, size, contentDescription})`** — icon(Material IconData) / vector / child 三选一（assert）。
- **`MiuixCard({cornerRadius, insideMargin, colors, onPressed, onLongPress, feedbackType, child})`**。
- **`MiuixButtonColors({required color, disabledColor, contentColor, disabledContentColor})`** — 给按钮上色用。
- **`MiuixSnackbarHostState.showSnackbar(String, {actionLabel, withDismissAction, duration})` → Future<MiuixSnackbarResult>`**；`MiuixSnackbarHost({required state})`。
- **`MiuixOverlayDialog({required show, title, summary, backgroundColor, onDismissRequest, onDismissFinished, maxWidth, largeScreen, cornerRadius, required content})`** —— 是**声明式**组件，`show` 用 `MiuixPopupController`（`visible:false` 初始化 → 后帧 `controller.show()`）驱动，靠 `MiuixPopupHost`/`MiuixScaffold.popupHost` 渲染。**它不是 `showDialog` 那样的命令式**。所以我的 `confirmMiuix` 用 `showDialog` 包住它再 `Navigator.pop`，行为等价旧对话框（保留 Navigator 语义）。如果要更彻底 Miuix，可改为直接放进某页面让其注册——但你改页面时**保持 `confirmMiuix` 的 `Future<bool>` 接口不变**，内部实现可调。
- **`MiuixOverlayBottomSheet({required show, title, startAction, endAction, backgroundColor, onDismissRequest, onDismissFinished, allowDismiss, content})`** —— 同样声明式（`show` 控制）。我没有在每个页面用它的声明式形态，而是保留了 `showModalBottomSheet`+`MiuixActionSheetView` 承接底部菜单；如果你想完全去 Material 底部弹层，可改成用 `MiuixPopupController` + `MiuixOverlayBottomSheet` 嵌入页面。
- **`MiuixPopupController`**：`visible`（bool getter/setter）、`show()/dismiss()/toggle()`。注册靠 `MiuixPopupScope` + `MiuixDialogLayout(content: builder)` 或 `MiuixPopupLayout`，由 `MiuixPopupHost` 绘制。根 `MiuixScaffold` 会自动放一个 `MiuixPopupHost`（`widget.popupHost ?? const MiuixPopupHost()`）。
- **`MiuixPullToRefresh({required isRefreshing, required onRefresh, required child, contentPadding, ...})`**。
- **`MiuixTabRow({required tabs(List<String>), required selectedTabIndex, required onTabSelected, height, ...})`**。
- **`MiuixLinearProgressIndicator({progress(0..1 or null), height})`**、`MiuixCircularProgressIndicator({progress, size=30})`、`MiuixInfiniteProgressIndicator({color, size})`。
- **`MiuixSwitch({required value, required onChanged, enabled})`**、`MiuixCheckbox({required value, onChanged, enabled})`。
- **`MiuixHorizontalDivider({thickness, color})`**、**`MiuixVerticalDivider`**。
- **`MiuixSmallTitle(String text, {textColor, insideMargin})`** — text 位置参数。
- **`MiuixSurface({color, contentColor, cornerRadius, squircleEnabled, border, shadowElevation, child})`**。
- **`MiuixBadge({containerColor, contentColor, child})`**、**`MiuixBadgedBox`**。
- **`MiuixNavigationBar({required children(2-5), color, colors, showDivider, mode})`**；`MiuixNavigationBarItem({required selected, onPressed, icon, label, labelWidget, enabled, badge})`。
- **`MiuixPressable({required onPressed, required child, enabled, feedbackType: none|sink|tilt, borderRadius, onLongPress, ...})`**。
- **`MiuixBreadcrumbBar`** 存在，可做网盘页面包屑。
- **图标**：`Icons.*`（Material）可直接传给 `MiuixIcon(icon:)`；也可用 `MiuixIcons.basic.*` / `MiuixIcons.extended.*`（矢量的传 `vector:`）。

## 静态检查脚本（写完后跑）
用 python 对每个 dart 文件做括号配平 + TAB 缩进检查（避免明显的语法/缩进错）。参考之前用的脚本逻辑：逐字符跳过字符串/行注释/块注释，遇 `(` 深度+1、`)` 深度-1，并检查缩进里没有 tab。改完补给用户一份「已改动文件 + 需用户自己编译验证」的清单。

## 改完不跑 build
- 不 `flutter build`/`flutter test`/`flutter analyze`（没 SDK）。
- 把 `third_party/`（flutter_miuix 源码）是否入库的决定权留给用户；建议不入 git（可 `.gitignore`），但若用户需要离线 API 参考可保留。
- 最后给用户：完整改动清单 + 请其本机构建验收 + 自行提交 GitHub。
