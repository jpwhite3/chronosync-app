import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Decodes one validated ZIP entry without ever buffering beyond [maximumBytes].
final class BoundedZipEntryDecoder {
  const BoundedZipEntryDecoder();

  Uint8List decode(ZipFileHeader entry, {required int maximumBytes}) {
    if (maximumBytes < 0) {
      throw ArgumentError.value(
        maximumBytes,
        'maximumBytes',
        'The output limit cannot be negative.',
      );
    }
    final ZipFile? file = entry.file;
    if (file == null) {
      throw FormatException('${entry.filename} has no readable ZIP content.');
    }
    if ((entry.generalPurposeBitFlag & 0x01) != 0 || (file.flags & 0x01) != 0) {
      throw FormatException('${entry.filename} cannot be encrypted.');
    }
    if (entry.compressionMethod != ZipFile.zipCompressionStore &&
        entry.compressionMethod != ZipFile.zipCompressionDeflate) {
      throw FormatException(
        '${entry.filename} uses an unsupported ZIP compression method.',
      );
    }
    if (file.filename != entry.filename ||
        file.flags != entry.generalPurposeBitFlag ||
        file.compressedSize != entry.compressedSize ||
        file.uncompressedSize != entry.uncompressedSize ||
        file.crc32 != entry.crc32) {
      throw FormatException(
        '${entry.filename} failed ZIP integrity validation.',
      );
    }

    final _BoundedOutputStream output = _BoundedOutputStream(maximumBytes);
    try {
      final InputStream rawInput = file.getStream(decompress: false);
      if (entry.compressionMethod == ZipFile.zipCompressionStore) {
        output.writeStream(rawInput);
      } else {
        Inflate.stream(rawInput, output: output);
      }
    } on _OutputLimitExceeded {
      throw FormatException(
        '${entry.filename} exceeds the maximum uncompressed size.',
      );
    } on Object {
      throw FormatException(
        '${entry.filename} failed ZIP integrity validation.',
      );
    }

    final Uint8List bytes = output.getBytes();
    if (bytes.length != entry.uncompressedSize ||
        getCrc32(bytes) != entry.crc32) {
      throw FormatException(
        '${entry.filename} failed ZIP integrity validation.',
      );
    }
    return bytes;
  }
}

final class _OutputLimitExceeded implements Exception {
  const _OutputLimitExceeded();
}

final class _BoundedOutputStream extends OutputStream {
  _BoundedOutputStream(this.maximumLength)
    : _buffer = Uint8List(math.min(maximumLength, 32768)),
      super(byteOrder: ByteOrder.littleEndian);

  final int maximumLength;
  Uint8List _buffer;

  @override
  int length = 0;

  void _ensureCapacity(int additionalLength) {
    if (additionalLength < 0 || length > maximumLength - additionalLength) {
      throw const _OutputLimitExceeded();
    }
    final int requiredLength = length + additionalLength;
    if (requiredLength <= _buffer.length) {
      return;
    }
    final int doubledLength = math.max(_buffer.length * 2, 256);
    final int newLength = math.min(
      maximumLength,
      math.max(requiredLength, doubledLength),
    );
    final Uint8List expanded = Uint8List(newLength)
      ..setRange(0, length, _buffer);
    _buffer = expanded;
  }

  @override
  void clear() {
    length = 0;
  }

  @override
  void flush() {}

  @override
  Uint8List getBytes() => subset(0, length);

  @override
  Uint8List subset(int start, [int? end]) {
    final int resolvedStart = start < 0 ? length + start : start;
    int resolvedEnd = end ?? length;
    if (resolvedEnd < 0) {
      resolvedEnd = length + resolvedEnd;
    }
    if (resolvedStart < 0 ||
        resolvedStart > resolvedEnd ||
        resolvedEnd > length) {
      throw RangeError.range(resolvedStart, 0, length);
    }
    return Uint8List.view(
      _buffer.buffer,
      _buffer.offsetInBytes + resolvedStart,
      resolvedEnd - resolvedStart,
    );
  }

  @override
  void writeByte(int value) {
    _ensureCapacity(1);
    _buffer[length] = value;
    length += 1;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final int writeLength = length ?? bytes.length;
    if (writeLength > bytes.length) {
      throw RangeError.range(writeLength, 0, bytes.length);
    }
    _ensureCapacity(writeLength);
    _buffer.setRange(this.length, this.length + writeLength, bytes);
    this.length += writeLength;
  }

  @override
  void writeStream(InputStream stream) {
    writeBytes(stream.toUint8List());
  }
}
