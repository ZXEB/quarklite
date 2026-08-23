import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quarklite/core/gopeed/gopeed_models.dart';
import 'package:quarklite/core/gopeed/ios_background_download_client.dart';

void main() {
  group('iOS background downloader mapping', () {
    test('parallel chunks are limited to one through eight', () {
      expect(IosBackgroundDownloadClient.chunkCount(0), 1);
      expect(IosBackgroundDownloadClient.chunkCount(4), 4);
      expect(IosBackgroundDownloadClient.chunkCount(512), 8);
    });

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
}
