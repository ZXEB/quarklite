import 'dart:async';
import 'dart:convert';
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
        if (key == sid) break; // 不淘汰刚建的当前会话
        _sessions.remove(key)?.dispose();
      }
      return ProxyHandle('http://127.0.0.1:${server.port}/p/$sid', sid, s.dispose);
    } catch (_) {
      return null;
    }
  }

  /// 代理可用性自检：对 /p/{sid} 发一个 1 字节 Range GET，要求 2xx 且
  /// 读到数据。上游探测失败（签名过期/CDN拒绝/网络抖动）时代理会 502，
  /// mpv 拿到就是 "Failed to open"——调用方应据此回退直连。
  Future<bool> probe(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client
          .openUrl('GET', uri)
          .timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      var ok = false;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final b = BytesBuilder(copy: false);
        await for (final chunk in resp
            .timeout(const Duration(seconds: 8), onTimeout: (sink) => sink.close())) {
          b.add(chunk);
          if (b.length >= 1) break;
        }
        ok = b.length > 0;
      } else {
        await _discardUpstream(resp);
      }
      client.close(force: true);
      return ok;
    } catch (_) {
      return false;
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
      // pipe / pipeRetry：pipeRetry 表示首次探测已失败过，直接按重试路径走
      await _pipeUrl(req, s, s.rootUrl, isRetry: s.mode == _Mode.pipeRetry);
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
      // 首次探测失败不直接定死 pipe：留待 _pipeUrl 用完整 Range 再试一次
      // （部分 CDN 对 bytes=0-15 的微小 Range 返回异常，但正常 Range 可用）
      s.mode = _Mode.pipeRetry;
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

  // HttpClientResponse 的元素静态类型是 List<int>（运行时才是 Uint8List）
  static bool _looksLikeM3u8(List<int> b) {
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
    // 首块未缓存时优先直通：按请求区间直接向上游拉流、边收边写，
    // 首字节不再等整块 8MiB 下载完（mpv 打开 mp4 时会另开连接长距
    // seek 到片尾读 moov，原来必撞本地 5s 超时）。途经的完整分块
    // 回填滑窗缓存；上游没能给出可用响应（未写出任何字节）时回落
    // 到下方分块窗口路径。
    if (s.chunks[baseChunk] == null &&
        await _teeFileRange(req, s, start, last)) {
      return;
    }
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

  /// 文件模式直通：按客户端请求的 [start]-[last] 区间向上游拉流，
  /// 边收边写给客户端，并把途经的完整分块回填进滑窗缓存（部分块丢弃，
  /// 保持 chunks 只存整块的语义；末块按文件实际剩余长度截断）。
  /// 返回 true 表示响应已接管；返回 false 表示一个字节都没写出去，
  /// 调用方应走分块窗口兜底。
  Future<bool> _teeFileRange(
      HttpRequest req, _Session s, int start, int last) async {
    if (s.disposed) return false;
    final size = s.fileSize!;
    HttpClientResponse? resp;
    var delivered = 0;
    // 回填游标：从 start 所在块开始顺序收整块
    var fillIdx = start ~/ chunkSize;
    var fillStart = fillIdx * chunkSize;
    Uint8List? fillBuf;
    var fillLen = 0;
    void feed(List<int> c) {
      var off = 0;
      while (off < c.length) {
        if (fillBuf == null) {
          if (s.disposed) return;
          fillBuf = Uint8List(chunkSize);
          fillLen = 0;
        }
        final buf = fillBuf!;
        final take = min(chunkSize - fillLen, c.length - off);
        buf.setRange(fillLen, fillLen + take, c, off);
        fillLen += take;
        off += take;
        if (fillLen >= chunkSize || fillStart + fillLen >= size) {
          if (!s.disposed) {
            s.chunks[fillIdx] = fillLen == chunkSize
                ? buf
                : Uint8List.sublistView(buf, 0, fillLen);
            if (fillIdx + 1 > s.cursor) s.cursor = fillIdx + 1;
            _pump(s);
            _evict(s, fillIdx);
          }
          fillIdx++;
          fillStart += chunkSize;
          fillBuf = null;
          fillLen = 0;
        }
      }
    }

    try {
      // 末段用开区间，让 CDN 直流到文件尾（对齐 mpv 的 bytes=0- 习惯）
      final range = last >= size - 1 ? 'bytes=$start-' : 'bytes=$start-$last';
      resp = await _openGet(s.rootUrl, s.headers, range: range)
          .timeout(const Duration(seconds: 20));
      // 仅接受 206（200 说明上游忽略了 Range，数据起点不对，不能直通）；
      // Content-Range 起点异常时同样放弃，交分块路径处理
      final cr = resp.headers.value(HttpHeaders.contentRangeHeader);
      if (resp.statusCode != 206 ||
          (cr != null && !cr.startsWith('bytes $start-'))) {
        await _discardUpstream(resp);
        return false;
      }
      final r = req.response;
      await r.addStream(resp.map((c) {
        delivered += c.length;
        feed(c);
        return c;
      }));
      await r.close();
      _countSent(delivered);
      return true;
    } catch (_) {
      await _discardUpstream(resp);
      if (delivered > 0) {
        // 已开始写出后中断（seek/停止属正常路径），连接到此为止
        try {
          await req.response.close();
        } catch (_) {}
        return true;
      }
      // 未写出任何字节：响应仍干净，交给分块窗口兜底
      return false;
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

  Future<void> _pipeUrl(HttpRequest req, _Session s, String url,
      {bool isRetry = false}) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    HttpClientResponse? resp;
    try {
      resp = await _openGet(url, s.headers, range: range)
          .timeout(const Duration(seconds: 30));
      // pipeRetry：探测失败后的二次尝试。若仍失败，把状态码透传给客户端
      // 后放弃（调用方 mpv 会得到明确的 HTTP 错误而非挂死）。
      if (resp.statusCode >= 400) {
        final code = resp.statusCode;
        await _discardUpstream(resp);
        // 403/401 若由客户端携带的 Range 引起（部分 CDN 拒绝开区间
        // Range），先去掉 Range 再试一次；5xx 与重试路径直接透传
        final hardFail = isRetry ||
            code >= 500 ||
            ((code == 403 || code == 401) && range == null);
        if (hardFail) {
          final r = req.response;
          r.statusCode = code >= 400 ? code : 502;
          r.contentLength = 0;
          await r.close();
          return;
        }
        // 客户端带了 Range 且上游拒绝：去掉 Range 再试一次
        if (range != null) {
          resp = await _openGet(url, s.headers)
              .timeout(const Duration(seconds: 30));
          if (resp.statusCode >= 400) {
            final code2 = resp.statusCode;
            await _discardUpstream(resp);
            final r = req.response;
            r.statusCode = code2;
            r.contentLength = 0;
            await r.close();
            return;
          }
        }
      }
      final r = req.response;
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
      // 上游中断/超时。若一个字节都还没写给客户端（响应未开始或刚开始），
      // 再给一次完整重试（去 Range 重开）；否则只能中断（seek 场景属正常）。
      // 注意：头一旦发出再改状态码会抛异常，因此重试失败时仅在未写头时
      // 才尝试置 502（置失败也无所谓，close 让连接断开即可）。
      await _discardUpstream(resp);
      try {
        if (!isRetry) {
          await _pipeUrl(req, s, url, isRetry: true);
          return;
        }
        final r = req.response;
        try {
          r.statusCode = 502;
          r.contentLength = 0;
        } catch (_) {}
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

enum _Mode { undetermined, hls, file, pipe, pipeRetry }

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
