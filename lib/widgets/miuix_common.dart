import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../app.dart';
import '../theme/app_theme.dart';

/// 全局 Miuix Snackbar 便捷入口。
class MiuixToast {
  MiuixToast._();
  static void show(String msg, {String? actionLabel, VoidCallback? onAction}) {
    final host = SnackbarRegistry.globalHost;
    if (actionLabel != null && onAction != null) {
      host.showSnackbar(msg, actionLabel: actionLabel).then((r) {
        if (r == MiuixSnackbarResult.actionPerformed) onAction();
      });
    } else {
      host.showSnackbar(msg);
    }
  }
}

/// 便捷确认对话框：返回 [Future<bool>]，true 表示用户确认。
Future<bool> confirmMiuix(
  BuildContext context, {
  required String title,
  required String content,
  String confirmText = '确定',
  bool danger = false,
}) {
  final completer = Completer<bool>();
  showDialog<bool>(
    context: context,
    builder: (_) => _MiuixConfirmDialog(
      title: title,
      content: content,
      confirmText: confirmText,
      danger: danger,
      completer: completer,
    ),
  );
  return completer.future;
}

/// 基于 MiuixOverlayDialog 的确认框（挂在 Navigator 之上，行为等同旧对话框）。
/// 仅在确认/取消或点遮罩关闭时返回。
/// 渲染依赖根 Scaffold 的 popupHost，故包裹一层 MiuixDialogLayout：当宿主
/// popupHost 缺失时（如未经过 RootPage 的场景），弹窗通过 Dialog 兜底显示。
class _MiuixConfirmDialog extends StatefulWidget {
  final String title;
  final String content;
  final String confirmText;
  final bool danger;
  final Completer<bool> completer;

  const _MiuixConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    required this.danger,
    required this.completer,
  });

  @override
  State<_MiuixConfirmDialog> createState() => _MiuixConfirmDialogState();
}

class _MiuixConfirmDialogState extends State<_MiuixConfirmDialog> {
  final MiuixPopupController _controller = MiuixPopupController(visible: false);
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.show());
  }

  void _finish(bool ok) {
    if (_closed) return;
    _closed = true;
    _controller.dismiss();
    widget.completer.complete(ok);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final dangerColor = widget.danger ? AppColors.red : colors.primary;
    final confirmColors = MiuixButtonColors(
      color: dangerColor,
      disabledColor: dangerColor,
      contentColor: Colors.white,
      disabledContentColor: Colors.white,
    );
    return MiuixDialogLayout(
      controller: _controller,
      renderInRoot: false,
      content: (_) => MiuixOverlayDialog(
        show: true,
        onDismissRequest: () => _finish(false),
        title: widget.title,
        content: MiuixDismissScope(
          onDismissRequest: () => _finish(false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MiuixText(
                widget.content,
                textAlign: TextAlign.center,
                color: colors.onSurfaceSecondary,
                fontSize: 14,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: MiuixTextButton(
                      '取消',
                      onPressed: () => _finish(false),
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MiuixTextButton(
                      widget.confirmText,
                      onPressed: () => _finish(true),
                      colors: confirmColors,
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miuix 底部操作菜单（替代 showModalBottomSheet + ListTile）。
/// 内容由 [MiuixActionItem] 组成；返回后由调用方决定关闭方式。
class MiuixActionSheet {
  MiuixActionSheet._();

  /// 弹出底部操作单。返回所选动作值；取消返回 null。
  /// [actions] 为 (icon, text, value, {color}) 列表。
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<({IconData icon, String text, T value, Color? color})> actions,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MiuixActionSheetView(title: title, actions: actions),
    );
  }
}

class MiuixActionSheetView<T> extends StatelessWidget {
  final String title;
  final List<({IconData icon, String text, T value, Color? color})> actions;

  const MiuixActionSheetView({
    super.key,
    required this.title,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixSurface(
      color: colors.surfaceContainer,
      cornerRadius: 20,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: MiuixText(title,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 4),
            for (final a in actions)
              MiuixPressable(
                onPressed: () => Navigator.of(context).pop(a.value),
                borderRadius: BorderRadius.circular(10),
                feedbackType: MiuixPressFeedbackType.sink,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      MiuixIcon(
                          icon: a.icon, size: 22, tint: a.color ?? colors.onBackground),
                      const SizedBox(width: 16),
                      MiuixText(a.text,
                          fontSize: 15, color: a.color ?? colors.onBackground),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// 带单行输入的确认框（重命名/新建文件夹/下载目录等）。
/// 返回 [Future<String?>]：确认返回输入文本（已 trim），取消/关闭返回 null。
Future<String?> miuixInputDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String confirmText = '确定',
  String initialText = '',
}) {
  final completer = Completer<String?>();
  showDialog<String>(
    context: context,
    builder: (_) => _MiuixInputDialog(
      title: title,
      hint: hint,
      confirmText: confirmText,
      initialText: initialText,
      completer: completer,
    ),
  );
  return completer.future;
}

class _MiuixInputDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String confirmText;
  final String initialText;
  final Completer<String?> completer;

  const _MiuixInputDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.confirmText,
    required this.initialText,
    required this.completer,
  });

  @override
  State<_MiuixInputDialog> createState() => _MiuixInputDialogState();
}

class _MiuixInputDialogState extends State<_MiuixInputDialog> {
  final MiuixPopupController _controller = MiuixPopupController(visible: false);
  late final TextEditingController _field =
      TextEditingController(text: widget.initialText);
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.show());
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _finish(String? value) {
    if (_closed) return;
    _closed = true;
    _controller.dismiss();
    widget.completer.complete(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return MiuixDialogLayout(
      controller: _controller,
      renderInRoot: false,
      content: (_) => MiuixOverlayDialog(
        show: true,
        title: widget.title,
        onDismissRequest: () => _finish(null),
        content: MiuixDismissScope(
          onDismissRequest: () => _finish(null),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MiuixTextField(
                controller: _field,
                label: widget.hint ?? widget.title,
                useLabelAsPlaceholder: true,
                singleLine: true,
                autofocus: true,
                onSubmitted: (_) =>
                    _finish(_field.text.trim().isEmpty ? null : _field.text.trim()),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: MiuixTextButton(
                      '取消',
                      onPressed: () => _finish(null),
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MiuixTextButton(
                      widget.confirmText,
                      onPressed: () => _finish(
                          _field.text.trim().isEmpty ? null : _field.text.trim()),
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单选列表选择框（线程数/并发数/关闭方式等），替代旧 `SimpleDialog`。
/// 返回所选值 [T]；取消返回 null。
Future<T?> miuixChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  required T current,
  String? hint,
}) {
  final completer = Completer<T?>();
  showDialog<T>(
    context: context,
    builder: (_) => _MiuixChoiceDialog(
      title: title,
      options: options,
      labelOf: labelOf,
      current: current,
      hint: hint,
      completer: completer,
    ),
  );
  return completer.future;
}

class _MiuixChoiceDialog<T> extends StatefulWidget {
  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final T current;
  final String? hint;
  final Completer<T?> completer;

  const _MiuixChoiceDialog({
    super.key,
    required this.title,
    required this.options,
    required this.labelOf,
    required this.current,
    required this.hint,
    required this.completer,
  });

  @override
  State<_MiuixChoiceDialog<T>> createState() => _MiuixChoiceDialogState<T>();
}

class _MiuixChoiceDialogState<T> extends State<_MiuixChoiceDialog<T>> {
  final MiuixPopupController _controller = MiuixPopupController(visible: false);
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.show());
  }

  void _finish(T? value) {
    if (_closed) return;
    _closed = true;
    _controller.dismiss();
    widget.completer.complete(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixDialogLayout(
      controller: _controller,
      renderInRoot: false,
      content: (_) => MiuixOverlayDialog(
        show: true,
        title: widget.title,
        onDismissRequest: () => _finish(null),
        content: MiuixDismissScope(
          onDismissRequest: () => _finish(null),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.hint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MiuixText(
                    widget.hint!,
                    color: AppColors.orange,
                    fontSize: 12,
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final o in widget.options)
                MiuixPressable(
                  onPressed: () => _finish(o),
                  borderRadius: BorderRadius.circular(10),
                  feedbackType: MiuixPressFeedbackType.sink,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      children: [
                        MiuixIcon(
                          icon: o == widget.current
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 20,
                          tint: o == widget.current
                              ? colors.primary
                              : colors.onSurfaceSecondary,
                        ),
                        const SizedBox(width: 12),
                        MiuixText(widget.labelOf(o),
                            fontSize: 14, color: colors.onSurfaceContainer),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态角标（普通胶囊），风格对齐 MiuixBadge。
Widget MiuixStatusChip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: MiuixText(text, fontSize: 11, color: color),
  );
}

/// 筛选 Tab（Miuix 风格胶囊）。
Widget MiuixFilterTabs({
  required List<String> tabs,
  required int selectedIndex,
  required ValueChanged<int> onSelected,
}) {
  return MiuixTabRow(
    tabs: tabs,
    selectedTabIndex: selectedIndex,
    onTabSelected: onSelected,
  );
}
