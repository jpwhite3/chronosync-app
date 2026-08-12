import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/release_artifact_verifier.dart';

void main() {
  late Directory releaseDirectory;

  setUp(() {
    releaseDirectory = Directory.systemTemp.createTempSync(
      'chronosync_web_release_',
    );
  });

  tearDown(() {
    releaseDirectory.deleteSync(recursive: true);
  });

  test('accepts a release containing only sanitized browser assets', () {
    File(
      '${releaseDirectory.path}/app.js',
    ).writeAsStringSync('console.log("ChronoSync");');

    expect(webReleaseArtifactProblems(releaseDirectory), isEmpty);
  });

  test('reports compiler metadata and source-map references', () {
    File(
      '${releaseDirectory.path}/worker.js.deps',
    ).writeAsStringSync('file:///Users/developer/project/worker.dart');
    File(
      '${releaseDirectory.path}/worker.js',
    ).writeAsStringSync('//# sourceMappingURL=worker.js.map');

    expect(
      webReleaseArtifactProblems(releaseDirectory),
      containsAll(<String>[
        'worker.js.deps: compiler metadata must not ship',
        'worker.js: contains a source-map reference',
      ]),
    );
  });

  test('reports absolute local file URLs embedded in text assets', () {
    File('${releaseDirectory.path}/worker.js').writeAsStringSync(
      'const source = "file:///Users/developer/project/worker.dart";',
    );

    expect(
      webReleaseArtifactProblems(releaseDirectory),
      contains('worker.js: contains an absolute local file URL'),
    );
  });

  test('sanitizes generated source maps and their references', () {
    File(
      '${releaseDirectory.path}/worker.js.map',
    ).writeAsStringSync('{"version":3}');
    File(
      '${releaseDirectory.path}/worker.js.deps',
    ).writeAsStringSync('file:///Users/developer/project/worker.dart');
    final File script = File('${releaseDirectory.path}/worker.js')
      ..writeAsStringSync(
        'console.log("ChronoSync");\n//# sourceMappingURL=worker.js.map\n',
      );

    sanitizeWebReleaseArtifacts(releaseDirectory);

    expect(
      File('${releaseDirectory.path}/worker.js.map').existsSync(),
      isFalse,
    );
    expect(
      File('${releaseDirectory.path}/worker.js.deps').existsSync(),
      isFalse,
    );
    expect(script.readAsStringSync(), 'console.log("ChronoSync");\n');
    expect(webReleaseArtifactProblems(releaseDirectory), isEmpty);
  });
}
