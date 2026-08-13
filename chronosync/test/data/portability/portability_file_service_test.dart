import 'dart:async';
import 'dart:typed_data';

import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

const int _maximumArchiveBytes = 10 * 1024 * 1024;

void main() {
  test('requests a stream and assembles a small archive', () async {
    final _RecordingFilePicker picker = _RecordingFilePicker(
      PlatformFile(
        name: 'plans.chronosync',
        size: 4,
        readStream: Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
      ),
    );
    final PortabilityFileService service = PortabilityFileService(
      filePicker: picker,
    );

    final Uint8List? bytes = await service.pickChronoSyncArchive();

    expect(bytes, <int>[1, 2, 3, 4]);
    expect(picker.requestedDialogTitle, 'Import ChronoSync sequences');
    expect(picker.requestedWithData, isFalse);
    expect(picker.requestedWithReadStream, isTrue);
  });

  test('rejects a reported oversized file before subscribing', () async {
    bool subscribed = false;
    final Stream<List<int>> stream = Stream<List<int>>.multi((
      MultiStreamController<List<int>> controller,
    ) {
      subscribed = true;
      controller.close();
    });
    final _RecordingFilePicker picker = _RecordingFilePicker(
      PlatformFile(
        name: 'oversized.chronosync',
        size: _maximumArchiveBytes + 1,
        readStream: stream,
      ),
    );
    final PortabilityFileService service = PortabilityFileService(
      filePicker: picker,
    );

    await expectLater(
      service.pickChronoSyncArchive(),
      throwsA(
        isA<FileSystemException>().having(
          (FileSystemException error) => error.message,
          'message',
          contains('10 MB'),
        ),
      ),
    );
    expect(subscribed, isFalse);
  });

  test(
    'cancels a stream that exceeds the cap despite a smaller size',
    () async {
      int chunksYielded = 0;
      final Uint8List chunk = Uint8List(1024 * 1024);
      Stream<List<int>> oversizedStream() async* {
        for (int index = 0; index < 20; index += 1) {
          chunksYielded += 1;
          yield chunk;
        }
      }

      final _RecordingFilePicker picker = _RecordingFilePicker(
        PlatformFile(
          name: 'lying-size.chronosync',
          size: 1,
          readStream: oversizedStream(),
        ),
      );
      final PortabilityFileService service = PortabilityFileService(
        filePicker: picker,
      );

      await expectLater(
        service.pickChronoSyncArchive(),
        throwsA(
          isA<FileSystemException>().having(
            (FileSystemException error) => error.message,
            'message',
            contains('10 MB'),
          ),
        ),
      );
      expect(chunksYielded, 11);
    },
  );
}

final class _RecordingFilePicker implements FilePickerAdapter {
  _RecordingFilePicker(this.file);

  final PlatformFile file;
  String? requestedDialogTitle;
  bool? requestedWithData;
  bool? requestedWithReadStream;

  @override
  Future<FilePickerResult?> pickFiles({
    required String dialogTitle,
    required FileType type,
    required List<String> allowedExtensions,
    required bool allowMultiple,
    required bool withData,
    required bool withReadStream,
  }) async {
    requestedDialogTitle = dialogTitle;
    requestedWithData = withData;
    requestedWithReadStream = withReadStream;
    return FilePickerResult(<PlatformFile>[file]);
  }

  @override
  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
    required FileType type,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) {
    throw UnsupportedError('This picker only records import requests.');
  }
}
