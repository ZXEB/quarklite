import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quarklite/core/gopeed/gopeed_models.dart';
import 'package:quarklite/core/gopeed/ios_background_download_client.dart';
import 'package:quarklite/core/gopeed/ios_parallel_download_client.dart';

void main() {
  group('iOS background downloader mapping', () {
    test('native task statuses map to the shared download model', () {
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.enqueued),
        GopeedStatus.wait,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.waitingToRetry),
        GopeedStatus.wait,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.running),
        GopeedStatus.running,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.paused),
        GopeedStatus.pause,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.complete),
        GopeedStatus.done,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.failed),
        GopeedStatus.error,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.notFound),
        GopeedStatus.error,
      );
      expect(
        IosBackgroundDownloadClient.mapStatus(TaskStatus.canceled),
        GopeedStatus.error,
      );
    });
  });

  group('iOS adaptive parallelism', () {
    test('caps requested chunks at 256', () {
      expect(
        IosParallelDownloadClient.adaptiveChunkCount(requested: 512),
        256,
      );
    });

    test('uses one chunk when Range is unavailable', () {
      expect(
        IosParallelDownloadClient.adaptiveChunkCount(
          requested: 256,
          rangeSupported: false,
        ),
        1,
      );
    });

    test('reduces chunks for small files', () {
      expect(
        IosParallelDownloadClient.adaptiveChunkCount(
          requested: 256,
          contentLength: 16 * 1024 * 1024,
        ),
        2,
      );
    });

    test('keeps configured cap below global maximum', () {
      expect(
        IosParallelDownloadClient.adaptiveChunkCount(
          requested: 256,
          maxConnections: 32,
        ),
        32,
      );
    });
  });
}
