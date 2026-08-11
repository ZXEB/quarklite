enum GopeedStatus {
  ready,
  running,
  pause,
  wait,
  error,
  done;

  static GopeedStatus from(String? name) {
    switch (name) {
      case 'ready':
        return GopeedStatus.ready;
      case 'running':
        return GopeedStatus.running;
      case 'pause':
        return GopeedStatus.pause;
      case 'wait':
        return GopeedStatus.wait;
      case 'error':
        return GopeedStatus.error;
      case 'done':
        return GopeedStatus.done;
      default:
        return GopeedStatus.wait;
    }
  }

  String get label {
    switch (this) {
      case GopeedStatus.ready:
        return '等待中';
      case GopeedStatus.running:
        return '下载中';
      case GopeedStatus.pause:
        return '已暂停';
      case GopeedStatus.wait:
        return '排队中';
      case GopeedStatus.error:
        return '失败';
      case GopeedStatus.done:
        return '已完成';
    }
  }

  bool get isActive =>
      this == GopeedStatus.ready ||
      this == GopeedStatus.running ||
      this == GopeedStatus.wait;
}

class GopeedTask {
  final String id;
  final String name;
  final GopeedStatus status;
  final int size;
  final int downloaded;
  final int speed;
  final int createdAt;

  GopeedTask({
    required this.id,
    required this.name,
    required this.status,
    required this.size,
    required this.downloaded,
    required this.speed,
    required this.createdAt,
  });

  double get progress =>
      size <= 0 ? 0 : (downloaded / size).clamp(0.0, 1.0);

  factory GopeedTask.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>? ?? const {};
    final res = (json['meta'] as Map<String, dynamic>?)?['res']
            as Map<String, dynamic>? ??
        const {};
    return GopeedTask(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: GopeedStatus.from(json['status']?.toString()),
      size: (res['size'] as num?)?.toInt() ?? 0,
      downloaded: (progress['downloaded'] as num?)?.toInt() ?? 0,
      speed: (progress['speed'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}
