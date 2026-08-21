import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/quark_client.dart';
import '../../state/app_state.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
import '../drive/netdisk123_accounts_page.dart';
import '../drive/xunlei_drive_page.dart';
import 'share_files_page.dart';

enum ShareType { quark, netdisk123, xunlei, magnet, unknown }

class ParsePage extends StatefulWidget {
  const ParsePage({super.key});

  @override
  State<ParsePage> createState() => _ParsePageState();
}

class _ParsePageState extends State<ParsePage> {
  final _urlController = TextEditingController();
  final _pwdController = TextEditingController();
  final _btController = TextEditingController();

  bool _btMode = false;
  bool _parsing = false;
  List<Map<String, String>> _history = [];
  ShareType _detected = ShareType.unknown;
  String _detectedUrl = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _urlController.addListener(_onInputChanged);
    _btController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final raw = _btMode ? _btController.text : _urlController.text;
    final urls = _extractUrls(raw);
    final first = urls.isNotEmpty ? urls.first : raw.trim();
    final ty = _detectType(first);
    if (ty != _detected || first != _detectedUrl) setState(() { _detected = ty; _detectedUrl = first; });
  }
  ShareType _detectType(String s) {
    final v = s.trim().toLowerCase();
    if (v.startsWith('magnet:')) return ShareType.magnet;
    if (v.contains('quark.cn') || v.contains('pan.quark')) return ShareType.quark;
    if (v.contains('123pan') || v.contains('123865') || v.contains('123912') || v.contains('123684') || v.contains('www.123pan.com')) return ShareType.netdisk123;
    if (v.contains('xunlei') || v.contains('pan.xunlei')) return ShareType.xunlei;
    if (v.isEmpty) return ShareType.unknown;
    if (v.startsWith('http')) return ShareType.quark;
    return ShareType.unknown;
  }
  String _typeLabel(ShareType t) { switch(t){ case ShareType.quark: return '夸克分享'; case ShareType.netdisk123: return '123 网盘'; case ShareType.xunlei: return '迅雷分享'; case ShareType.magnet: return '磁力/BT'; case ShareType.unknown: return '自动识别'; } }
  IconData _typeIcon(ShareType t) { switch(t){ case ShareType.quark: return Icons.cloud_rounded; case ShareType.netdisk123: return Icons.cloud_upload_rounded; case ShareType.xunlei: return Icons.bolt_rounded; case ShareType.magnet: return Icons.wifi_tethering_rounded; case ShareType.unknown: return Icons.search_rounded; } }
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('parse_history');
    if (raw != null) {
      final list = (raw.split('\n'))
          .where((e) => e.isNotEmpty)
          .map((e) {
            final parts = e.split('\u0001');
            return {
              'url': parts.isNotEmpty ? parts[0] : '',
              'pwd': parts.length > 1 ? parts[1] : '',
              'time': parts.length > 2 ? parts[2] : '',
            };
          })
          .toList();
      if (mounted) setState(() => _history = list);
    }
  }

  Future<void> _saveHistory(String url, String pwd) async {
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    _history.removeWhere((e) => e['url'] == url);
    _history.insert(0, {'url': url, 'pwd': pwd, 'time': time});
    if (_history.length > 30) _history = _history.sublist(0, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'parse_history', _history.map((e) => e.values.join('\u0001')).join('\n'));
    if (mounted) setState(() {});
  }

  Future<void> _parse() async {
    if (_parsing) return;
    final app = AppState.I;
    if (!app.isLoggedIn) {
      _toast('请先登录夸克账号');
      return;
    }
    if (_btMode) {
      final magnet = _btController.text.trim();
      if (magnet.isEmpty) {
        _toast('请输入磁力链接或种子地址');
        return;
      }
      await _addBt(magnet);
      return;
    }

    final text = _urlController.text.trim();
    if (text.isEmpty) {
      _toast('请粘贴分享链接');
      return;
    }
    final urls = _extractUrls(text);
    if (urls.isEmpty) {
      _toast('未识别到有效链接');
      return;
    }

    final url = urls.first;
    if (url.startsWith('magnet:')) {
      await _addBt(url);
      return;
    }

    final parsed = QuarkClient.parseShareUrl(url);
    if (parsed.pwdId.isEmpty) {
      _toast('无法识别的分享链接');
      return;
    }
    final pwd = _pwdController.text.trim().isEmpty
        ? parsed.passcode
        : _pwdController.text.trim();

    setState(() => _parsing = true);
    try {
      final session = await app.quark.getShareToken(parsed.pwdId, pwd);
      final files = await app.quark.listShare(session, '0');
      await _saveHistory(url, pwd);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ShareFilesPage(
          session: session,
          initialFiles: files,
          initialName: '分享内容',
        ),
      ));
    } catch (e) {
      _toast('解析失败: $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _addBt(String magnet) async {
    setState(() => _parsing = true);
    try {
      final err = await DownloadService.addMagnet(url: magnet);
      if (err != null) throw Exception(err);
      _toast('已添加到下载队列');
    } catch (e) {
      _toast('添加失败: $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  List<String> _extractUrls(String text) {
    final re = RegExp(r'''https?://[^\s<>"'，。]+''');
    return re.allMatches(text).map((m) => m.group(0)!).toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    MiuixToast.show(msg);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _pwdController.dispose();
    _btController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final now = DateTime.now();
    const months = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiuixText('${now.day} / ${months[now.month - 1]}',
                          fontSize: 30, fontWeight: FontWeight.w800),
                      const SizedBox(height: 2),
                      MiuixText('下午好，解析分享链接',
                          color: colors.primary, fontSize: 14),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showHistory(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accentDeep,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        MiuixIcon(icon: Icons.history_rounded,
                            tint: colors.primary, size: 18),
                        const SizedBox(width: 6),
                        MiuixText('历史', color: colors.primary, fontSize: 13),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildInputCard(),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: MiuixText('解析记录',
                        color: colors.onSurfaceSecondary, fontSize: 13),
                  ),
                  ..._history.map(_buildHistoryItem),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentDeep,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: MiuixIcon(icon: Icons.paste_rounded,
                    tint: colors.primary, size: 19),
              ),
              const SizedBox(width: 10),
              MiuixText('粘贴内容',
                  color: colors.onSurfaceContainer,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              const Spacer(),
              MiuixText('等待粘贴链接',
                  color: colors.onSurfaceSecondary, fontSize: 12),
            ],
          ),
          const SizedBox(height: 14),
          MiuixTextField(
            controller: _urlController,
            maxLines: 3,
            minLines: 2,
            label: '粘贴夸克分享链接或包含链接的文本',
            useLabelAsPlaceholder: true,
          ),
          const SizedBox(height: 10),
          MiuixTextField(
            controller: _pwdController,
            label: '提取码（自动识别，可手动修改）',
            useLabelAsPlaceholder: true,
            singleLine: true,
          ),
          if (_btMode) ...[
            const SizedBox(height: 10),
            MiuixTextField(
              controller: _btController,
              maxLines: 2,
              minLines: 1,
              label: '磁力链接或种子文件地址（magnet: 开头）',
              useLabelAsPlaceholder: true,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: MiuixTextButton(
                  _btMode ? '关闭 BT 输入' : '+ 添加BT',
                  onPressed: () => setState(() => _btMode = !_btMode),
                  colors: _btMode
                      ? MiuixButtonColors(color: colors.primary, disabledColor: colors.primary, contentColor: Colors.white, disabledContentColor: Colors.white)
                      : MiuixButtonColors(color: colors.onSurfaceSecondary, disabledColor: colors.onSurfaceSecondary, contentColor: Colors.white, disabledContentColor: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixButton(
                  onPressed: _parsing ? null : _parse,
                  colors: MiuixButtonColors(
                    color: _parsing ? colors.primaryVariant : colors.primary,
                    disabledColor: _parsing ? colors.primaryVariant : colors.primary,
                    contentColor: Colors.white,
                    disabledContentColor: Colors.white,
                  ),
                  child: _parsing
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: MiuixCircularProgressIndicator(
                              size: 18,
                              colors: MiuixProgressIndicatorColors(
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                                backgroundColor: Colors.white24,
                              )),
                        )
                      : MiuixText('开始解析', color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, String> item) {
    final url = item['url'] ?? '';
    final pwd = item['pwd'] ?? '';
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MiuixCard(onPressed: () async { _urlController.text = url; _pwdController.text = pwd; await _parse(); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentDeep,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: MiuixIcon(icon: Icons.link_rounded,
                    tint: colors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MiuixText(url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: colors.onSurfaceContainer, fontSize: 13),
                    const SizedBox(height: 3),
                    MiuixText(
                      pwd.isEmpty ? '无提取码' : '提取码: $pwd',
                      color: colors.onSurfaceSecondary,
                      fontSize: 11,
                    ),
                  ],
                ),
              ),
              MiuixIconButton(
                onPressed: () => _removeHistory(url),
                child: MiuixIcon(icon: Icons.close_rounded,
                    tint: colors.onSurfaceSecondary, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeHistory(String url) async {
    setState(() {
      _history.removeWhere((e) => e['url'] == url);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'parse_history', _history.map((e) => e.values.join('\u0001')).join('\n'));
  }

  void _showHistory() {
    if (_history.isEmpty) {
      _toast('暂无解析记录');
      return;
    }
    MiuixActionSheet.show<String>(
      context,
      title: '解析记录',
      actions: [
        for (final e in _history)
          (
            icon: Icons.link_rounded,
            text: e['url'] ?? '',
            value: e['url'] ?? '',
            color: null,
          ),
      ],
    ).then((url) {
      if (url == null) return;
      _urlController.text = url;
      _pwdController.text = _history
          .firstWhere((e) => e['url'] == url,
              orElse: () => {'url': url, 'pwd': '', 'time': ''})['pwd'] ??
          '';
      _parse();
    });
  }
}
