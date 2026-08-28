import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../widgets/miuix_common.dart';
import 'playback_source.dart';

/// 在线播放器（media_kit / libmpv 内核）。
///
/// - 4K/高码率硬解（hwdec=auto-safe），HDR10/HLG 10-bit 解码 + 高质量色调映射
/// - 规格/源切换、音轨/字幕/倍速可选，直链过期自动重取并续播
/// - MD3 风格控件层：双击 ±10s、横向拖动 seek、垂直拖动音量、进度记忆、锁定
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.request, this.startAt});

  final PlaybackRequest request;

  /// 起始播放位置；为 null 时读取本地记忆。
  final Duration? startAt;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  NativePlayer get _native => _player.platform as NativePlayer;

  MediaVariant? _variant;
  bool _loading = true;
  String? _error;
  bool _retriedLink = false;
  int _openEpoch = 0;

  bool _controlsVisible = true;
  bool _locked = false;
  bool _fullscreen = false;
  Timer? _hideTimer;
  Timer? _flashTimer;
  String? _flashText;

  VideoParams? _videoParams;
  bool _dragging = false;
  double _dragTargetFraction = 0;
  Duration _lastSavedAt = Duration.zero;
  DateTime _lastUiRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hwdec = true;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<VideoParams>? _vpSub;
  StreamSubscription<String>? _errSub;
  StreamSubscription<Tracks>? _tracksSub;
  final List<StreamSubscription<dynamic>> _uiSubs = [];

  SharedPreferences? _prefs;
  final FocusNode _focusNode = FocusNode();

  static const _prefsPrefix = 'playback.pos.';
  static const _hideAfter = Duration(seconds: 3);

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _player = Player(
        configuration:
            const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
    _controller = VideoController(_player);
    unawaited(_applyMpvOptions());
    _bindStreams();
    unawaited(_initialOpen());
    if (!kIsWeb) unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _posSub?.cancel();
    _vpSub?.cancel();
    _errSub?.cancel();
    _tracksSub?.cancel();
    for (final s in _uiSubs) {
      s.cancel();
    }
    _savePosition(force: true);
    if (_fullscreen) _exitFullscreen();
    if (!kIsWeb) unawaited(WakelockPlus.disable());
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  // ---------------- engine setup ----------------

  Future<void> _applyMpvOptions() async {
    try {
      await _native.setProperty('hwdec', 'auto-safe');
      await _native.setProperty('cache', 'yes');
      await _native.setProperty('demuxer-readahead-secs', '30');
      await _native.setProperty('demuxer-max-bytes', '268435456');
      // HDR10/HLG 片源：10-bit 解码后高质量色调映射到 SDR 管线
      await _native.setProperty('tone-mapping', 'bt.2446a');
      await _native.setProperty('hdr-compute-peak', 'yes');
      await _native.setProperty('keep-open', 'yes');
      await _native.setProperty('force-window', 'no');
      await _native.setProperty('osc', 'no');
      // 网盘直链中断自动重连
      await _native.setProperty(
          'stream-lavf-o', 'reconnect=1,reconnect_at_eof=1,reconnect_streamed=1');
    } catch (_) {
      // 个别属性在特定构建下不可用，忽略
    }
  }

  void _bindStreams() {
    // 位置流：记忆进度 + 节流刷新 UI（进度条/时间）
    _posSub = _player.stream.position.listen((pos) {
      _maybeSavePosition(pos);
      final now = DateTime.now();
      if (!_dragging &&
          now.difference(_lastUiRefresh).inMilliseconds >= 250) {
        _lastUiRefresh = now;
        if (mounted) setState(() {});
      }
    });
    // 播放状态/时长/缓冲/倍速变化时刷新控件
    _uiSubs.add(_player.stream.playing.listen((_) {
      if (mounted) setState(() {});
    }));
    _uiSubs.add(_player.stream.duration.listen((_) {
      if (mounted) setState(() {});
    }));
    _uiSubs.add(_player.stream.buffer.listen((_) {
      if (mounted) setState(() {});
    }));
    _uiSubs.add(_player.stream.rate.listen((_) {
      if (mounted) setState(() {});
    }));
    _vpSub = _player.stream.videoParams.listen((vp) {
      if (mounted) setState(() => _videoParams = vp);
    });
    _errSub = _player.stream.error.listen((msg) => _onPlayError(msg));
    _tracksSub = _player.stream.tracks.listen((_) {
      if (mounted) setState(() {});
    });
  }

  // ---------------- open / retry ----------------

  Future<void> _initialOpen() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    var at = widget.startAt ?? Duration.zero;
    if (widget.startAt == null) {
      final saved = _prefs?.getInt('$_prefsPrefix${widget.request.provider}.${widget.request.fileId}') ?? 0;
      if (saved > 30000) at = Duration(milliseconds: saved);
    }
    await _open(at: at);
  }

  Future<void> _open({required Duration at, MediaVariant? variant}) async {
    final v = variant ?? _variant ?? widget.request.defaultVariant;
    final epoch = ++_openEpoch;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _variant = v;
      });
    }
    try {
      final resolved = await v.resolve();
      if (resolved.isEmpty) throw Exception('未获取到播放地址');
      if (epoch != _openEpoch) return;
      // 监听本次加载的首个有效时长（元数据解析完成），用于恢复进度
      final firstDuration = _player.stream.duration
          .firstWhere((d) => d > Duration.zero,
              orElse: () => Duration.zero)
          .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
      await _player.open(Media(resolved.url, httpHeaders: resolved.headers));
      final d = await firstDuration;
      if (epoch != _openEpoch) return;
      if (at > Duration.zero && d > Duration.zero && at < d - const Duration(seconds: 60)) {
        await _player.seek(at);
      }
      await _player.play();
      if (mounted) setState(() => _loading = false);
      _scheduleHide();
    } catch (e) {
      if (epoch != _openEpoch) return;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _onPlayError(String msg) {
    // 直链过期/失效：重取一次并从当前位置续播
    if (!_retriedLink && _variant != null && !_loading) {
      _retriedLink = true;
      final pos = _player.state.position;
      _flash('链接已刷新，继续播放');
      unawaited(_open(at: pos, variant: _variant));
      return;
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _error = msg.isEmpty ? '播放失败' : msg;
      });
    }
  }

  // ---------------- position memory ----------------

  void _maybeSavePosition(Duration pos) {
    if (_prefs == null || pos <= _lastSavedAt + const Duration(seconds: 5)) {
      return;
    }
    _lastSavedAt = pos;
    _savePosition(force: false, at: pos);
  }

  Future<void> _savePosition({required bool force, Duration? at}) async {
    final pos = at ?? _player.state.position;
    if (pos <= Duration.zero) return;
    final d = _player.state.duration;
    if (d > Duration.zero && pos > d - const Duration(seconds: 5)) return;
    try {
      await _prefs?.setInt(
          '$_prefsPrefix${widget.request.provider}.${widget.request.fileId}',
          pos.inMilliseconds);
    } catch (_) {}
  }

  // ---------------- fullscreen / system UI ----------------

  Future<void> _toggleFullscreen() async {
    if (_fullscreen) {
      _exitFullscreen();
    } else {
      _fullscreen = true;
      if (!kIsWeb && Platform.isWindows) {
        try {
          await windowManager.setFullScreen(true);
        } catch (_) {}
      } else if (_isMobile) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }
    if (mounted) setState(() {});
    _scheduleHide();
  }

  void _exitFullscreen() {
    _fullscreen = false;
    if (!kIsWeb && Platform.isWindows) {
      try {
        windowManager.setFullScreen(false);
      } catch (_) {}
    } else if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
  }

  // ---------------- playback actions ----------------

  Future<void> _togglePlay() async {
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) setState(() {});
    _scheduleHide();
  }

  Future<void> _seekRelative(Duration delta) async {
    final d = _player.state.duration;
    var target = _player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (d > Duration.zero && target > d) target = d;
    await _player.seek(target);
    _flash('${delta.isNegative ? '后退' : '快进'} ${delta.inSeconds.abs()}s');
    _scheduleHide();
  }

  Future<void> _setVolume(double v) async {
    final clamped = v < 0 ? 0.0 : (v > 100 ? 100.0 : v);
    await _player.setVolume(clamped);
    _flash('音量 ${clamped.toStringAsFixed(0)}');
    _scheduleHide();
  }

  // ---------------- controls visibility ----------------

  void _toggleControls() {
    if (_locked) return;
    if (_controlsVisible) {
      if (mounted) setState(() => _controlsVisible = false);
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    if (_locked) return;
    _hideTimer?.cancel();
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && !_dragging) setState(() => _controlsVisible = false);
    });
  }

  void _flash(String msg) {
    if (!mounted) return;
    setState(() => _flashText = msg);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flashText = null);
    });
  }

  // ---------------- sheets ----------------

  Future<void> _showSpecSheet() async {
    _hideTimer?.cancel();
    final action = await MiuixActionSheet.show<String>(
      context,
      title: '播放规格 · ${widget.request.fileName}',
      actions: [
        for (final v in widget.request.variants)
          (
            icon: v.key == _variant?.key
                ? Icons.check_circle_rounded
                : Icons.movie_outlined,
            text: v.key == _variant?.key ? '${v.label}（当前）' : v.label,
            value: 'variant:${v.key}',
            color: null,
          ),
        (
          icon: Icons.memory_rounded,
          text: '解码方式：${_hwdec ? '硬解（自动）' : '软解'}',
          value: 'hwdec',
          color: null,
        ),
      ],
    );
    if (!mounted || action == null) {
      _scheduleHide();
      return;
    }
    if (action.startsWith('variant:')) {
      final key = action.substring('variant:'.length);
      final v = widget.request.variants
          .firstWhere((e) => e.key == key, orElse: () => widget.request.defaultVariant);
      _retriedLink = false;
      await _open(at: _player.state.position, variant: v);
    } else if (action == 'hwdec') {
      // 硬解异常(花屏/卡顿)时可切软解，切换后从当前位置重新加载
      _hwdec = !_hwdec;
      await _native.setProperty('hwdec', _hwdec ? 'auto-safe' : 'no');
      _flash(_hwdec ? '已切换硬解，重新加载' : '已切换软解，重新加载');
      _retriedLink = false;
      await _open(at: _player.state.position, variant: _variant);
    }
    _scheduleHide();
  }

  Future<void> _showSpeedSheet() async {
    _hideTimer?.cancel();
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
    final current = _player.state.rate;
    final action = await MiuixActionSheet.show<double>(
      context,
      title: '播放倍速',
      actions: [
        for (final s in speeds)
          (
            icon: Icons.speed_rounded,
            text: s == current ? '${s}x（当前）' : '${s}x',
            value: s,
            color: null,
          ),
      ],
    );
    if (!mounted || action == null) {
      _scheduleHide();
      return;
    }
    await _player.setRate(action);
    if (mounted) setState(() {});
    _scheduleHide();
  }

  Future<void> _showAudioSheet() async {
    _hideTimer?.cancel();
    final tracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isEmpty) {
      _flash('该文件没有可选音轨');
      _scheduleHide();
      return;
    }
    final currentId = _player.state.track.audio.id;
    final action = await MiuixActionSheet.show<String>(
      context,
      title: '音轨',
      actions: [
        for (final t in tracks)
          (
            icon: Icons.audiotrack_rounded,
            text: _trackLabel(t.id, t.title, t.language, '音轨') +
                (t.id == currentId ? '（当前）' : ''),
            value: t.id,
            color: null,
          ),
      ],
    );
    if (!mounted || action == null) {
      _scheduleHide();
      return;
    }
    final picked = tracks.firstWhere((t) => t.id == action,
        orElse: () => tracks.first);
    await _player.setAudioTrack(picked);
    if (mounted) setState(() {});
    _scheduleHide();
  }

  Future<void> _showSubtitleSheet() async {
    _hideTimer?.cancel();
    final embedded = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final currentId = _player.state.track.subtitle.id;
    final action = await MiuixActionSheet.show<String>(
      context,
      title: '字幕',
      actions: [
        (
          icon: Icons.subtitles_off_rounded,
          text: '关闭字幕',
          value: 'off',
          color: null,
        ),
        for (final t in embedded)
          (
            icon: Icons.subtitles_rounded,
            text: _trackLabel(t.id, t.title, t.language, '内嵌字幕') +
                (t.id == currentId ? '（当前）' : ''),
            value: 'embed:${t.id}',
            color: null,
          ),
        for (var i = 0; i < widget.request.subtitles.length; i++)
          (
            icon: Icons.subtitles_rounded,
            text: '${widget.request.subtitles[i].name}（外挂）',
            value: 'ext:$i',
            color: null,
          ),
      ],
    );
    if (!mounted || action == null) {
      _scheduleHide();
      return;
    }
    if (action == 'off') {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } else if (action.startsWith('embed:')) {
      final id = action.substring('embed:'.length);
      final t = embedded.firstWhere((e) => e.id == id,
          orElse: () => embedded.first);
      await _player.setSubtitleTrack(t);
    } else if (action.startsWith('ext:')) {
      final i = int.tryParse(action.substring('ext:'.length)) ?? -1;
      if (i >= 0 && i < widget.request.subtitles.length) {
        final sub = widget.request.subtitles[i];
        unawaited(() async {
          try {
            final resolved = await sub.resolve();
            if (resolved.isEmpty) throw Exception('未获取到字幕地址');
            await _player.setSubtitleTrack(
                SubtitleTrack.uri(resolved.url, title: sub.name));
            _flash('已加载外挂字幕');
          } catch (e) {
            _flash('外挂字幕加载失败');
          }
        }());
      }
    }
    if (mounted) setState(() {});
    _scheduleHide();
  }

  String _trackLabel(String id, String? title, String? language, String fallback) {
    final parts = <String>[];
    if (title != null && title.isNotEmpty) parts.add(title);
    if (language != null && language.isNotEmpty) parts.add(language);
    if (parts.isEmpty) parts.add('$fallback #$id');
    return parts.join(' · ');
  }

  // ---------------- spec badge ----------------

  String? _specBadge() {
    final vp = _videoParams;
    final vt = _player.state.track.video;
    final w = vp?.w ?? vt.w ?? 0;
    if (w <= 0) return null;
    final h = vp?.h ?? vt.h ?? 0;
    final String res;
    if (w >= 3800) {
      res = '4K';
    } else if (w >= 2500) {
      res = '2K';
    } else if (h >= 1000) {
      res = '1080p';
    } else if (h >= 700) {
      res = '720p';
    } else {
      res = '$w×$h';
    }
    final parts = <String>[res];
    final codec = vt.codec ?? '';
    if (codec.isNotEmpty) parts.add(codec.toUpperCase());
    final fps = vt.fps;
    if (fps != null && fps >= 1) {
      parts.add('${fps.round()}fps');
    }
    final bitrate = vt.bitrate;
    if (bitrate != null && bitrate >= 1000000) {
      parts.add('${(bitrate / 1000000).round()}Mbps');
    }
    final pixfmt = vp?.pixelformat ?? '';
    if (pixfmt.contains('10le') || pixfmt.contains('12le') || pixfmt.contains('16le')) {
      parts.add('10bit+');
    }
    final prim = (vp?.primaries ?? '').toLowerCase();
    final gamma = (vp?.gamma ?? '').toLowerCase();
    if (prim.contains('bt.2020')) {
      if (gamma.contains('pq')) {
        parts.add('HDR10');
      } else if (gamma.contains('hlg')) {
        parts.add('HLG');
      } else {
        parts.add('广色域');
      }
    } else if (gamma.contains('pq') || gamma.contains('hlg')) {
      parts.add(gamma.contains('pq') ? 'HDR10' : 'HLG');
    }
    if ((vp?.hwPixelformat ?? '').isNotEmpty) parts.add('硬解');
    return parts.join(' · ');
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final duration = _player.state.duration;
    final position = _player.state.position;
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          _savePosition(force: true);
          if (_fullscreen) _exitFullscreen();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _controller, controls: NoVideoControls),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),
              if (_error != null) _buildErrorView(),
              _buildGestureLayer(),
              _buildDragPreview(),
              if (_flashText != null) _buildFlash(),
              _buildControlsOverlay(duration, position),
              if (_locked) _buildLockOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      unawaited(_togglePlay());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekRelative(const Duration(seconds: 10)));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekRelative(const Duration(seconds: -10)));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      unawaited(_setVolume(_player.state.volume + 5));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_setVolume(_player.state.volume - 5));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyF) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape && _fullscreen) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 44),
            const SizedBox(height: 12),
            const Text('播放失败',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    _retriedLink = false;
                    unawaited(_open(at: _player.state.position, variant: _variant));
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('返回'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 视频区手势层：单击切换控件、双击 ±10s、横向拖动 seek、纵向拖动音量（移动端）。
  Widget _buildGestureLayer() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        onDoubleTapDown: _locked ? null : (d) {
          final w = MediaQuery.sizeOf(context).width;
          unawaited(_seekRelative(
              d.localPosition.dx < w / 2
                  ? const Duration(seconds: -10)
                  : const Duration(seconds: 10)));
        },
        onHorizontalDragStart: _locked ? null : (d) {
          _dragging = true;
          _dragTargetFraction = _fractionOf(_player.state.position);
          if (mounted) setState(() {});
        },
        onHorizontalDragUpdate: _locked ? null : (d) {
          final duration = _player.state.duration;
          if (duration <= Duration.zero) return;
          final delta = d.delta.dx / MediaQuery.sizeOf(context).width;
          var f = _dragTargetFraction + delta;
          if (f < 0) f = 0;
          if (f > 1) f = 1;
          _dragTargetFraction = f;
          if (mounted) setState(() {});
        },
        onHorizontalDragEnd: _locked ? null : (d) async {
          final duration = _player.state.duration;
          _dragging = false;
          if (duration > Duration.zero) {
            final target = Duration(
                milliseconds:
                    (_dragTargetFraction * duration.inMilliseconds).round());
            await _player.seek(target);
          }
          if (mounted) setState(() {});
          _scheduleHide();
        },
        onVerticalDragUpdate: _locked || !_isMobile
            ? null
            : (d) {
                final w = MediaQuery.sizeOf(context).width;
                // 移动端纵向拖动调节音量（左右两侧均可）
                if (d.localPosition.dx < w * 0.25 || d.localPosition.dx > w * 0.75) {
                  unawaited(_setVolume(_player.state.volume - d.delta.dy));
                }
              },
      ),
    );
  }

  double _fractionOf(Duration pos) {
    final d = _player.state.duration;
    if (d <= Duration.zero) return 0;
    final f = pos.inMilliseconds / d.inMilliseconds;
    if (f < 0) return 0;
    if (f > 1) return 1;
    return f;
  }

  Widget _buildDragPreview() {
    if (!_dragging) return const SizedBox.shrink();
    final duration = _player.state.duration;
    final target = Duration(
        milliseconds: (_dragTargetFraction * duration.inMilliseconds).round());
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            '${_formatDuration(target)} / ${_formatDuration(duration)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildFlash() {
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_flashText ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(Duration duration, Duration position) {
    final visible = _controlsVisible && !_locked;
    final spec = _specBadge();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.fastOutSlowIn,
          child: Column(
            children: [
              // 顶栏：返回 / 片名+来源 / 规格徽标
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 24),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.request.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.request.providerLabel}'
                              '${_variant == null ? '' : ' · ${_variant!.label}'}',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (spec != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(spec,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // 底栏：进度条 + 时间 + 操作按钮
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(_formatDuration(position),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildProgressBar(duration, position)),
                          const SizedBox(width: 12),
                          Text(_formatDuration(duration),
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _togglePlay,
                            icon: Icon(
                              _player.state.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const Spacer(),
                          _controlButton(
                            icon: Icons.video_settings_rounded,
                            label: '规格',
                            onTap: _showSpecSheet,
                          ),
                          _controlButton(
                            icon: Icons.audiotrack_rounded,
                            label: '音轨',
                            onTap: _showAudioSheet,
                          ),
                          _controlButton(
                            icon: Icons.subtitles_rounded,
                            label: '字幕',
                            onTap: _showSubtitleSheet,
                          ),
                          _controlButton(
                            icon: Icons.speed_rounded,
                            label: '${_player.state.rate.toStringAsFixed(_player.state.rate == _player.state.rate.roundToDouble() ? 0 : 2)}x',
                            onTap: _showSpeedSheet,
                          ),
                          _controlButton(
                            icon: _fullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            label: _fullscreen ? '退出' : '全屏',
                            onTap: _toggleFullscreen,
                          ),
                          _controlButton(
                            icon: Icons.lock_outline_rounded,
                            label: '锁定',
                            onTap: () {
                              if (mounted) setState(() => _locked = true);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// MD3 风格细进度条（可点击/拖动，含缓冲长度指示）。
  Widget _buildProgressBar(Duration duration, Duration position) {
    final played =
        _dragging ? _dragTargetFraction : _fractionOf(position);
    final buffered = duration > Duration.zero
        ? (_player.state.buffer.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;
    return LayoutBuilder(builder: (context, constraints) {
      final barWidth = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) async {
          if (duration <= Duration.zero) return;
          var f = d.localPosition.dx / barWidth;
          if (f < 0) f = 0;
          if (f > 1) f = 1;
          await _player.seek(Duration(
              milliseconds: (f * duration.inMilliseconds).round()));
        },
        onHorizontalDragStart: duration <= Duration.zero ? null : (d) {
          _dragging = true;
          _dragTargetFraction = (d.localPosition.dx / barWidth).clamp(0.0, 1.0).toDouble();
          if (mounted) setState(() {});
        },
        onHorizontalDragUpdate: duration <= Duration.zero ? null : (d) {
          var f = _dragTargetFraction + d.delta.dx / barWidth;
          if (f < 0) f = 0;
          if (f > 1) f = 1;
          _dragTargetFraction = f;
          if (mounted) setState(() {});
        },
        onHorizontalDragEnd: duration <= Duration.zero ? null : (d) async {
          final target = Duration(
              milliseconds:
                  (_dragTargetFraction * duration.inMilliseconds).round());
          _dragging = false;
          await _player.seek(target);
          if (mounted) setState(() {});
          _scheduleHide();
        },
        child: SizedBox(
          height: 24,
          child: Center(
            child: SizedBox(
              width: barWidth,
              height: 12,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                      height: 3.5,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2))),
                  FractionallySizedBox(
                    widthFactor: buffered,
                    child: Container(
                        height: 3.5,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  FractionallySizedBox(
                    widthFactor: played,
                    child: Container(
                        height: 3.5,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  Positioned(
                    left: (barWidth - 11) * played,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLockOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_locked,
        child: Align(
          alignment: Alignment.topRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0.25,
                duration: const Duration(milliseconds: 220),
                child: IconButton(
                  onPressed: () {
                    if (mounted) setState(() => _locked = false);
                    _scheduleHide();
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                  ),
                  icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
