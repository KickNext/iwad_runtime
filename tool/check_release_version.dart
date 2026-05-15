import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/check_release_version.dart <tag>');
    exitCode = 64;
    return;
  }

  final tag = args.single;
  final version = _pubspecVersion();
  final expectedTag = 'v$version';

  if (tag != expectedTag) {
    stderr.writeln(
      'Release tag "$tag" must match pubspec.yaml version "$expectedTag".',
    );
    exitCode = 1;
    return;
  }

  final changelog = File('CHANGELOG.md').readAsStringSync();
  final heading = RegExp(
    '^##\\s+${RegExp.escape(version)}\\s*\$',
    multiLine: true,
  );

  if (!heading.hasMatch(changelog)) {
    stderr.writeln('CHANGELOG.md must contain a "## $version" section.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Release version check passed for $expectedTag.');
}

String _pubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsLinesSync();

  for (final line in pubspec) {
    final match = RegExp(r'^version:\s*([^\s]+)\s*$').firstMatch(line);

    if (match != null) {
      return match.group(1)!;
    }
  }

  throw StateError('pubspec.yaml does not contain a top-level version field.');
}
