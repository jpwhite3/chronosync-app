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
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      width: 1024,
      height: 1024,
    );
    await _expectBrandedPng(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      width: 192,
      height: 192,
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
    await _expectBrandedPng(
      '$directory/LaunchImage-dark.png',
      width: 168,
      height: 185,
    );
    await _expectBrandedPng(
      '$directory/LaunchImage-dark@2x.png',
      width: 336,
      height: 370,
    );
    await _expectBrandedPng(
      '$directory/LaunchImage-dark@3x.png',
      width: 504,
      height: 555,
    );

    final Map<String, Object?> launchContents =
        jsonDecode(File('$directory/Contents.json').readAsStringSync())
            as Map<String, Object?>;
    final List<Object?> launchImages =
        launchContents['images']! as List<Object?>;
    expect(launchImages, hasLength(6));
    expect(
      launchImages.where((Object? entry) {
        final Map<String, Object?> image = entry! as Map<String, Object?>;
        return image['appearances'] != null;
      }),
      hasLength(3),
    );

    final String storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    expect(storyboard, contains('name="LaunchBackground"'));

    final Map<String, Object?> launchColor =
        jsonDecode(
              File(
                'ios/Runner/Assets.xcassets/LaunchBackground.colorset/'
                'Contents.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final List<Object?> colors = launchColor['colors']! as List<Object?>;
    expect(colors, hasLength(2));
    expect(_assetColorComponents(colors[0]!), <String>['0xF4', '0xF5', '0xFA']);
    expect(_assetColorComponents(colors[1]!), <String>['0x05', '0x06', '0x08']);
    expect((colors[1]! as Map<String, Object?>)['appearances'], isNotNull);
  });

  test('brand source and generator publish the Dark Deco identity', () {
    final String source = File(
      'tool/branding/chronosync_app_icon.svg',
    ).readAsStringSync();
    for (final String color in <String>[
      '#050608',
      '#1E3A8A',
      '#6366F1',
      '#82AAFF',
      '#FFCB6B',
      '#B83A4A',
    ]) {
      expect(source, contains(color), reason: color);
    }
    expect(source, isNot(contains('#176B52')));
    expect(source, isNot(contains('#F7F5EF')));

    final String generator = File(
      'tool/branding/generate_assets.sh',
    ).readAsStringSync();
    for (final String output in <String>[
      'mipmap-mdpi/ic_launcher.png',
      'mipmap-xxxhdpi/ic_launcher.png',
      'windows/runner/resources/app_icon.ico',
      'LaunchImage-dark@3x.png',
    ]) {
      expect(generator, contains(output), reason: output);
    }

    for (final (String path, String color) in <(String, String)>[
      ('android/app/src/main/res/values/colors.xml', '#F4F5FA'),
      ('android/app/src/main/res/values-night/colors.xml', '#050608'),
    ]) {
      expect(File(path).readAsStringSync(), contains(color), reason: path);
    }
    for (final String path in <String>[
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('@color/launch_background'),
        reason: path,
      );
    }
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
    expect(
      index,
      contains(
        'ChronoSync keeps groups in sync through shared timed sequences.',
      ),
    );
    expect(index, contains('create and run shared sequences'));
  });

  test('web chrome follows the adaptive Dark Deco palette', () {
    final String index = File('web/index.html').readAsStringSync();

    expect(index, contains('name="color-scheme" content="light dark"'));
    expect(
      index,
      contains(
        'name="theme-color" content="#F4F5FA" '
        'media="(prefers-color-scheme: light)"',
      ),
    );
    expect(
      index,
      contains(
        'name="theme-color" content="#050608" '
        'media="(prefers-color-scheme: dark)"',
      ),
    );
    expect(index, contains('background: #F4F5FA;'));
    expect(index, contains('@media (prefers-color-scheme: dark)'));
    expect(index, contains('background: #050608;'));
    expect(index, isNot(contains('#176B52')));
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
    expect(manifest['background_color'], '#F4F5FA');
    expect(manifest['theme_color'], '#1E3A8A');
    expect(
      manifest['description'],
      'A local-first shared timer for groups moving through a sequence '
      'together.',
    );
  });

  test('nearby entry name limit matches the shared domain contract', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();
    expect(index, contains('id="display-name" maxlength="48"'));
    expect(index, isNot(contains('maxlength="50"')));
  });

  test('nearby client uses the Sequence and Interval product language', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();

    expect(index, contains('Join the live sequence.'));
    expect(index, contains('id="step-position">Interval 1'));
    expect(index, contains('you saw the current interval'));
    expect(index, isNot(contains('live runbook')));
    expect(index, isNot(contains('Team participant')));
    expect(index, contains('Let everyone know'));

    final String source = File(
      'tool/nearby_client/main.dart',
    ).readAsStringSync();
    expect(source, contains("'Participant'"));
    expect(source, contains('Enter the name others will see.'));
    expect(source, isNot(contains('joining team')));
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

  test('nearby client publishes adaptive Dark Deco color tokens', () {
    final String index = File(
      'assets/nearby_client/index.html',
    ).readAsStringSync();

    expect(index, contains('name="color-scheme" content="light dark"'));
    expect(index, contains('color-scheme: light dark;'));
    expect(index, contains('@media (prefers-color-scheme: dark)'));
    for (final String token in <String>[
      '--canvas: #F4F5FA;',
      '--surface: #FFFFFF;',
      '--text-primary: #11131C;',
      '--text-secondary: #4B526D;',
      '--primary: #1E3A8A;',
      '--canvas: #050608;',
      '--surface: #0B0C0E;',
      '--surface-muted: #1A1D24;',
      '--text-primary: #E8E8E8;',
      '--text-secondary: #BABED8;',
      '--primary: #666AF5;',
      '--primary-pressed: #7A7DFF;',
      '--live: #82AAFF;',
      '--warning: #FFCB6B;',
    ]) {
      expect(index, contains(token), reason: token);
    }
    expect(index, contains('var(--canvas)'));
    expect(index, contains('var(--text-primary)'));
    expect(index, contains('var(--primary)'));
    expect(index, isNot(contains('#174e3a')));
    expect(index, isNot(contains('#18332a')));
    expect(index, isNot(contains('#2d7b5b')));
  });

  test('nearby controls and text meet contrast floors in both schemes', () {
    for (final (int foreground, int background) in <(int, int)>[
      // Light text and controls.
      (0x11131C, 0xF4F5FA),
      (0x4B526D, 0xF4F5FA),
      (0x4B526D, 0xFFFFFF),
      (0xFFFFFF, 0x1E3A8A),
      (0x1E3A8A, 0xE3E8FA),
      (0x4A5D23, 0xE8EED9),
      (0x6F4E00, 0xFFF1C9),
      (0x8B2635, 0xFBE5EA),
      // Dark text and controls.
      (0xE8E8E8, 0x050608),
      (0xBABED8, 0x0B0C0E),
      (0x050608, 0x666AF5),
      (0xC5CAE9, 0x1E2951),
      (0x9FB36B, 0x252B18),
      (0xFFCB6B, 0x3C2C0D),
      (0xFF9CAC, 0x3B151D),
    ]) {
      expect(_contrastRatio(foreground, background), greaterThanOrEqualTo(4.5));
    }

    for (final (int boundary, int surface) in <(int, int)>[
      (0x717891, 0xFFFFFF),
      (0x717CB4, 0x0B0C0E),
    ]) {
      expect(_contrastRatio(boundary, surface), greaterThanOrEqualTo(3));
    }
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

  test('iOS nearby fallback page uses the adaptive Dark Deco palette', () {
    final String source = File(
      'ios/Runner/NearbyHostService.swift',
    ).readAsStringSync();

    for (final String token in <String>[
      'name="color-scheme" content="light dark"',
      '--canvas: #F4F5FA;',
      '--surface: #FFFFFF;',
      '--text-primary: #11131C;',
      '--text-secondary: #4B526D;',
      '--primary: #1E3A8A;',
      '@media (prefers-color-scheme: dark)',
      '--canvas: #050608;',
      '--surface: #0B0C0E;',
      '--surface-muted: #1A1D24;',
      '--text-primary: #E8E8E8;',
      '--text-secondary: #BABED8;',
      '--primary: #666AF5;',
      '--primary-pressed: #7A7DFF;',
      '--warning: #FFCB6B;',
    ]) {
      expect(source, contains(token), reason: token);
    }
    for (final String staleToken in <String>[
      '#174E3A',
      '#F7F3EA',
      '#18332A',
      '#2D7B5B',
    ]) {
      expect(source, isNot(contains(staleToken)), reason: staleToken);
    }
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
  expect(_containsColor(pixels, 0x05, 0x06, 0x08), isTrue, reason: path);
  expect(
    expectAccents
        ? _containsColor(pixels, 0x1e, 0x3a, 0x8a)
        : _containsNearColor(pixels, 0x1e, 0x3a, 0x8a, tolerance: 16),
    isTrue,
    reason: path,
  );
  expect(
    expectAccents
        ? _containsColor(pixels, 0x82, 0xaa, 0xff)
        : _containsNearColor(pixels, 0x82, 0xaa, 0xff, tolerance: 16),
    isTrue,
    reason: path,
  );
  if (expectAccents) {
    expect(_containsColor(pixels, 0x63, 0x66, 0xf1), isTrue, reason: path);
    expect(_containsColor(pixels, 0xff, 0xcb, 0x6b), isTrue, reason: path);
    expect(_containsColor(pixels, 0xb8, 0x3a, 0x4a), isTrue, reason: path);
  }
  expect(_containsColor(pixels, 0x17, 0x6b, 0x52), isFalse, reason: path);
  expect(_containsColor(pixels, 0xf7, 0xf5, 0xef), isFalse, reason: path);
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

bool _containsNearColor(
  Uint8List pixels,
  int red,
  int green,
  int blue, {
  required int tolerance,
}) {
  for (int offset = 0; offset < pixels.length; offset += 4) {
    if ((pixels[offset] - red).abs() <= tolerance &&
        (pixels[offset + 1] - green).abs() <= tolerance &&
        (pixels[offset + 2] - blue).abs() <= tolerance) {
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

List<String> _assetColorComponents(Object color) {
  final Map<String, Object?> entry = color as Map<String, Object?>;
  final Map<String, Object?> value = entry['color']! as Map<String, Object?>;
  final Map<String, Object?> components =
      value['components']! as Map<String, Object?>;
  return <String>[
    components['red']! as String,
    components['green']! as String,
    components['blue']! as String,
  ];
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
