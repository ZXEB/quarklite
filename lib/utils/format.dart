String formatBytes(num bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  double v = bytes.toDouble();
  int i = -1;
  do {
    v /= 1024;
    i++;
  } while (v >= 1024 && i < units.length - 1);
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// 容量文本：`12.3 GB / 100 GB (12%)`；total 未知时仅显示已用。
String formatCapacity(num used, num total) {
  final totalV = total > 0 ? total.toDouble() : 0.0;
  final usedV = used > 0 ? used.toDouble() : 0.0;
  if (totalV <= 0) return formatBytes(usedV);
  final pct = (usedV / totalV * 100).clamp(0.0, 100.0).toDouble();
  return '${formatBytes(usedV)} / ${formatBytes(totalV)} '
      '(${pct.toStringAsFixed(pct >= 100 ? 0 : 1)}%)';
}

String formatSpeed(num bytesPerSec) {
  if (bytesPerSec <= 0) return '0 KB/s';
  return '${formatBytes(bytesPerSec)}/s';
}

String formatPercent(int done, int total) {
  if (total <= 0) return '--';
  return '${((done / total) * 100).clamp(0, 100).toStringAsFixed(1)}%';
}

String formatDateTime(int? millis) {
  if (millis == null || millis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
