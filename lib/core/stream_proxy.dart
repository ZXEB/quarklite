import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 本地多线程播放加速代理。
///
/// mpv 单连接直连网盘 CDN 时，4K 高码率流的吞吐抖动会让缓冲耗尽而卡顿
/// （官方客户端流畅靠的是自家的多连接预下载）。本代理在 127.0.0.1 起一个
/// 回环 HTTP 服务，mpv 只访问本地；代理在上游按两种策略做并发预取：
///
/// - HLS（m3u8）：改写播放列表把全部分段/子列表指向本地，按播放进度
///   并发预取后续分段进内存 LRU；
/// - 直链文件：按 8MiB 分块 Range 滑窗，多连接并发预取，支持 mpv 的
///   Range/seek（seek 时窗口重对齐）。
///
/// 上游鉴权头（Cookie/Referer/UA）由代理统一附带，mpv 侧不再暴露直链与
/// 凭据；全内存实现，不落盘。
class StreamProxy {
  StreamProxy._();

  static final StreamProxy I = StreamProxy._();

  /// 直链模式分块大小（8MiB）
  static const int chunkSize = 8 * 1024 * 1024;

  /// 滑窗预取块数（≈64MB）
  static const int windowChunks = 8;

  /// 直链模式同时在飞的请求上限
  static const int maxInflightChunks = 6;

  /// HLS 分段预取提前量（段）
  static const int hlsPrefetchAhead = 8;

  /// HLS 分段内存缓存上限
  static const int segmentCacheBytes = 192 * 1024 * 1024;

  /// 整体读入内存的资源大小上限（超过则单连接直通）
  static const int fetchCapBytes = 64 * 1024 * 1024;

  /// 单会话上游并发额度（预留 2 个给客户端主动请求）
  static const int gateMax = 8;

  HttpServer? _server;
  int _port = 0;
  final Map<String, _Session> _sessions = {};
  int _seq = 0;

  int _bytesTotal = 0;
  final List<(DateTime, int)> _samples = [];

  HttpClient? _client;
  HttpClient get _http =>
      _client ??= HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 60)
        ..maxConnectionsPerHost = 16;

  /// 代理是否已在运行（回环端口）
  bool get running => _server != null;

  /// 最近 4 秒的下行速率（字节/秒），代理未出流量时为 0
  int get speedBps {
    final now = DateTime.now();
    while (_samples.isNotEmpty &&
        now.difference(_samples.first.$1) > const Duration(seconds: 4)) {
      _samples.removeAt(0);
    }
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final last = _samples.last;
    final dt = last.$1.difference(first.$1).inMilliseconds;
    if (dt <= 200) return 0;
    return ((last.$2 - first.$2) * 1000 / dt).round();
  }

  void _countSent(int n) {
    if (n <= 0) return;
    _bytesTotal += n;
    final now = DateTime.now();
    if (_samples.isNotEmpty && now == _samples.last.$1) {
      return;
    }
    _samples.add((now, _bytesTotal));
    if (_samples.length > 64) _samples.removeAt(0);
  }

  /// 为一个上游直链创建代理会话。失败（端口不可用等）返回 null，
  /// 调用方应回退为 mpv 直连。
  Future<ProxyHandle?> start(String url, Map<String, String> headers) async {
    try {
      final server = await _ensureServer();
      final sid = 's${_seq++}';
      final s = _Session(sid, url, Map.of(headers));
      s.registerResource(url);
      _sessions[sid] = s;
      // 会话收敛：最多保留 6 个（换清晰度/续播会产生新会话）
      while (_sessions.length > 6) {
        final key = _sessions.keys.first;
        _sessions.remove(key)?.dispose();
      }
      return ProxyHandle('http://127.0.0.1:${server.port}/p/$sid', sid, s.dispose);
    } catch (_) {
      return null;
    }
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, backlog: 64);
    _port = server.port;
    _server = server;
    server.listen(_handleRequest, onError: (Object _) {});
    return server;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final parts =
          req.uri.path.split('/')..removeWhere((e) => e.isEmpty);
      if (parts.length == 2 && parts[0] == 'p') {
        final s = _sessions[parts[1]];
        if (s == null || s.disposed) {
          await _respondStatus(req, 404);
          return;
        }
        await _serveRoot(req, s);
      } else if (parts.length == 3 && parts[0] == 'h') {
        final s = _sessions[parts[1]];
        final rid = int.tryParse(parts[2]);
        if (s == null ||
            s.disposed ||
            rid == null ||
            !s.urlByRid.containsKey(rid)) {
          await _respondStatus(req, 404);
          return;
        }
        await _serveResource(req, s, rid);
      } else {
        await _respondStatus(req, 404);
      }
    } catch (_) {
      try {
        req.response.statusCode = 502;
        req.response.contentLength = 0;
        await req.response.close();
      } catch (_) {}
    }
  }

  // ---------------- session root ----------------

  Future<void> _serveRoot(HttpRequest req, _Session s) async {
    await _detectMode(s);
    if (s.mode == _Mode.hls) {
      await _serveResource(req, s, 0);
    } else if (s.mode == _Mode.file) {
      await _streamRange(req, s);
    } else {
      await _pipeUrl(req, s, s.rootUrl);
    }
  }

  /// 模式探测：m3u8 → HLS；Range 可用 → 分块文件；否则单连接直通。
  Future<void> _detectMode(_Session s) async {
    if (s.mode != _Mode.undetermined) return;
    final clean = s.rootUrl.split('?').first.toLowerCase();
    if (clean.endsWith('.m3u8') || clean.endsWith('.m3u')) {
      s.mode = _Mode.hls;
      return;
    }
    HttpClientResponse? resp;
    try {
      resp = await _openGet(s.rootUrl, s.headers, range: 'bytes=0-15')
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 206) {
        final head = await _peek(resp, 16);
        if (_looksLikeM3u8(head)) {
          s.mode = _Mode.hls;
          return;
        }
        final total = _contentRangeTotal(
            resp.headers.value(HttpHeaders.contentRangeHeader));
        if (total != null && total > 0) {
          s.fileSize = total;
          s.mode = _Mode.file;
          return;
        }
      }
      // 200（上游忽略 Range）或其他状态：无法分块，只能直通
      s.mode = _Mode.pipe;
    } catch (_) {
      s.mode = _Mode.pipe;
    } finally {
      await _discardUpstream(resp);
    }
  }

  // ---------------- HLS resources ----------------

  Future<void> _serveResource(HttpRequest req, _Session s, int rid) async {
    _ResData? data = s.cacheGet(rid);
    data ??= await _loadResource(s, rid, priority: true);
    if (data == null) {
      // 超过整读上限的大资源：单连接直通
      await _pipeUrl(req, s, s.urlByRid[rid]!);
      return;
    }
    if (!data.playlist) {
      final segs = s.segments;
      if (segs != null) {
        final idx = segs.indexOf(rid);
        if (idx >= 0 && idx > s.segCursor) s.segCursor = idx;
      }
    }
    _kickHlsPrefetch(s);
    await _respondBytes(req, data);
  }

  /// 拉取并缓存一个资源（播放列表或分段）；超过整读上限返回 null。
  Future<_ResData?> _loadResource(_Session s, int rid,
      {required bool priority}) async {
    final cached = s.cacheGet(rid);
    if (cached != null) return cached;
    final url = s.urlByRid[rid];
    if (url == null) return null;
    await s.gate.enter(priority: priority);
    try {
      final again = s.cacheGet(rid);
      if (again != null) return again;
      final resp =
          await _openGet(url, s.headers).timeout(const Duration(seconds: 30));
      if (resp.statusCode >= 400) {
        await _discardUpstream(resp);
        throw HttpException('上游 ${resp.statusCode}');
      }
      final ctype = resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final builder = BytesBuilder(copy: false);
      var playlist = false;
      var sniffed = false;
      var overflow = false;
      await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
        if (!sniffed) {
          sniffed = true;
          playlist = _looksLikeM3u8(chunk);
        }
        builder.add(chunk);
        if (!playlist && builder.length > fetchCapBytes) {
          overflow = true;
          break; // 退出循环即取消订阅，中断上游连接
        }
      }
      if (overflow) return null;
      if (playlist) {
        final text = utf8.decode(builder.takeBytes(), allowMalformed: true);
        final rewritten = _rewritePlaylist(s, text, url);
        final out = _ResData(
            Uint8List.fromList(utf8.encode(rewritten)),
            'application/vnd.apple.mpegurl',
            playlist: true);
        s.cachePut(rid, out);
        return out;
      }
      final out =
          _ResData(builder.takeBytes(), ctype.isEmpty ? 'video/mp2t' : ctype);
      s.cachePut(rid, out);
      return out;
    } finally {
      s.gate.leave();
    }
  }

  void _kickHlsPrefetch(_Session s) {
    if (s.disposed || s.segments == null) return;
    final segs = s.segments!;
    final start = s.segCursor < 0 ? 0 : s.segCursor;
    final end = min(segs.length, start + hlsPrefetchAhead);
    for (var i = start; i < end; i++) {
      final rid = segs[i];
      if (s.cacheGet(rid) != null || s.segInflight.contains(rid)) continue;
      s.segInflight.add(rid);
      unawaited(_loadResource(s, rid, priority: false)
          .catchError((Object _) => null)
          .whenComplete(() {
        s.segInflight.remove(rid);
        if (!s.disposed) _kickHlsPrefetch(s);
      }));
    }
  }

  // ---------------- playlist rewriting ----------------

  static final RegExp _uriAttrRe =
      RegExp('URI="([^"]+)"', caseSensitive: false);

  String _rewritePlaylist(_Session s, String body, String baseUrl) {
    final hasByteRange = body.contains('#EXT-X-BYTERANGE');
    final isMaster = body.contains('#EXT-X-STREAM-INF');
    final segIds = <int>[];
    final out = StringBuffer();
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        out.writeln();
        continue;
      }
      if (line.startsWith('#')) {
        // 标签行：只改写 URI="..."（KEY / MAP / 媒体组等）
        out.writeln(_rewriteUriAttrs(s, line, baseUrl));
        continue;
      }
      if (hasByteRange) {
        // BYTERANGE 分段共用同一 URI，无法逐段代理，保持原样交 mpv 直连
        out.writeln(line);
        continue;
      }
      final rid = s.registerResource(_resolveUrl(baseUrl, line));
      segIds.add(rid);
      out.writeln(_localUrl(s, rid));
    }
    if (!isMaster && segIds.isNotEmpty) {
      s.segments = segIds;
      s.segCursor = -1;
    }
    return out.toString();
  }

  String _rewriteUriAttrs(_Session s, String line, String baseUrl) {
    return line.replaceAllMapped(_uriAttrRe, (m) {
      final url = _resolveUrl(baseUrl, m.group(1)!);
      final rid = s.registerResource(url);
      return 'URI="${_localUrl(s, rid)}"';
    });
  }

  String _localUrl(_Session s, int rid) =>
      'http://127.0.0.1:$_port/h/${s.id}/$rid';

  static String _resolveUrl(String base, String ref) {
    try {
      return Uri.parse(base).resolve(ref).toString();
    } catch (_) {
      return ref;
    }
  }

  static bool _looksLikeM3u8(Uint8List b) {
    if (b.length < 4) return false;
    // "#EXT"
    return b[0] == 0x23 && b[1] == 0x45 && b[2] == 0x58 && b[3] == 0x54;
  }

  static int? _contentRangeTotal(String? value) {
    if (value == null) return null;
    final m = RegExp(r'/(\d+)$').firstMatch(value.trim());
    if (m == null) return null;
    final v = int.tryParse(m.group(1)!);
    return v;
  }

  // ---------------- file mode ----------------

  Future<void> _streamRange(HttpRequest req, _Session s) async {
    final size = s.fileSize!;
    final rng = req.headers.value(HttpHeaders.rangeHeader);
    var hasRange = false;
    int? start;
    int? endIncl;
    if (rng != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rng.trim());
      if (m != null) {
        final a = m.group(1);
        final b = m.group(2);
        if (a != null && a.isNotEmpty) {
          start = int.parse(a);
          endIncl = (b != null && b.isNotEmpty) ? int.parse(b) : null;
          hasRange = true;
        } else if (b != null && b.isNotEmpty) {
          final n = int.parse(b);
          start = max(0, size - n);
          endIncl = size - 1;
          hasRange = true;
        }
      }
    }
    start ??= 0;
    var last = endIncl ?? size - 1;
    if (last >= size) last = size - 1;
    if (start > last || start >= size) {
      final r = req.response;
      r.statusCode = 416;
      r.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      r.contentLength = 0;
      await r.close();
      return;
    }
    final r = req.response;
    r.statusCode = hasRange ? 206 : 200;
    r.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    r.headers.set(
        HttpHeaders.contentTypeHeader, s.contentType ?? 'video/mp4');
    if (hasRange) {
      r.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$last/$size');
    }
    r.contentLength = last - start + 1;
    if (req.method == 'HEAD') {
      await r.close();
      return;
    }

    final baseChunk = start ~/ chunkSize;
    final startOff = start - baseChunk * chunkSize;
    // seek 跳出旧窗口：清掉旧块重新预取
    if ((baseChunk - s.cursor).abs() > windowChunks + 2) {
      s.chunks.clear();
    }
    s.cursor = baseChunk;
    _pump(s);
    try {
      var pos = start;
      var idx = baseChunk;
      while (pos <= last) {
        if (s.disposed) return;
        final data = await _getChunk(s, idx, priority: true);
        final off = idx == baseChunk ? startOff : 0;
        if (off >= data.length) break;
        final take = min(data.length - off, last - pos + 1);
        await _writeSlice(r, data, off, take);
        pos += take;
        idx++;
        s.cursor = idx;
        _pump(s);
        _evict(s, idx);
      }
      await r.close();
    } catch (_) {
      // 客户端断开（seek/停止）属正常路径
      try {
        await r.close();
      } catch (_) {}
    }
  }

  Future<Uint8List> _getChunk(_Session s, int idx, {bool priority = false}) {
    final done = s.chunks[idx];
    if (done != null) return Future.value(done);
    final f = s.inflight[idx];
    if (f != null) return f;
    return _fetchChunk(s, idx, priority: priority);
  }

  Future<Uint8List> _fetchChunk(_Session s, int idx,
      {bool priority = false}) {
    final existing = s.inflight[idx];
    if (existing != null) return existing;
    final c = Completer<Uint8List>();
    s.inflight[idx] = c.future;
    unawaited(() async {
      try {
        final data = await _fetchChunkInner(s, idx, priority: priority);
        if (!c.isCompleted) c.complete(data);
      } catch (e, st) {
        if (!c.isCompleted) c.completeError(e, st);
      } finally {
        s.inflight.remove(idx);
        if (!s.disposed) _pump(s);
      }
    }());
    return c.future;
  }

  Future<Uint8List> _fetchChunkInner(_Session s, int idx,
      {required bool priority}) async {
    final size = s.fileSize!;
    final from = idx * chunkSize;
    var to = from + chunkSize - 1;
    if (to >= size) to = size - 1;
    final want = to - from + 1;
    await s.gate.enter(priority: priority);
    try {
      final done = s.chunks[idx];
      if (done != null) return done;
      Uint8List data = Uint8List(0);
      Object? lastErr;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final resp = await _openGet(s.rootUrl, s.headers,
                  range: 'bytes=$from-$to')
              .timeout(const Duration(seconds: 20));
          if (resp.statusCode != 206 && resp.statusCode != 200) {
            await _discardUpstream(resp);
            throw HttpException('分块请求失败 ${resp.statusCode}');
          }
          data = await _readExact(resp, want);
          lastErr = null;
          break;
        } catch (e) {
          lastErr = e;
          if (attempt == 1) rethrow;
        }
      }
      if (lastErr != null) throw lastErr;
      if (data.isEmpty) throw HttpException('分块无数据');
      s.chunks[idx] = data;
      return data;
    } finally {
      s.gate.leave();
    }
  }

  void _pump(_Session s) {
    if (s.disposed || s.mode != _Mode.file || s.fileSize == null) return;
    final totalChunks =
        (s.fileSize! + chunkSize - 1) ~/ chunkSize;
    for (var i = 0; i < windowChunks; i++) {
      final idx = s.cursor + i;
      if (idx >= totalChunks) break;
      if (s.chunks.containsKey(idx) || s.inflight.containsKey(idx)) continue;
      if (s.inflight.length >= maxInflightChunks) break;
      _fetchChunk(s, idx, priority: false);
    }
  }

  void _evict(_Session s, int servedIdx) {
    final lo = servedIdx - 2;
    final hi = servedIdx + windowChunks + 2;
    s.chunks.removeWhere((k, _) => k < lo || k > hi);
  }

  // ---------------- passthrough ----------------

  Future<void> _pipeUrl(HttpRequest req, _Session s, String url) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final resp =
        await _openGet(url, s.headers, range: range)
            .timeout(const Duration(seconds: 30));
    final r = req.response;
    try {
      r.statusCode = resp.statusCode;
      final ct = resp.headers.value(HttpHeaders.contentTypeHeader);
      if (ct != null) r.headers.set(HttpHeaders.contentTypeHeader, ct);
      final cl = resp.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) {
        final n = int.tryParse(cl);
        if (n != null && n >= 0) r.contentLength = n;
      }
      final cr = resp.headers.value(HttpHeaders.contentRangeHeader);
      if (cr != null) r.headers.set(HttpHeaders.contentRangeHeader, cr);
      final ar = resp.headers.value(HttpHeaders.acceptRangesHeader);
      if (ar != null) r.headers.set(HttpHeaders.acceptRangesHeader, ar);
      if (req.method == 'HEAD') {
        await _discardUpstream(resp);
        await r.close();
        return;
      }
      var n = 0;
      await r.addStream(resp.map((chunk) {
        n += chunk.length;
        return chunk;
      }));
      _countSent(n);
      await r.close();
    } catch (_) {
      try {
        await _discardUpstream(resp);
      } catch (_) {}
      try {
        await r.close();
      } catch (_) {}
    }
  }

  // ---------------- upstream helpers ----------------

  /// GET 上游（手动跟随重定向，逐跳保留全部请求头）。
  Future<HttpClientResponse> _openGet(String url, Map<String, String> headers,
      {String? range}) async {
    var current = url;
    for (var hop = 0; hop < 5; hop++) {
      final req = await _http.openUrl('GET', Uri.parse(current));
      req.followRedirects = false;
      headers.forEach((k, v) {
        try {
          req.headers.set(k, v);
        } catch (_) {}
      });
      try {
        req.headers.set(HttpHeaders.acceptHeader, '*/*');
      } catch (_) {}
      if (range != null) {
        try {
          req.headers.set(HttpHeaders.rangeHeader, range);
        } catch (_) {}
      }
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.isRedirect) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await _discardUpstream(resp);
        if (loc == null || loc.isEmpty) {
          throw HttpException('重定向缺少 Location');
        }
        current = _resolveUrl(current, loc);
        continue;
      }
      return resp;
    }
    throw HttpException('重定向次数过多');
  }

  /// 读前 n 字节后中断连接（用于探测）。
  Future<Uint8List> _peek(HttpClientResponse resp, int n) async {
    final b = BytesBuilder(copy: false);
    try {
      await for (final chunk in resp) {
        b.add(chunk);
        if (b.length >= n) break;
      }
    } catch (_) {}
    return b.takeBytes();
  }

  /// 精确读 n 字节（超出部分中断连接）。
  Future<Uint8List> _readExact(HttpClientResponse resp, int n) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
      b.add(chunk);
      if (b.length >= n) break;
    }
    final bytes = b.takeBytes();
    return bytes.length > n ? Uint8List.sublistView(bytes, 0, n) : bytes;
  }

  /// 尽力丢弃/中止一个未消费完的上游响应。
  Future<void> _discardUpstream(HttpClientResponse? resp) async {
    if (resp == null) return;
    try {
      var n = 0;
      await for (final chunk in resp) {
        n += chunk.length;
        if (n >= 64 * 1024) break;
      }
    } catch (_) {}
  }

  // ---------------- respond ----------------

  Future<void> _respondBytes(HttpRequest req, _ResData data) async {
    final r = req.response;
    r.statusCode = 200;
    r.headers.set(
        HttpHeaders.contentTypeHeader,
        data.contentType.isEmpty
            ? 'application/octet-stream'
            : data.contentType);
    r.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    r.contentLength = data.bytes.length;
    if (req.method == 'HEAD') {
      await r.close();
      return;
    }
    const sliceSize = 512 * 1024;
    for (var off = 0; off < data.bytes.length; off += sliceSize) {
      final end = min(off + sliceSize, data.bytes.length);
      await _writeSlice(r, data.bytes, off, end - off);
    }
    await r.close();
  }

  Future<void> _writeSlice(HttpResponse r, Uint8List data, int off, int take) async {
    if (take <= 0) return;
    await r.addStream(
        Stream.value(Uint8List.sublistView(data, off, off + take)));
    _countSent(take);
  }

  Future<void> _respondStatus(HttpRequest req, int code) async {
    try {
      req.response.statusCode = code;
      req.response.contentLength = 0;
      await req.response.close();
    } catch (_) {}
  }
}

/// 一次代理会话的句柄：localUrl 交给播放器，dispose 在切换源/退出时调用。
class ProxyHandle {
  final String url;
  final String sessionId;
  final void Function() _onDispose;
  bool _disposed = false;

  ProxyHandle(this.url, this.sessionId, this._onDispose);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose();
  }
}

enum _Mode { undetermined, hls, file, pipe }

class _ResData {
  final Uint8List bytes;
  final String contentType;
  final bool playlist;
  _ResData(this.bytes, this.contentType, {this.playlist = false});
}

/// 并发闸门：上游请求总额度控制；priority 请求插队（客户端在等的数据）。
class _Gate {
  final int max;
  int _used = 0;
  final List<Completer<void>> _waiters = [];
  _Gate(this.max);

  Future<void> enter({bool priority = false}) {
    if (_used < max) {
      _used++;
      return Future.value();
    }
    final c = Completer<void>();
    if (priority) {
      _waiters.insert(0, c);
    } else {
      _waiters.add(c);
    }
    return c.future;
  }

  void leave() {
    if (_used > 0) _used--;
    if (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      _used++;
      c.complete();
    }
  }
}

class _Session {
  _Session(this.id, this.rootUrl, this.headers);

  final String id;
  final String rootUrl;
  final Map<String, String> headers;
  final _Gate gate = _Gate(StreamProxy.gateMax);

  _Mode mode = _Mode.undetermined;
  int? fileSize;
  String? contentType;

  int _ridSeq = 0;
  final Map<String, int> _ridByUrl = {};
  final Map<int, String> urlByRid = {};

  // HLS
  List<int>? segments;
  int segCursor = -1;
  final Set<int> segInflight = {};
  int cacheBytes = 0;
  final Map<int, _ResData> cache = {};

  // file 模式滑窗
  int cursor = 0;
  final Map<int, Uint8List> chunks = {};
  final Map<int, Future<Uint8List>> inflight = {};

  bool disposed = false;

  int registerResource(String url) {
    final existing = _ridByUrl[url];
    if (existing != null) return existing;
    final rid = _ridSeq++;
    _ridByUrl[url] = rid;
    urlByRid[rid] = url;
    return rid;
  }

  _ResData? cacheGet(int rid) {
    final v = cache.remove(rid);
    if (v != null) cache[rid] = v; // 触碰即移到 LRU 尾部
    return v;
  }

  void cachePut(int rid, _ResData data) {
    final old = cache.remove(rid);
    if (old != null) cacheBytes -= old.bytes.length;
    cache[rid] = data;
    cacheBytes += data.bytes.length;
    while (cacheBytes > StreamProxy.segmentCacheBytes && cache.length > 1) {
      final oldest = cache.keys.first;
      cacheBytes -= cache.remove(oldest)!.bytes.length;
    }
  }

  void dispose() {
    disposed = true;
    chunks.clear();
    inflight.clear();
    cache.clear();
    cacheBytes = 0;
    segInflight.clear();
    segments = null;
  }
}
