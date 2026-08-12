import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release icons use the ChronoSync brand artwork', () async {
    await _expectBrandedPng(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
      width: 1024,
      height: 1024,
    );
    await _expectBrandedPng('web/icons/Icon-512.png', width: 512, height: 512);
    await _expectBrandedPng(
      'web/icons/Icon-maskable-512.png',
      width: 512,
      height: 512,
    );
    await _expectBrandedPng(
      'web/favicon.png',
      width: 32,
      height: 32,
      expectAccents: false,
    );
  });

  test('iOS launch images are branded, opaque, and correctly scaled', () async {
    const String directory = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    await _expectBrandedPng(
      '$directory/LaunchImage.png',
      width: 168,
      height: 185,
    );
    await _expectBrandedPng(
      '$directory/LaunchImage@2x.png',
      width: 336,
      height: 370,
    );
    await _expectBrandedPng(
      '$directory/LaunchImage@3x.png',
      width: 504,
      height: 555,
    );

    final String storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    expect(storyboard, contains('red="0.968627451"'));
    expect(storyboard, contains('green="0.960784314"'));
    expect(storyboard, contains('blue="0.937254902"'));
  });

  test('generated browser bundles do not publish local build metadata', () {
    final List<FileSystemEntity> generatedMetadata =
        <Directory>[
          Directory('assets/nearby_client'),
          Directory('web'),
        ].expand((Directory directory) => directory.listSync()).where((
          FileSystemEntity entity,
        ) {
          return entity.path.endsWith('.deps') || entity.path.endsWith('.map');
        }).toList();
    expect(generatedMetadata, isEmpty);

    for (final String path in <String>[
      'assets/nearby_client/client.js',
      'web/drift_worker.js',
    ]) {
      final String bundle = File(path).readAsStringSync();
      expect(bundle, isNot(contains('sourceMappingURL=')), reason: path);
      expect(bundle, isNot(contains('/Users/')), reason: path);
    }

    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/nearby_client/index.html'));
    expect(pubspec, contains('- assets/nearby_client/client.js'));
    expect(pubspec, isNot(contains('- assets/nearby_client/\n')));
  });

  test('web document declares mobile and fallback accessibility metadata', () {
    final String index = File('web/index.html').readAsStringSync();
    expect(index, contains('<html lang="en">'));
    expect(
      index,
      contains('name="viewport" content="width=device-width, initial-scale=1"'),
    );
    expect(index, contains('<noscript>'));
    expect(index, contains('ChronoSync requires JavaScript'));
  });

  test('web manifest has a stable scoped identity and localized metadata', () {
    final Map<String, Object?> manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, Object?>;

    expect(manifest['id'], '.');
    expect(manifest['start_url'], '.');
    expect(manifest['scope'], '.');
    expect(manifest['lang'], 'en');
    expect(manifest['dir'], 'ltr');
    expect(manifest['display'], 'standalone');
  });

  test('nearby entry name limit matches the shared domain contract', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();
    expect(index, contains('id="display-name" maxlength="48"'));
    expect(index, isNot(contains('maxlength="50"')));
  });

  test('nearby client removes invitation secrets from browser history', () {
    final String source = File(
      'tool/nearby_client/main.dart',
    ).readAsStringSync();
    final int scrubIndex = source.indexOf('history.replaceState(');
    final int parseIndex = source.indexOf('Invitation.fromQrPayload(');

    expect(scrubIndex, greaterThanOrEqualTo(0));
    expect(source, contains('fragmentFreeNearbyUrl('));
    expect(
      scrubIndex,
      lessThan(parseIndex),
      reason: 'invalid and expired invitations must also be removed',
    );
  });

  test('nearby live state is announced without making timers live', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();
    expect(
      index,
      contains(
        'id="step-announcement" role="status" aria-live="polite" '
        'aria-atomic="true"',
      ),
    );
    expect(index, isNot(contains('id="elapsed" aria-live=')));
    expect(index, isNot(contains('id="remaining" aria-live=')));
  });

  test('nearby controls and text meet non-text and text contrast floors', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();
    expect(index, contains('#7a877f'));
    expect(index, isNot(contains('#b8c3bf')));
    expect(index, contains('#65736d'));
    expect(index, isNot(contains('#71807a')));
    expect(_contrastRatio(0x65736d, 0xffffff), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(0x7a877f, 0xffffff), greaterThanOrEqualTo(3));
  });

  test('nearby reconnect control keeps a 44 pixel touch target', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();
    expect(
      RegExp(
        r'\.reconnect\s*\{[^}]*min-height:\s*44px;',
        dotAll: true,
      ).hasMatch(index),
      isTrue,
    );
    expect(
      index,
      isNot(matches(RegExp(r'\.reconnect[^}]*min-height:\s*3[68]px'))),
    );
  });

  test('Mac release verification propagates codesign failures', () {
    if (!Platform.isMacOS) {
      return;
    }

    final Directory fixture = Directory.systemTemp.createTempSync(
      'chronosync-macos-verification-',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));

    final File entitlements = File(
      '${fixture.path}/macos/Runner/Release.entitlements',
    )..createSync(recursive: true);
    entitlements.writeAsStringSync(_macReleaseEntitlements);

    final File infoPlist = File('${fixture.path}/macos/Runner/Info.plist')
      ..createSync(recursive: true);
    infoPlist.writeAsStringSync(_macInfoPlist);

    Directory(
      '${fixture.path}/build/macos/Build/Products/Release/ChronoSync.app',
    ).createSync(recursive: true);

    final Directory fakeBin = Directory('${fixture.path}/bin')..createSync();
    final File codesign = File('${fakeBin.path}/codesign')
      ..writeAsStringSync('#!/bin/sh\nexit 42\n');
    final ProcessResult chmod = Process.runSync('chmod', <String>[
      '+x',
      codesign.path,
    ]);
    expect(chmod.exitCode, 0, reason: chmod.stderr.toString());

    final ProcessResult result = Process.runSync(
      'make',
      <String>[
        '--no-print-directory',
        'verify-macos-release',
        'APP_DIR=${fixture.path}',
      ],
      workingDirectory: '..',
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
      },
    );

    expect(
      result.exitCode,
      isNot(0),
      reason:
          'A failed nested-code signature check must fail the release gate.\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    expect(
      result.stderr,
      contains('Mac release signature verification failed.'),
    );
  });

  test('Mac release build cannot reuse a stale outer application seal', () {
    final String makefile = File('../Makefile').readAsStringSync();
    final RegExpMatch? target = RegExp(
      r'^build-macos-release:.*?(?=^[a-zA-Z0-9_-]+:)',
      multiLine: true,
      dotAll: true,
    ).firstMatch(makefile);

    expect(target, isNotNull);
    final String recipe = target!.group(0)!;
    final int cleanup = recipe.indexOf('rm -rf "\$(MACOS_RELEASE_APP)"');
    final int build = recipe.indexOf('\$(FLUTTER) build macos --release');

    expect(cleanup, greaterThanOrEqualTo(0));
    expect(build, greaterThan(cleanup));
    expect(
      recipe,
      contains('\$(MAKE) --no-print-directory verify-macos-release'),
    );
  });
}

const String _macReleaseEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
</dict>
</plist>
''';

const String _macInfoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Find nearby ChronoSync sessions.</string>
</dict>
</plist>
''';

Future<void> _expectBrandedPng(
  String path, {
  required int width,
  required int height,
  bool expectAccents = true,
}) async {
  final ui.Codec codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
  );
  final ui.Image image = (await codec.getNextFrame()).image;
  expect(image.width, width, reason: path);
  expect(image.height, height, reason: path);

  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  expect(data, isNotNull, reason: path);
  final Uint8List pixels = data!.buffer.asUint8List();
  expect(_containsColor(pixels, 0x17, 0x6b, 0x52), isTrue, reason: path);
  if (expectAccents) {
    expect(_containsColor(pixels, 0xe3, 0xa2, 0x3b), isTrue, reason: path);
    expect(_containsColor(pixels, 0xe7, 0x6f, 0x61), isTrue, reason: path);
  }
  expect(_isFullyOpaque(pixels), isTrue, reason: '$path contains transparency');
  image.dispose();
  codec.dispose();
}

bool _containsColor(Uint8List pixels, int red, int green, int blue) {
  for (int offset = 0; offset < pixels.length; offset += 4) {
    if (pixels[offset] == red &&
        pixels[offset + 1] == green &&
        pixels[offset + 2] == blue) {
      return true;
    }
  }
  return false;
}

bool _isFullyOpaque(Uint8List pixels) {
  for (int offset = 3; offset < pixels.length; offset += 4) {
    if (pixels[offset] != 0xff) {
      return false;
    }
  }
  return true;
}

double _contrastRatio(int first, int second) {
  final double light = _relativeLuminance(first);
  final double dark = _relativeLuminance(second);
  final double lighter = light > dark ? light : dark;
  final double darker = light > dark ? dark : light;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(int color) {
  double channel(int value) {
    final double normalized = value / 255;
    if (normalized <= 0.04045) {
      return normalized / 12.92;
    }
    return _pow((normalized + 0.055) / 1.055, 2.4);
  }

  return 0.2126 * channel((color >> 16) & 0xff) +
      0.7152 * channel((color >> 8) & 0xff) +
      0.0722 * channel(color & 0xff);
}

double _pow(double base, double exponent) =>
    math.pow(base, exponent).toDouble();
