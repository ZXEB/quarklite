import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/permission.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
import 'album_page.dart';
import 'drive_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<QuarkFile> _results = [];
  String? _error;
  String _keyword = '';
  int _scope = 0; // 0=全部, 2=照片(内容搜索)

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(text));
  }

  Future<void> _search(String keyword) async {
    keyword = keyword.trim();
    if (keyword.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _error = null;
        _keyword = '';
      });
      return;
    }
    if (keyword == _keyword && _results.isNotEmpty && !_scopeChanged) {
      return;
    }
    _scopeChanged = false;
    setState(() {
      _keyword = keyword;
      _searching = true;
      _error = null;
    });
    try {
      List<QuarkFile> results;
      if (_scope == 2) {
        // 照片内容搜索：夸克 AI 识别标签（仅命中已被 AI 打标的照片）
        results = await AppState.I.quark
            .listCategoryImages(page: 1, size: 50, labels: keyword);
      } else {
        results =
            await AppState.I.quark.searchFiles(keyword, scope: _scope);
      }
      if (!mounted || keyword != _keyword) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || keyword != _keyword) return;
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  bool _scopeChanged = false;

  void _setScope(int scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _scopeChanged = true;
    });
    if (_keyword.isNotEmpty) {
      _search(_keyword);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '搜索',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
        bottomContent: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: MiuixTextField(
                    controller: _controller,
                    onChanged: _onChanged,
                    onSubmitted: _search,
                    label: '搜索文件名或照片内容',
                    useLabelAsPlaceholder: true,
                    singleLine: true,
                    leadingIcon: MiuixIcon(
                        icon: Icons.search_rounded,
                        tint: colors.onSurfaceSecondary,
                        size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MiuixIconButton(
                onPressed: () {
                  _controller.clear();
                  _search('');
                },
                child: MiuixIcon(icon: Icons.close_rounded, tint: colors.primary),
              ),
            ],
          ),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildScopeChip(0, '全部'),
                  const SizedBox(width: 10),
                  _buildScopeChip(2, '照片'),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeChip(int scope, String label) {
    final selected = _scope == scope;
    final colors = MiuixTheme.of(context).colors;
    return MiuixPressable(
      onPressed: () => _setScope(scope),
      borderRadius: BorderRadius.circular(16),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: MiuixText(
          label,
          fontSize: 12,
          color: selected ? Colors.white : colors.onSurfaceSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return BodySwitcher(child: const Center(child: MiuixCircularProgressIndicator()));
    }
    if (_error != null) {
      return BodySwitcher(
        child: EmptyView(
          icon: Icons.cloud_off_rounded,
          text: '搜索失败',
          subText: _error,
          action: MiuixTextButton('重试',
              onPressed: () => _search(_controller.text)),
        ),
      );
    }
    if (_keyword.isEmpty) {
      return BodySwitcher(
        child: const EmptyView(
          icon: Icons.search_rounded,
          text: '输入关键词搜索',
          subText: '「照片」模式按 AI 识别内容搜索（需照片已被夸克识别打标）',
        ),
      );
    }
    if (_results.isEmpty) {
      return BodySwitcher(
        child: EmptyView(
          icon: Icons.search_off_rounded,
          text: '没有找到相关内容',
          subText: _scope == 2 ? '照片内容搜索仅命中已被夸克 AI 识别打标的照片\n试试用「全部」按文件名搜索，或在相册中浏览' : null,
        ),
      );
    }
    final content = MiuixPullToRefresh(
      isRefreshing: _searching,
      onRefresh: () => _search(_keyword),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _results.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => StaggeredFileItem(index: i, child: _buildItem(_results[i])),
      ),
    );
    return BodySwitcher(child: content);
  }

  Widget _buildItem(QuarkFile file) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      onPressed: () {
        if (file.isDir) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DrivePage(
              initialDirFid: file.fid,
              initialName: file.fileName,
            ),
          ));
        } else if (file.isImage || file.isLivePhoto) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PhotoViewerPage(
              photos: [file],
              index: 0,
            ),
          ));
        } else {
          _showFileActions(file);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            FileIcon(isDir: file.isDir, name: file.fileName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: colors.onSurfaceContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  const SizedBox(height: 4),
                  MiuixText(
                    file.isDir ? '文件夹' : formatBytes(file.size),
                    color: colors.onSurfaceSecondary,
                    fontSize: 12,
                  ),
                ],
              ),
            ),
            MiuixIcon(
                icon: Icons.chevron_right_rounded,
                tint: colors.onSurfaceSecondary,
                size: 20),
          ],
        ),
      ),
    );
  }

  void _showFileActions(QuarkFile file) {
    MiuixActionSheet.show<String>(
      context,
      title: file.fileName,
      actions: [
        (icon: Icons.download_rounded, text: '立即下载', value: 'download', color: null),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'download':
          _downloadFile(file);
      }
    });
  }

  Future<void> _downloadFile(QuarkFile file) async {
    final ok = await ensureStoragePermission(context);
    if (!ok) return;
    if (!mounted) return;
    final err =
        await DownloadService.downloadQuarkFile(file.fid, fileName: file.fileName);
    if (!mounted) return;
    if (err != null) {
      MiuixToast.show(err);
      return;
    }
    MiuixToast.show('已加入下载队列');
    DownloadManager.I.startPolling();
  }
}
