import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quarklite/api/quark_models.dart';
import 'package:quarklite/pages/parse/parse_page.dart';
import 'package:quarklite/pages/parse/share_files_page.dart';
import 'package:quarklite/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _historyKey = 'flutter.parse_history';
const _oldShare = 'https://pan.quark.cn/s/test-old';
const _oldHistory = '$_oldShare\u0001old-code\u00011';
const _newShare = 'https://pan.quark.cn/s/test-new';
const _unsaved = '解析记录的更改未保存';
final _client = _ShareFixtureClient();

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    _client.attemptedRequests.clear();
  });

  tearDown(() {
    AppState.I.user = null;
  });

  testWidgets('shows previously saved history with its passcode', (
    tester,
  ) async {
    _HistoryPreferences(tester, stored: _oldHistory);
    await _pumpParsePage(tester);
    await tester.pumpAndSettle();

    expect(find.text(_oldShare), findsOneWidget);
    expect(find.text('提取码: old-code'), findsOneWidget);
    expect(find.text(_unsaved), findsNothing);
  });

  testWidgets('keeps parsing usable after a native read failure', (
    tester,
  ) async {
    final prefs = _HistoryPreferences(tester, stored: _oldHistory)
      ..read = () => throw PlatformException(code: 'prefs_unavailable');
    await _pumpParsePage(tester);
    await _parseNewShare(tester);
    await tester.pumpAndSettle();

    _expectShareFiles();
    expect(prefs.writes, isEmpty);
    expect(prefs.stored, _oldHistory);
    await _backToHistory(tester);
    expect(find.widgetWithText(MiuixText, _newShare), findsOneWidget);
    expect(find.text(_unsaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [true, false]) {
    testWidgets(
      'opens parsed files when history write ${throws ? 'throws' : 'returns false'}',
      (tester) async {
        final prefs = _HistoryPreferences(tester, stored: _oldHistory)
          ..write = (_) {
            if (throws) {
              throw PlatformException(
                code: 'PlatformException',
                message: 'java.lang.NoSuchMethodError',
              );
            }
            return false;
          };
        await _pumpParsePage(tester);
        await _parseNewShare(tester);
        await tester.pumpAndSettle();

        _expectShareFiles();
        expect(prefs.writes, hasLength(1));
        expect(prefs.stored, _oldHistory);
        await _backToHistory(tester);
        expect(find.widgetWithText(MiuixText, _newShare), findsOneWidget);
        expect(find.text(_unsaved), findsOneWidget);

        prefs.write = null;
        await _parseNewShare(tester);
        await tester.pumpAndSettle();
        await _backToHistory(tester);
        expect(find.widgetWithText(MiuixText, _newShare), findsOneWidget);
        expect(find.text(_unsaved), findsNothing);
        expect(prefs.stored!.split('\n'), hasLength(2));
      },
    );
  }

  testWidgets(
    'marks an unsuccessful deletion and keeps stored history intact',
    (tester) async {
      final prefs = _HistoryPreferences(tester, stored: _oldHistory)
        ..write = (_) => false;
      await _pumpParsePage(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_oldShare), findsNothing);
      expect(find.text(_unsaved), findsOneWidget);
      expect(prefs.writes, ['']);
      expect(prefs.stored, _oldHistory);

      await tester.pumpWidget(const SizedBox.shrink());
      SharedPreferences.resetStatic();
      await _pumpParsePage(tester);
      await tester.pumpAndSettle();
      expect(find.text(_oldShare), findsOneWidget);
    },
  );

  testWidgets('merges a new parse with history that loads asynchronously', (
    tester,
  ) async {
    final loaded = Completer<Map<String, Object>>();
    final prefs = _HistoryPreferences(tester)..read = () => loaded.future;
    await _pumpParsePage(tester);
    await _parseNewShare(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(_client.attemptedRequests, ['token', 'detail']);
    expect(prefs.writes, isEmpty);
    expect(find.widgetWithText(MiuixText, _newShare), findsNothing);

    loaded.complete({_historyKey: _oldHistory});
    await tester.pumpAndSettle();
    _expectShareFiles();
    final savedHistory = prefs.stored!.split('\n');
    expect(savedHistory, hasLength(2));
    expect(savedHistory.first.split('\u0001').take(2), [_newShare, '']);
    expect(savedHistory.last, _oldHistory);
  });

  testWidgets('writes overlapping deletions in order', (tester) async {
    final firstWrite = Completer<bool>();
    final prefs = _HistoryPreferences(
      tester,
      stored: '$_oldHistory\n$_newShare\u0001\u00012',
    )..write = (history) => history.isEmpty ? true : firstWrite.future;
    await _pumpParsePage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(prefs.writes, hasLength(1));
    expect(prefs.writes.single, startsWith(_newShare));

    firstWrite.complete(true);
    await tester.pumpAndSettle();
    expect(prefs.writes, hasLength(2));
    expect(prefs.stored, '');
    expect(find.text(_unsaved), findsNothing);
  });

  testWidgets('can leave the page while preferences are still loading', (
    tester,
  ) async {
    final loaded = Completer<Map<String, Object>>();
    final prefs = _HistoryPreferences(tester);
    prefs.read = () => loaded.future;
    await _pumpParsePage(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    loaded.complete({_historyKey: _oldHistory});
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpParsePage(WidgetTester tester) => tester.pumpWidget(
  const MiuixThemeController(
    colorSchemeMode: MiuixColorSchemeMode.system,
    child: MaterialApp(home: Scaffold(body: ParsePage())),
  ),
);

Future<void> _parseNewShare(WidgetTester tester) async {
  AppState.I.user = QuarkUserInfo(
    nickname: 'Fixture',
    avatar: '',
    userId: 'fixture',
    totalSize: 0,
    usedSize: 0,
  );
  await HttpOverrides.runZoned(() async {
    await tester.enterText(find.byType(EditableText).first, _newShare);
    await tester.tap(find.text('开始解析'));
    await tester.pump();
  }, createHttpClient: (_) => _client);
}

void _expectShareFiles() {
  expect(find.byType(ShareFilesPage), findsOneWidget);
  expect(find.text('fixture-file.txt'), findsOneWidget);
}

Future<void> _backToHistory(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}

class _HistoryPreferences {
  String? stored;
  FutureOr<Map<String, Object>> Function()? read;
  FutureOr<bool> Function(String)? write;
  final writes = <String>[];

  _HistoryPreferences(WidgetTester tester, {this.stored}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') {
          return read?.call() ?? {_historyKey: ?stored};
        }
        if (call.method == 'setString') {
          final arguments = call.arguments as Map;
          expect(arguments['key'], _historyKey);
          final history = arguments['value'] as String;
          writes.add(history);
          final saved = await (write?.call(history) ?? true);
          if (saved) stored = history;
          return saved;
        }
        throw UnsupportedError(call.method);
      },
    );
  }
}

class _ShareFixtureClient extends Fake implements HttpClient {
  final attemptedRequests = <String>[];

  @override
  set idleTimeout(Duration value) {}

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    expect(url.host, 'drive.quark.cn');
    final endpoint = url.pathSegments.last;
    attemptedRequests.add(endpoint);
    final body = switch (endpoint) {
      'token' => {
        'code': 0,
        'data': {'stoken': 'fixture-token'},
      },
      'detail' => {
        'code': 0,
        'data': {
          'list': [
            {'fid': 'file', 'file_name': 'fixture-file.txt'},
          ],
        },
        'metadata': {'_total': 1},
      },
      _ => throw UnsupportedError(endpoint),
    };
    return _FixtureRequest(jsonEncode(body));
  }
}

class _FixtureRequest extends Fake implements HttpClientRequest {
  final String body;

  _FixtureRequest(this.body);

  @override
  final HttpHeaders headers = _FixtureHeaders();

  @override
  set followRedirects(bool value) {}

  @override
  set maxRedirects(int value) {}

  @override
  set persistentConnection(bool value) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain();

  @override
  Future<HttpClientResponse> close() async => _FixtureResponse(body);
}

class _FixtureHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String, List<String>) action) {
    action(HttpHeaders.contentTypeHeader, ['application/json']);
  }
}

class _FixtureResponse extends Stream<List<int>> implements HttpClientResponse {
  final String body;

  _FixtureResponse(this.body);

  @override
  final HttpHeaders headers = _FixtureHeaders();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
