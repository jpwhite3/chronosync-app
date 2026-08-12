import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chronosync/core/serialization/utc_timestamp.dart';
import 'package:chronosync/data/portability/archive_limits.dart';
import 'package:chronosync/data/portability/bounded_zip_entry_decoder.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:uuid/uuid.dart';

const int chronosyncArchiveVersion = 1;
const int _requiredArchiveEntries = 2;
const int _maximumArchiveEntryBytes = 10 * 1024 * 1024;
const int _maximumUncompressedArchiveBytes = 20 * 1024 * 1024;
const int _maximumImportedPlans = 500;
const int _zipEocdSignature = 0x06054B50;
const int _zip64EocdLocatorSignature = 0x07064B50;
const int _zipCentralHeaderSignature = 0x02014B50;
const int _zipLocalHeaderSignature = 0x04034B50;

final class PlanImportPreview {
  const PlanImportPreview({
    required this.exportedAt,
    required this.sourceAppVersion,
    required this.plans,
  });

  final DateTime exportedAt;
  final String sourceAppVersion;
  final List<Plan> plans;

  int get stepCount =>
      plans.fold<int>(0, (int count, Plan plan) => count + plan.steps.length);
}

final class PlanArchiveService {
  const PlanArchiveService({this.appVersion = '1.0.0'});

  final String appVersion;

  Uint8List exportPlans(Iterable<Plan> plans, {DateTime? exportedAt}) {
    final List<Plan> selected = List<Plan>.unmodifiable(plans);
    if (selected.isEmpty) {
      throw const FormatException('Select at least one plan to export.');
    }
    if (selected.length > _maximumImportedPlans) {
      throw const FormatException(
        'A ChronoSync archive cannot contain more than 500 plans.',
      );
    }
    final DateTime timestamp = (exportedAt ?? DateTime.now()).toUtc();
    final String manifestJson = jsonEncode(<String, Object>{
      'archiveVersion': chronosyncArchiveVersion,
      'format': 'com.chronosync.plans',
      'appVersion': appVersion,
      'exportedAt': timestamp.toIso8601String(),
      'planCount': selected.length,
    });
    final String plansJson = jsonEncode(<String, Object>{
      'archiveVersion': chronosyncArchiveVersion,
      'plans': selected
          .map<Map<String, Object?>>((Plan plan) => plan.toJson())
          .toList(growable: false),
    });
    if (utf8.encode(manifestJson).length > _maximumArchiveEntryBytes ||
        utf8.encode(plansJson).length > _maximumArchiveEntryBytes) {
      throw const FormatException(
        'The selected plans exceed the 10 MB ChronoSync archive limit.',
      );
    }
    final Archive archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', manifestJson))
      ..addFile(ArchiveFile.string('plans.json', plansJson));
    final Uint8List encoded = ZipEncoder().encodeBytes(archive);
    if (encoded.length > maximumChronoSyncArchiveBytes) {
      throw const FormatException(
        'The selected plans exceed the 10 MB ChronoSync archive limit.',
      );
    }
    return encoded;
  }

  PlanImportPreview inspect(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumChronoSyncArchiveBytes) {
      throw const FormatException(
        'The ChronoSync archive is empty or exceeds 10 MB.',
      );
    }

    late final Map<String, ZipFileHeader> entries;
    try {
      final _ZipPreflight preflight = _ZipPreflight.read(bytes);
      final ZipDirectory directory = ZipDirectory()
        ..read(InputMemoryStream(bytes));
      entries = _validatedEntries(directory, preflight: preflight);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'The file is not a valid ChronoSync archive.',
      );
    }

    final Map<String, Object?> manifest = _decodeObject(
      entries['manifest.json']!,
      'manifest.json',
    );
    final Map<String, Object?> plansPayload = _decodeObject(
      entries['plans.json']!,
      'plans.json',
    );
    _requireArchiveVersion(manifest);
    _requireArchiveVersion(plansPayload);
    if (manifest['format'] != 'com.chronosync.plans') {
      throw const FormatException(
        'This archive is not a ChronoSync plan file.',
      );
    }

    final Object? plansValue = plansPayload['plans'];
    if (plansValue is! List<Object?> ||
        plansValue.isEmpty ||
        plansValue.length > _maximumImportedPlans) {
      throw const FormatException(
        'An archive must contain between 1 and 500 plans.',
      );
    }
    final List<Plan> plans = plansValue
        .map<Plan>((Object? value) {
          if (value is! Map<Object?, Object?>) {
            throw const FormatException('An imported plan is malformed.');
          }
          return Plan.fromJson(Map<String, Object?>.from(value));
        })
        .toList(growable: false);
    if (manifest['planCount'] != plans.length) {
      throw const FormatException('The archive plan count does not match.');
    }

    final Object? exportedAtValue = manifest['exportedAt'];
    final Object? appVersionValue = manifest['appVersion'];
    if (exportedAtValue is! String || appVersionValue is! String) {
      throw const FormatException('The archive manifest is incomplete.');
    }
    final DateTime exportedAt = parseUtcTimestamp(
      exportedAtValue,
      fieldName: 'exportedAt',
    );
    return PlanImportPreview(
      exportedAt: exportedAt,
      sourceAppVersion: appVersionValue,
      plans: List<Plan>.unmodifiable(plans),
    );
  }

  List<Plan> resolveIdCollisions({
    required Iterable<Plan> importedPlans,
    required Set<String> existingPlanIds,
    Set<String> existingStepIds = const <String>{},
    Uuid uuid = const Uuid(),
  }) {
    final Set<String> claimedIds = Set<String>.of(existingPlanIds);
    final Set<String> claimedStepIds = Set<String>.of(existingStepIds);
    final DateTime now = DateTime.now().toUtc();
    return importedPlans
        .map<Plan>((Plan plan) {
          final bool planIdCollides = !claimedIds.add(plan.id);
          String newPlanId = plan.id;
          if (planIdCollides) {
            newPlanId = uuid.v4();
            while (!claimedIds.add(newPlanId)) {
              newPlanId = uuid.v4();
            }
          }

          bool changedStepId = false;
          final List<Step> steps = plan.steps
              .map<Step>((Step step) {
                String stepId = step.id;
                if (planIdCollides || !claimedStepIds.add(stepId)) {
                  changedStepId = true;
                  stepId = uuid.v4();
                  while (!claimedStepIds.add(stepId)) {
                    stepId = uuid.v4();
                  }
                }
                return step.copyWith(id: stepId, planId: newPlanId);
              })
              .toList(growable: false);

          if (!planIdCollides && !changedStepId) {
            return plan;
          }
          return Plan(
            id: newPlanId,
            title: plan.title,
            plannedStartTime: plan.plannedStartTime,
            defaultCueProfile: plan.defaultCueProfile,
            steps: steps,
            createdAt: now,
            updatedAt: now,
          );
        })
        .toList(growable: false);
  }

  Map<String, Object?> _decodeObject(ZipFileHeader entry, String name) {
    late final Uint8List bytes;
    try {
      bytes = const BoundedZipEntryDecoder().decode(
        entry,
        maximumBytes: _maximumArchiveEntryBytes,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException('$name has invalid compressed content.');
    }

    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) {
        throw const FormatException();
      }
      return Map<String, Object?>.from(decoded);
    } on Object {
      throw FormatException('$name is not valid JSON.');
    }
  }

  Map<String, ZipFileHeader> _validatedEntries(
    ZipDirectory directory, {
    required _ZipPreflight preflight,
  }) {
    if (directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0) {
      throw const FormatException(
        'ChronoSync archives cannot span multiple disks.',
      );
    }
    if (directory.centralDirectoryOffset != preflight.centralDirectoryOffset ||
        directory.centralDirectorySize != preflight.centralDirectorySize) {
      throw const FormatException(
        'The ZIP central directory does not match its preflight record.',
      );
    }
    final List<ZipFileHeader> entries = directory.fileHeaders;
    if (entries.length != _requiredArchiveEntries) {
      throw const FormatException(
        'A version-one ChronoSync archive must contain exactly two entries.',
      );
    }

    int totalSize = 0;
    final Map<String, ZipFileHeader> entriesByName = <String, ZipFileHeader>{};
    for (final ZipFileHeader entry in entries) {
      if (entriesByName.containsKey(entry.filename)) {
        throw const FormatException(
          'The archive contains a duplicate entry name.',
        );
      }
      entriesByName[entry.filename] = entry;
      final int fileType = (entry.externalFileAttributes >> 16) & 0xF000;
      if (fileType == 0xA000) {
        throw const FormatException(
          'The archive cannot contain symbolic links.',
        );
      }
      final int size = entry.uncompressedSize;
      if (size < 0 || size > _maximumArchiveEntryBytes) {
        throw const FormatException(
          'An archive entry exceeds the maximum uncompressed size.',
        );
      }
      totalSize += size;
      if (totalSize > _maximumUncompressedArchiveBytes) {
        throw const FormatException(
          'The archive exceeds the maximum total uncompressed size.',
        );
      }
    }
    if (!entriesByName.containsKey('manifest.json') ||
        !entriesByName.containsKey('plans.json')) {
      throw const FormatException(
        'The archive must contain manifest.json and plans.json.',
      );
    }
    return entriesByName;
  }

  void _requireArchiveVersion(Map<String, Object?> payload) {
    if (payload['archiveVersion'] != chronosyncArchiveVersion) {
      throw FormatException(
        'Unsupported ChronoSync archive version: '
        '${payload['archiveVersion']}.',
      );
    }
  }
}

final class _ZipPreflight {
  const _ZipPreflight({
    required this.centralDirectoryOffset,
    required this.centralDirectorySize,
  });

  final int centralDirectoryOffset;
  final int centralDirectorySize;

  static _ZipPreflight read(Uint8List bytes) {
    if (bytes.length < 22) {
      throw const FormatException(
        'The file has no valid ZIP end-of-central-directory record.',
      );
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int eocdOffset = _findEocdOffset(data, bytes.length);
    final int commentLength = data.getUint16(eocdOffset + 20, Endian.little);
    if (commentLength != 0) {
      throw const FormatException(
        'ChronoSync archives cannot contain a ZIP comment.',
      );
    }
    if (eocdOffset >= 20 &&
        data.getUint32(eocdOffset - 20, Endian.little) ==
            _zip64EocdLocatorSignature) {
      throw const FormatException('ZIP64 archives are not supported.');
    }

    final int diskNumber = data.getUint16(eocdOffset + 4, Endian.little);
    final int centralDirectoryDisk = data.getUint16(
      eocdOffset + 6,
      Endian.little,
    );
    final int entriesOnDisk = data.getUint16(eocdOffset + 8, Endian.little);
    final int totalEntries = data.getUint16(eocdOffset + 10, Endian.little);
    final int centralDirectorySize = data.getUint32(
      eocdOffset + 12,
      Endian.little,
    );
    final int centralDirectoryOffset = data.getUint32(
      eocdOffset + 16,
      Endian.little,
    );

    if (entriesOnDisk == 0xFFFF ||
        totalEntries == 0xFFFF ||
        centralDirectorySize == 0xFFFFFFFF ||
        centralDirectoryOffset == 0xFFFFFFFF) {
      throw const FormatException('ZIP64 archives are not supported.');
    }
    if (diskNumber != 0 ||
        centralDirectoryDisk != 0 ||
        entriesOnDisk != totalEntries) {
      throw const FormatException(
        'ChronoSync archives cannot span multiple disks.',
      );
    }
    if (totalEntries != _requiredArchiveEntries) {
      throw const FormatException(
        'A version-one ChronoSync archive must contain exactly two entries.',
      );
    }
    if (centralDirectoryOffset > eocdOffset ||
        centralDirectorySize > eocdOffset - centralDirectoryOffset ||
        centralDirectoryOffset + centralDirectorySize != eocdOffset) {
      throw const FormatException(
        'The ZIP central directory is outside the archive bounds.',
      );
    }

    _validateCentralDirectory(
      data,
      centralDirectoryOffset: centralDirectoryOffset,
      centralDirectorySize: centralDirectorySize,
    );
    return _ZipPreflight(
      centralDirectoryOffset: centralDirectoryOffset,
      centralDirectorySize: centralDirectorySize,
    );
  }

  static int _findEocdOffset(ByteData data, int length) {
    final int searchWindow = 22 + 0xFFFF;
    final int minimumOffset = length > searchWindow ? length - searchWindow : 0;
    for (int offset = length - 22; offset >= minimumOffset; offset -= 1) {
      if (data.getUint32(offset, Endian.little) != _zipEocdSignature) {
        continue;
      }
      final int commentLength = data.getUint16(offset + 20, Endian.little);
      if (offset + 22 + commentLength == length) {
        return offset;
      }
    }
    throw const FormatException(
      'The file has no valid ZIP end-of-central-directory record.',
    );
  }

  static void _validateCentralDirectory(
    ByteData data, {
    required int centralDirectoryOffset,
    required int centralDirectorySize,
  }) {
    final int centralDirectoryEnd =
        centralDirectoryOffset + centralDirectorySize;
    int offset = centralDirectoryOffset;
    int totalUncompressedSize = 0;

    for (int index = 0; index < _requiredArchiveEntries; index += 1) {
      _requireRange(
        offset: offset,
        length: 46,
        upperBound: centralDirectoryEnd,
        description: 'central directory',
      );
      if (data.getUint32(offset, Endian.little) != _zipCentralHeaderSignature) {
        throw const FormatException('The ZIP central directory is malformed.');
      }

      final int flags = data.getUint16(offset + 8, Endian.little);
      final int compression = data.getUint16(offset + 10, Endian.little);
      final int compressedSize = data.getUint32(offset + 20, Endian.little);
      final int uncompressedSize = data.getUint32(offset + 24, Endian.little);
      final int filenameLength = data.getUint16(offset + 28, Endian.little);
      final int extraLength = data.getUint16(offset + 30, Endian.little);
      final int entryCommentLength = data.getUint16(offset + 32, Endian.little);
      final int diskStart = data.getUint16(offset + 34, Endian.little);
      final int localHeaderOffset = data.getUint32(offset + 42, Endian.little);

      if (compressedSize == 0xFFFFFFFF ||
          uncompressedSize == 0xFFFFFFFF ||
          localHeaderOffset == 0xFFFFFFFF ||
          diskStart == 0xFFFF) {
        throw const FormatException('ZIP64 archives are not supported.');
      }
      if (diskStart != 0) {
        throw const FormatException(
          'ChronoSync archives cannot span multiple disks.',
        );
      }
      if ((flags & 0x01) != 0) {
        throw const FormatException(
          'ChronoSync archive entries cannot be encrypted.',
        );
      }
      if (compression != ZipFile.zipCompressionStore &&
          compression != ZipFile.zipCompressionDeflate) {
        throw const FormatException(
          'The archive uses an unsupported ZIP compression method.',
        );
      }
      if (uncompressedSize > _maximumArchiveEntryBytes) {
        throw const FormatException(
          'An archive entry exceeds the maximum uncompressed size.',
        );
      }
      totalUncompressedSize += uncompressedSize;
      if (totalUncompressedSize > _maximumUncompressedArchiveBytes) {
        throw const FormatException(
          'The archive exceeds the maximum total uncompressed size.',
        );
      }

      final int variableLength =
          filenameLength + extraLength + entryCommentLength;
      _requireRange(
        offset: offset + 46,
        length: variableLength,
        upperBound: centralDirectoryEnd,
        description: 'central directory entry',
      );
      _validateExtraFields(
        data,
        offset: offset + 46 + filenameLength,
        length: extraLength,
      );
      _validateLocalEntry(
        data,
        localHeaderOffset: localHeaderOffset,
        centralDirectoryOffset: centralDirectoryOffset,
        centralFlags: flags,
        centralCompression: compression,
        centralCompressedSize: compressedSize,
        centralUncompressedSize: uncompressedSize,
      );
      offset += 46 + variableLength;
    }

    if (offset != centralDirectoryEnd) {
      throw const FormatException(
        'The ZIP central directory size does not match its entries.',
      );
    }
  }

  static void _validateLocalEntry(
    ByteData data, {
    required int localHeaderOffset,
    required int centralDirectoryOffset,
    required int centralFlags,
    required int centralCompression,
    required int centralCompressedSize,
    required int centralUncompressedSize,
  }) {
    _requireRange(
      offset: localHeaderOffset,
      length: 30,
      upperBound: centralDirectoryOffset,
      description: 'local ZIP header',
    );
    if (data.getUint32(localHeaderOffset, Endian.little) !=
        _zipLocalHeaderSignature) {
      throw const FormatException('A local ZIP header is malformed.');
    }
    final int localFlags = data.getUint16(localHeaderOffset + 6, Endian.little);
    final int localCompression = data.getUint16(
      localHeaderOffset + 8,
      Endian.little,
    );
    final int localCompressedSize = data.getUint32(
      localHeaderOffset + 18,
      Endian.little,
    );
    final int localUncompressedSize = data.getUint32(
      localHeaderOffset + 22,
      Endian.little,
    );
    final int filenameLength = data.getUint16(
      localHeaderOffset + 26,
      Endian.little,
    );
    final int extraLength = data.getUint16(
      localHeaderOffset + 28,
      Endian.little,
    );
    if (localFlags != centralFlags ||
        localCompression != centralCompression ||
        localCompressedSize != centralCompressedSize ||
        localUncompressedSize != centralUncompressedSize) {
      throw const FormatException(
        'A local ZIP header does not match the central directory.',
      );
    }

    final int dataOffset =
        localHeaderOffset + 30 + filenameLength + extraLength;
    _requireRange(
      offset: localHeaderOffset + 30,
      length: filenameLength + extraLength,
      upperBound: centralDirectoryOffset,
      description: 'local ZIP header',
    );
    _validateExtraFields(
      data,
      offset: localHeaderOffset + 30 + filenameLength,
      length: extraLength,
    );
    _requireRange(
      offset: dataOffset,
      length: centralCompressedSize,
      upperBound: centralDirectoryOffset,
      description: 'compressed ZIP entry',
    );
  }

  static void _validateExtraFields(
    ByteData data, {
    required int offset,
    required int length,
  }) {
    final int end = offset + length;
    int cursor = offset;
    while (cursor < end) {
      _requireRange(
        offset: cursor,
        length: 4,
        upperBound: end,
        description: 'ZIP extra field',
      );
      final int identifier = data.getUint16(cursor, Endian.little);
      final int fieldLength = data.getUint16(cursor + 2, Endian.little);
      if (identifier == 0x0001) {
        throw const FormatException('ZIP64 archives are not supported.');
      }
      cursor += 4;
      _requireRange(
        offset: cursor,
        length: fieldLength,
        upperBound: end,
        description: 'ZIP extra field',
      );
      cursor += fieldLength;
    }
  }

  static void _requireRange({
    required int offset,
    required int length,
    required int upperBound,
    required String description,
  }) {
    if (offset < 0 ||
        length < 0 ||
        offset > upperBound ||
        length > upperBound - offset) {
      throw FormatException('The $description is outside the archive bounds.');
    }
  }
}
