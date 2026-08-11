/// 健壮的类型转换工具（夸克接口字段类型不稳定，统一做宽松解析）
library;

int toInt(dynamic v, {int fallback = 0}) {
  if (v is num) return v.toInt();
  if (v == null) return fallback;
  final s = v.toString().trim();
  if (s.isEmpty) return fallback;
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? fallback;
}

String toStr(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  return v.toString();
}
