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
