import 'dart:io';

void sanitizeWebReleaseArtifacts(Directory releaseDirectory) {
  if (!releaseDirectory.existsSync()) {
    return;
  }
  for (final FileSystemEntity entity in releaseDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }
    final String path = entity.path;
    if (path.endsWith('.deps') || path.endsWith('.map')) {
      entity.deleteSync();
      continue;
    }
    if (!_isTextAsset(path)) {
      continue;
    }
    final String contents = entity.readAsStringSync();
    final String sanitized = contents.replaceAll(
      RegExp(r'^\s*//[#@]\s*sourceMappingURL=.*(?:\r?\n)?', multiLine: true),
      '',
    );
    if (sanitized != contents) {
      entity.writeAsStringSync(sanitized);
    }
  }
}

List<String> webReleaseArtifactProblems(Directory releaseDirectory) {
  if (!releaseDirectory.existsSync()) {
    return <String>[
      '${releaseDirectory.path}: release directory does not exist',
    ];
  }

  final String root = releaseDirectory.absolute.path;
  final List<String> problems = <String>[];
  for (final FileSystemEntity entity in releaseDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }
    final String relativePath = entity.absolute.path.substring(root.length + 1);
    if (relativePath.endsWith('.deps') || relativePath.endsWith('.map')) {
      problems.add('$relativePath: compiler metadata must not ship');
      continue;
    }
    if (!_isTextAsset(relativePath)) {
      continue;
    }
    final String contents = entity.readAsStringSync();
    if (contents.contains('sourceMappingURL=')) {
      problems.add('$relativePath: contains a source-map reference');
    }
    if (RegExp(r'file:///(?:Users|home)/').hasMatch(contents) ||
        contents.contains('/Users/')) {
      problems.add('$relativePath: contains an absolute local file URL');
    }
  }
  problems.sort();
  return problems;
}

bool _isTextAsset(String path) {
  return <String>[
    '.css',
    '.dart',
    '.html',
    '.js',
    '.json',
    '.txt',
  ].any(path.endsWith);
}

void main(List<String> arguments) {
  final bool sanitize = arguments.firstOrNull == '--sanitize';
  final List<String> paths = sanitize ? arguments.skip(1).toList() : arguments;
  final Directory releaseDirectory = Directory(
    paths.isEmpty ? 'build/web' : paths.single,
  );
  if (sanitize) {
    sanitizeWebReleaseArtifacts(releaseDirectory);
  }
  final List<String> problems = webReleaseArtifactProblems(releaseDirectory);
  if (problems.isEmpty) {
    stdout.writeln('Web release artifacts are sanitized.');
    return;
  }
  for (final String problem in problems) {
    stderr.writeln(problem);
  }
  exitCode = 1;
}
