import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chronosync/data/portability/bounded_zip_entry_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const BoundedZipEntryDecoder decoder = BoundedZipEntryDecoder();

  test('decodes deflated and stored ZIP entries without data loss', () {
    final List<int> content = Uint8List.fromList(
      List<int>.generate(4096, (int index) => index % 251),
    );
    final Archive source = Archive()
      ..addFile(ArchiveFile.bytes('deflated.bin', content))
      ..addFile(ArchiveFile.noCompress('stored.bin', content.length, content));
    final Uint8List bytes = ZipEncoder().encodeBytes(source);
    final ZipDirectory directory = ZipDirectory()
      ..read(InputMemoryStream(bytes));

    expect(
      decoder.decode(
        directory.fileHeaders.singleWhere(
          (ZipFileHeader entry) => entry.filename == 'deflated.bin',
        ),
        maximumBytes: content.length,
      ),
      content,
    );
    expect(
      decoder.decode(
        directory.fileHeaders.singleWhere(
          (ZipFileHeader entry) => entry.filename == 'stored.bin',
        ),
        maximumBytes: content.length,
      ),
      content,
    );
  });

  test('stops deflate output at the configured limit', () {
    final Uint8List content = Uint8List(1024 * 1024);
    final Archive source = Archive()
      ..addFile(ArchiveFile.bytes('oversized.bin', content));
    final Uint8List bytes = ZipEncoder().encodeBytes(source);
    final ZipDirectory directory = ZipDirectory()
      ..read(InputMemoryStream(bytes));

    expect(
      () => decoder.decode(directory.fileHeaders.single, maximumBytes: 1024),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('uncompressed'),
        ),
      ),
    );
  });

  test('rejects a deflated entry whose CRC no longer matches', () {
    final List<int> content = List<int>.generate(
      4096,
      (int index) => index % 251,
    );
    final Uint8List bytes = ZipEncoder().encodeBytes(
      Archive()..addFile(ArchiveFile.bytes('corrupt.bin', content)),
    );
    final ZipDirectory directory = ZipDirectory()
      ..read(InputMemoryStream(bytes));
    final ZipFileHeader header = directory.fileHeaders.single;
    final int filenameLength =
        bytes[header.localHeaderOffset + 26] |
        (bytes[header.localHeaderOffset + 27] << 8);
    final int extraLength =
        bytes[header.localHeaderOffset + 28] |
        (bytes[header.localHeaderOffset + 29] << 8);
    final int contentOffset =
        header.localHeaderOffset + 30 + filenameLength + extraLength;
    bytes[contentOffset + (header.compressedSize ~/ 2)] ^= 0x01;
    final ZipDirectory corruptedDirectory = ZipDirectory()
      ..read(InputMemoryStream(bytes));

    expect(
      () => decoder.decode(
        corruptedDirectory.fileHeaders.single,
        maximumBytes: content.length,
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('integrity'),
        ),
      ),
    );
  });
}
