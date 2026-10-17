import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/netdisk123_client.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// 123 网盘下载通道诊断页。
///
/// 流量不足时用它一次打穿所有候选通道，直接看到服务端在哪一步拦、
/// 哪条通道还能返回直链。
class Netdisk123DiagPage extends StatefulWidget {
  final Netdisk123Client client;
  final Netdisk123File file;

  const Netdisk123DiagPage({
    super.key,
    required this.client,
    required this.file,
  });

  @override
  State<Netdisk123DiagPage> createState() => _Netdisk123DiagPageState();
}

class _Netdisk123DiagPageState extends State<Netdisk123DiagPage> {
  bool _running = true;
  String _error = '';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = '';
    });
    try {
      final rows = await widget.client.diagnose(widget.file);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  String _report() {
    final b = StringBuffer();
    b.writeln('123网盘通道诊断');
    b.writeln('文件: ${widget.file.name} (${formatBytes(widget.file.size)})');
    b.writeln('fileId: ${widget.file.id}');
    b.writeln('---');
    for (final r in _rows) {
      b.writeln('${r['name']} | code=${r['code']} | url=${r['hasUrl']}'
          '${r['urlHost'] != '' ? ' (${r['urlHost']})' : ''}'
          ' | ${r['ms']}ms | ${r['message']}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('通道诊断'),
        actions: [
          IconButton(
            tooltip: '复制结果',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _rows.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _report()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
          ),
          IconButton(
            tooltip: '重跑',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _running ? null : _run,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_running) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在逐个探测通道…', style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _headerCard(),
        const SizedBox(height: 8),
        for (final r in _rows) _rowCard(r),
      ],
    );
  }

  Widget _headerCard() {
    final okCount = _rows.where((r) => r['hasUrl'] == true).length;
    final color = okCount > 0 ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            okCount > 0 ? '$okCount 条通道能返回直链' : '所有通道都没返回直链',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.file.name} · ${formatBytes(widget.file.size)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _rowCard(Map<String, dynamic> r) {
    final hasUrl = r['hasUrl'] == true;
    final code = r['code'];
    final color = hasUrl
        ? AppColors.green
        : (code == 0 ? AppColors.orange : AppColors.red);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['name']}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                'code=${r['code']}',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${r['message']}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (hasUrl) ...[
            const SizedBox(height: 4),
            Text(
              '直链 host: ${r['urlHost']}',
              style: const TextStyle(fontSize: 12, color: AppColors.green),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${r['ms']} ms',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
