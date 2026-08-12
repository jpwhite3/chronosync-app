import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final String platform in <String>['ios', 'macos']) {
    test('$platform app declares its privacy practices', () {
      final File manifest = File('$platform/Runner/PrivacyInfo.xcprivacy');
      expect(manifest.existsSync(), isTrue);

      final String contents = manifest.readAsStringSync();
      expect(
        contents,
        matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false\s*/>')),
      );
      expect(contents, contains('<key>NSPrivacyCollectedDataTypes</key>'));
      expect(contents, contains('<key>NSPrivacyAccessedAPITypes</key>'));
      expect(
        contents,
        matches(RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array\s*/>')),
      );

      final String project = File(
        '$platform/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        'PrivacyInfo.xcprivacy'.allMatches(project).length,
        greaterThanOrEqualTo(3),
        reason: 'The manifest must be referenced and copied into Runner.app.',
      );
      expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
    });
  }
}
