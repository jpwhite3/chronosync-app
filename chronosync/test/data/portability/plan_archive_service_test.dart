import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const PlanArchiveService service = PlanArchiveService(appVersion: '1.2.3');

  test('exports and previews a versioned archive without data loss', () {
    final Plan plan = _plan();
    final DateTime exportedAt = DateTime.utc(2026, 7, 28, 12, 30);

    final Uint8List bytes = service.exportPlans(<Plan>[
      plan,
    ], exportedAt: exportedAt);
    final PlanImportPreview preview = service.inspect(bytes);

    expect(preview.sourceAppVersion, '1.2.3');
    expect(preview.exportedAt, exportedAt);
    expect(preview.plans, <Plan>[plan]);
    expect(preview.stepCount, 2);
  });

  test('refuses to export more plans than the importer accepts', () {
    expect(
      () => service.exportPlans(List<Plan>.filled(501, _plan())),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('500 plans'),
        ),
      ),
    );
  });

  test('refuses to export an archive its own size limits reject', () {
    final DateTime timestamp = DateTime.utc(2026, 7, 28);
    final String planTitle = List<String>.filled(160, 'P').join();
    final String stepTitle = List<String>.filled(240, 'S').join();
    final List<Plan> plans = List<Plan>.generate(120, (int planIndex) {
      final String planId = 'large-plan-$planIndex';
      return Plan(
        id: planId,
        title: planTitle,
        defaultCueProfile: CueProfile(),
        steps: List<Step>.generate(
          maxPlanSteps,
          (int stepIndex) => Step(
            id: 'large-step-$planIndex-$stepIndex',
            planId: planId,
            position: stepIndex,
            title: stepTitle,
            durationSeconds: 60,
          ),
        ),
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    });

    expect(
      () => service.exportPlans(plans, exportedAt: timestamp),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('10 MB'),
        ),
      ),
    );
  });

  test('requires an explicit time zone in archive timestamps', () {
    final Uint8List bytes = _archiveWithExportedAt('2026-07-28T12:30:00');

    expect(() => service.inspect(bytes), throwsFormatException);
  });

  test('rejects malformed and empty archives', () {
    expect(
      () => service.inspect(Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.inspect(Uint8List.fromList(<int>[1, 2, 3])),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an entry whose uncompressed content exceeds 10 MB', () {
    final Uint8List bytes = _archiveWithPayloadSizes(
      plansPayloadBytes: (10 * 1024 * 1024) + 1,
    );

    expect(bytes.length, lessThan(100000));
    expect(
      () => service.inspect(bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('uncompressed'),
        ),
      ),
    );
  });

  test('bounds decompression when an entry understates its size', () {
    final Uint8List bytes = _archiveWithPayloadSizes(
      plansPayloadBytes: (10 * 1024 * 1024) + 1,
    );
    _rewritePlansUncompressedSize(bytes, 1);

    expect(
      () => service.inspect(bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('uncompressed'),
        ),
      ),
    );
  });

  test('requires exactly the two version-one archive entries', () {
    final Uint8List bytes = _archiveWithPayloadSizes(
      plansPayloadBytes: 1024,
      extraPayloadBytes: <int>[0],
    );

    expect(
      () => service.inspect(bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('exactly two entries'),
        ),
      ),
    );
  });

  test('preflights the EOCD entry count before reading ZIP headers', () {
    final Uint8List bytes = service.exportPlans(<Plan>[_plan()]);
    final ByteData data = ByteData.sublistView(bytes);
    final int eocdOffset = _findEocdOffset(bytes);
    data
      ..setUint16(eocdOffset + 8, 0xFFFE, Endian.little)
      ..setUint16(eocdOffset + 10, 0xFFFE, Endian.little);

    expect(
      () => service.inspect(bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('exactly two entries'),
        ),
      ),
    );
  });

  test('rejects ZIP64 and multidisk archives during preflight', () {
    final Uint8List zip64Bytes = service.exportPlans(<Plan>[_plan()]);
    final ByteData zip64Data = ByteData.sublistView(zip64Bytes);
    final int zip64EocdOffset = _findEocdOffset(zip64Bytes);
    zip64Data
      ..setUint16(zip64EocdOffset + 8, 0xFFFF, Endian.little)
      ..setUint16(zip64EocdOffset + 10, 0xFFFF, Endian.little);

    expect(
      () => service.inspect(zip64Bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('ZIP64'),
        ),
      ),
    );

    final Uint8List multidiskBytes = service.exportPlans(<Plan>[_plan()]);
    final ByteData multidiskData = ByteData.sublistView(multidiskBytes);
    final int multidiskEocdOffset = _findEocdOffset(multidiskBytes);
    multidiskData
      ..setUint16(multidiskEocdOffset + 4, 1, Endian.little)
      ..setUint16(multidiskEocdOffset + 6, 1, Endian.little);

    expect(
      () => service.inspect(multidiskBytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('multiple disks'),
        ),
      ),
    );
  });

  test('rejects central-directory bounds before parsing entries', () {
    final Uint8List bytes = service.exportPlans(<Plan>[_plan()]);
    final ByteData data = ByteData.sublistView(bytes);
    final int eocdOffset = _findEocdOffset(bytes);
    data.setUint32(
      eocdOffset + 12,
      data.getUint32(eocdOffset + 12, Endian.little) + 1,
      Endian.little,
    );

    expect(
      () => service.inspect(bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('central directory'),
        ),
      ),
    );
  });

  test('rejects duplicate archive entry names', () {
    final Uint8List bytes = ZipEncoder().encodeBytes(
      Archive()
        ..addFile(ArchiveFile.string('first.json', '{}'))
        ..addFile(ArchiveFile.string('other.json', '{}')),
    );
    _rewriteEntryName(bytes, from: 'other.json', to: 'first.json');

    expect(
      () => service.inspect(bytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('duplicate'),
        ),
      ),
    );
  });

  test('rejects encrypted and unsupported ZIP entries before decoding', () {
    final Uint8List encryptedBytes = service.exportPlans(<Plan>[_plan()]);
    _rewriteEntryFlags(encryptedBytes, name: 'plans.json', flags: 1);
    expect(
      () => service.inspect(encryptedBytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('encrypted'),
        ),
      ),
    );

    final Uint8List unsupportedBytes = service.exportPlans(<Plan>[_plan()]);
    _rewriteEntryCompression(
      unsupportedBytes,
      name: 'plans.json',
      compression: 99,
    );
    expect(
      () => service.inspect(unsupportedBytes),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('compression'),
        ),
      ),
    );
  });

  test('remaps plan and step IDs instead of overwriting collisions', () {
    final Plan original = _plan();

    final Plan imported = service
        .resolveIdCollisions(
          importedPlans: <Plan>[original],
          existingPlanIds: <String>{original.id},
          existingStepIds: original.steps
              .map<String>((Step step) => step.id)
              .toSet(),
        )
        .single;

    expect(imported.id, isNot(original.id));
    expect(imported.steps.map((Step step) => step.id), isNot(contains('s1')));
    expect(
      imported.steps.every((Step step) => step.planId == imported.id),
      isTrue,
    );
  });
}

Uint8List _archiveWithPayloadSizes({
  required int plansPayloadBytes,
  List<int> extraPayloadBytes = const <int>[],
}) {
  final Plan plan = _plan();
  final String plansJson = jsonEncode(<String, Object>{
    'archiveVersion': chronosyncArchiveVersion,
    'plans': <Map<String, Object?>>[plan.toJson()],
  });
  final Uint8List plansPayload = _paddedJson(plansJson, plansPayloadBytes);
  final Archive archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(<String, Object>{
          'archiveVersion': chronosyncArchiveVersion,
          'format': 'com.chronosync.plans',
          'appVersion': '1.2.3',
          'exportedAt': DateTime.utc(2026, 7, 28).toIso8601String(),
          'planCount': 1,
        }),
      ),
    )
    ..addFile(ArchiveFile.bytes('plans.json', plansPayload));
  for (int index = 0; index < extraPayloadBytes.length; index += 1) {
    archive.addFile(
      ArchiveFile.bytes(
        'extra-$index.bin',
        Uint8List(extraPayloadBytes[index]),
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _archiveWithExportedAt(String exportedAt) {
  final Plan plan = _plan();
  return ZipEncoder().encodeBytes(
    Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode(<String, Object>{
            'archiveVersion': chronosyncArchiveVersion,
            'format': 'com.chronosync.plans',
            'appVersion': '1.2.3',
            'exportedAt': exportedAt,
            'planCount': 1,
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'plans.json',
          jsonEncode(<String, Object>{
            'archiveVersion': chronosyncArchiveVersion,
            'plans': <Map<String, Object?>>[plan.toJson()],
          }),
        ),
      ),
  );
}

Uint8List _paddedJson(String json, int length) {
  final List<int> jsonBytes = utf8.encode(json);
  if (jsonBytes.length > length) {
    throw ArgumentError.value(length, 'length', 'Must fit the JSON payload.');
  }
  return Uint8List(length)
    ..fillRange(0, length, 0x20)
    ..setRange(0, jsonBytes.length, jsonBytes);
}

void _rewritePlansUncompressedSize(Uint8List bytes, int size) {
  final ZipDirectory directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final ByteData data = ByteData.sublistView(bytes);
  int centralHeaderOffset = directory.centralDirectoryOffset;
  for (final ZipFileHeader entry in directory.fileHeaders) {
    if (entry.filename == 'plans.json') {
      data
        ..setUint32(entry.localHeaderOffset + 22, size, Endian.little)
        ..setUint32(centralHeaderOffset + 24, size, Endian.little);
    }
    final int filenameLength = data.getUint16(
      centralHeaderOffset + 28,
      Endian.little,
    );
    final int extraLength = data.getUint16(
      centralHeaderOffset + 30,
      Endian.little,
    );
    final int commentLength = data.getUint16(
      centralHeaderOffset + 32,
      Endian.little,
    );
    centralHeaderOffset += 46 + filenameLength + extraLength + commentLength;
  }
}

int _findEocdOffset(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  for (int offset = bytes.length - 22; offset >= 0; offset -= 1) {
    if (data.getUint32(offset, Endian.little) == 0x06054B50) {
      return offset;
    }
  }
  throw StateError('EOCD record not found.');
}

Map<String, int> _centralHeaderOffsets(Uint8List bytes) {
  final ZipDirectory directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final ByteData data = ByteData.sublistView(bytes);
  final Map<String, int> offsets = <String, int>{};
  int offset = directory.centralDirectoryOffset;
  for (final ZipFileHeader entry in directory.fileHeaders) {
    offsets[entry.filename] = offset;
    final int filenameLength = data.getUint16(offset + 28, Endian.little);
    final int extraLength = data.getUint16(offset + 30, Endian.little);
    final int commentLength = data.getUint16(offset + 32, Endian.little);
    offset += 46 + filenameLength + extraLength + commentLength;
  }
  return offsets;
}

void _rewriteEntryName(
  Uint8List bytes, {
  required String from,
  required String to,
}) {
  final List<int> fromBytes = utf8.encode(from);
  final List<int> toBytes = utf8.encode(to);
  if (fromBytes.length != toBytes.length) {
    throw ArgumentError('ZIP test entry names must have equal byte lengths.');
  }
  final ZipDirectory directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final ZipFileHeader entry = directory.fileHeaders.singleWhere(
    (ZipFileHeader candidate) => candidate.filename == from,
  );
  final int centralOffset = _centralHeaderOffsets(bytes)[from]!;
  bytes
    ..setRange(
      entry.localHeaderOffset + 30,
      entry.localHeaderOffset + 30 + toBytes.length,
      toBytes,
    )
    ..setRange(
      centralOffset + 46,
      centralOffset + 46 + toBytes.length,
      toBytes,
    );
}

void _rewriteEntryFlags(
  Uint8List bytes, {
  required String name,
  required int flags,
}) {
  final ZipDirectory directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final ZipFileHeader entry = directory.fileHeaders.singleWhere(
    (ZipFileHeader candidate) => candidate.filename == name,
  );
  final int centralOffset = _centralHeaderOffsets(bytes)[name]!;
  ByteData.sublistView(bytes)
    ..setUint16(entry.localHeaderOffset + 6, flags, Endian.little)
    ..setUint16(centralOffset + 8, flags, Endian.little);
}

void _rewriteEntryCompression(
  Uint8List bytes, {
  required String name,
  required int compression,
}) {
  final ZipDirectory directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final ZipFileHeader entry = directory.fileHeaders.singleWhere(
    (ZipFileHeader candidate) => candidate.filename == name,
  );
  final int centralOffset = _centralHeaderOffsets(bytes)[name]!;
  ByteData.sublistView(bytes)
    ..setUint16(entry.localHeaderOffset + 8, compression, Endian.little)
    ..setUint16(centralOffset + 10, compression, Endian.little);
}

Plan _plan() {
  final DateTime timestamp = DateTime.utc(2026, 7, 28);
  return Plan(
    id: 'p1',
    title: 'Show, with punctuation',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 's1',
        planId: 'p1',
        position: 0,
        title: 'Preset',
        durationSeconds: 60,
      ),
      Step(
        id: 's2',
        planId: 'p1',
        position: 1,
        title: 'Go',
        durationSeconds: 30,
      ),
    ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
