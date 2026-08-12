import 'dart:convert';
import 'dart:typed_data';

import 'package:chronosync/data/portability/archive_limits.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:share_plus/share_plus.dart';

abstract interface class FilePickerAdapter {
  Future<FilePickerResult?> pickFiles({
    required String dialogTitle,
    required FileType type,
    required List<String> allowedExtensions,
    required bool allowMultiple,
    required bool withData,
    required bool withReadStream,
  });

  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
    required FileType type,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  });
}

final class StaticFilePickerAdapter implements FilePickerAdapter {
  const StaticFilePickerAdapter();

  @override
  Future<FilePickerResult?> pickFiles({
    required String dialogTitle,
    required FileType type,
    required List<String> allowedExtensions,
    required bool allowMultiple,
    required bool withData,
    required bool withReadStream,
  }) {
    return FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: withData,
      withReadStream: withReadStream,
    );
  }

  @override
  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
    required FileType type,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) {
    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
  }
}

final class PortabilityFileService {
  const PortabilityFileService({
    FilePickerAdapter filePicker = const StaticFilePickerAdapter(),
  }) : _filePicker = filePicker;

  final FilePickerAdapter _filePicker;

  Future<Uint8List?> pickChronoSyncArchive() async {
    final FilePickerResult? result = await _filePicker.pickFiles(
      dialogTitle: 'Import ChronoSync plans',
      type: FileType.custom,
      allowedExtensions: const <String>['chronosync'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null) {
      return null;
    }
    final PlatformFile file = result.files.single;
    if (file.size > maximumChronoSyncArchiveBytes) {
      throw const FileSystemException('The ChronoSync archive exceeds 10 MB.');
    }

    final Stream<List<int>>? stream = file.readStream;
    if (stream != null) {
      return _readBoundedArchive(stream);
    }

    final Uint8List? bytes = file.bytes;
    if (bytes != null) {
      if (bytes.length > maximumChronoSyncArchiveBytes) {
        throw const FileSystemException(
          'The ChronoSync archive exceeds 10 MB.',
        );
      }
      return bytes;
    }

    throw const FileSystemException(
      'ChronoSync could not read the selected file safely.',
    );
  }

  Future<void> shareArchive({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (_usesNativeSaveDialog) {
      await _filePicker.saveFile(
        dialogTitle: 'Export ChronoSync plans',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['chronosync'],
        bytes: bytes,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        subject: 'ChronoSync plans',
        files: <XFile>[
          XFile.fromData(
            bytes,
            mimeType: 'application/vnd.chronosync.plans+zip',
          ),
        ],
        fileNameOverrides: <String>[fileName],
      ),
    );
  }

  Future<void> shareCsv({required String csv, required String fileName}) async {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(csv));
    if (_usesNativeSaveDialog) {
      await _filePicker.saveFile(
        dialogTitle: 'Export ChronoSync activity',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['csv'],
        bytes: bytes,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        subject: 'ChronoSync session activity',
        files: <XFile>[XFile.fromData(bytes, mimeType: 'text/csv')],
        fileNameOverrides: <String>[fileName],
      ),
    );
  }
}

Future<Uint8List> _readBoundedArchive(Stream<List<int>> stream) async {
  final BytesBuilder output = BytesBuilder(copy: false);
  int retainedLength = 0;
  await for (final List<int> chunk in stream) {
    if (chunk.isEmpty) {
      continue;
    }
    final int remainingThroughSentinel =
        maximumChronoSyncArchiveBytes + 1 - retainedLength;
    final int retainedChunkLength = chunk.length < remainingThroughSentinel
        ? chunk.length
        : remainingThroughSentinel;
    output.add(
      retainedChunkLength == chunk.length
          ? chunk
          : chunk.sublist(0, retainedChunkLength),
    );
    retainedLength += retainedChunkLength;
    if (retainedLength > maximumChronoSyncArchiveBytes ||
        retainedChunkLength < chunk.length) {
      throw const FileSystemException('The ChronoSync archive exceeds 10 MB.');
    }
  }
  return output.takeBytes();
}

bool get _usesNativeSaveDialog =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

final class FileSystemException implements Exception {
  const FileSystemException(this.message);

  final String message;

  @override
  String toString() => message;
}
