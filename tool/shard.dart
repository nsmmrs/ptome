/// The test files of [packages] dealt into [shards] of about the same
/// time, by each file's time in `tool/test_times.txt` (a second for one it
/// doesn't list), the longest first, each to the shard with the least so
/// far (a package lighter than half a shard whole). Prints shard
/// [index]'s files, a line per package: the package and its files (paths
/// in the package; none for the whole package), for `dart test` there.
///
/// ```sh
/// dart run tool/shard.dart SHARDS INDEX PACKAGE...
/// dart run tool/shard.dart --programs N SHARDS INDEX PACKAGE...
/// dart run tool/shard.dart --times REPORT.json... > tool/test_times.txt
/// ```
///
/// With `--programs`, the shard's files go into about N test programs
/// instead, shared out over its packages by their time (each at least
/// one): in a package, `.dart_tool/test_programs/program<k>_test.dart`, of about the
/// same time, each file a group named for
/// its path (its `@TestOn` and `@Tags` the group's), declared and run
/// from the package's test world (`test/support/world.dart`'s
/// `resetWorld`, if it has one; `checkWorld` fails a file that changes it
/// while declaring its tests), and printed as the package, that folder and
/// how many programs are in it (to run side by side: `dart test -j`). A
/// program loads once for all its files, where `dart test` starts an
/// isolate, and compiles, for each file.
///
/// With `--times`, writes the times file from test runs' JSON reports,
/// each `PACKAGE=REPORT.json` (`dart test --file-reporter json:…`; CI's
/// Linux runners' are the file's).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const String _timesPath = 'tool/test_times.txt';

void main(List<String> arguments) {
  final args = [...arguments];
  if (args.isNotEmpty && args.first == '--times') {
    _writeTimes(args.skip(1));
    return;
  }
  int? programs;
  if (args.isNotEmpty && args.first == '--programs') {
    programs = int.parse(args[1]);
    args.removeRange(0, 2);
  }
  if (args.length < 3) {
    stderr.writeln('usage: dart run tool/shard.dart SHARDS INDEX PACKAGE...');
    exit(64);
  }
  final shards = int.parse(args[0]);
  final index = int.parse(args[1]);
  final times = {
    if (File(_timesPath).existsSync())
      for (final line in File(_timesPath).readAsLinesSync())
        if (line.isNotEmpty && !line.startsWith('#'))
          if (line.split(' ') case [final path, final seconds])
            path: double.parse(seconds),
  };
  final files =
      <(String, String, double)>[
        for (final package in args.skip(2))
          for (final entity in Directory(
            'packages/$package/test',
          ).listSync(recursive: true))
            if (entity is File && entity.path.endsWith('_test.dart'))
              () {
                final path = entity.path
                    .substring('packages/$package/'.length)
                    .replaceAll(r'\', '/');
                return (package, path, times['$package/$path'] ?? 1.0);
              }(),
      ]..sort((a, b) {
        final byTime = b.$3.compareTo(a.$3);
        return byTime != 0
            ? byTime
            : '${a.$1}/${a.$2}'.compareTo('${b.$1}/${b.$2}');
      });
  // (A package lighter than half a shard goes whole, so a shard runs few
  // packages, `dart test` starting once for each; a heavier one by its
  // files.)
  final total = files.fold(0.0, (t, f) => t + f.$3);
  final perPackage = <String, double>{};
  for (final (package, _, seconds) in files) {
    perPackage[package] = (perPackage[package] ?? 0) + seconds;
  }
  final units =
      <(String, String?, double)>[
        for (final MapEntry(key: package, value: seconds) in perPackage.entries)
          if (seconds <= total / shards / 2) (package, null, seconds),
        for (final (package, path, seconds) in files)
          if (perPackage[package]! > total / shards / 2)
            (package, path, seconds),
      ]..sort((a, b) {
        final byTime = b.$3.compareTo(a.$3);
        return byTime != 0
            ? byTime
            : '${a.$1}/${a.$2}'.compareTo('${b.$1}/${b.$2}');
      });
  final load = List.filled(shards, 0.0);
  final dealt = List.generate(shards, (_) => <(String, String?)>[]);
  for (final (package, path, seconds) in units) {
    var least = 0;
    for (var s = 1; s < shards; s++) {
      if (load[s] < load[least]) least = s;
    }
    load[least] += seconds;
    dealt[least].add((package, path));
  }
  final byPackage = <String, List<String>>{};
  for (final (package, path) in dealt[index]) {
    final paths = byPackage[package] ??= [];
    if (path != null) paths.add(path);
  }
  final packages = byPackage.keys.toList()..sort();
  if (programs != null) {
    // (A whole package: every file of it.)
    final mine = {
      for (final package in packages)
        package: byPackage[package]!.isEmpty
            ? [
                for (final (p, path, _) in files)
                  if (p == package) path,
              ]
            : byPackage[package]!,
    };
    double timeOf(String package, String path) =>
        times['$package/$path'] ?? 1.0;
    final count = _share(programs, {
      for (final package in packages)
        package: mine[package]!.fold(
          0.0,
          (t, path) => t + timeOf(package, path),
        ),
    });
    for (final package in packages) {
      final n = _writePrograms(
        package,
        mine[package]!,
        count[package]!,
        (path) => timeOf(package, path),
      );
      stdout.writeln('$package $_programsPath $n');
    }
    return;
  }
  for (final package in packages) {
    final paths = byPackage[package]!;
    // (A whole package: no files named, `dart test` runs them all.)
    stdout.writeln(
      paths.isEmpty ? package : '$package ${(paths..sort()).join(' ')}',
    );
  }
}

/// A test's name in a program of several files: its file's group, then
/// its own name.
final RegExp _inProgram = RegExp(r'^(test/\S+_test\.dart) ');

/// [programs] shared out over packages by their [times]: each its share,
/// rounded, but at least one.
Map<String, int> _share(int programs, Map<String, double> times) {
  final total = times.values.fold(0.0, (t, s) => t + s);
  return {
    for (final MapEntry(key: package, value: seconds) in times.entries)
      package: total > 0
          ? math.max(1, (programs * seconds / total).round())
          : 1,
  };
}

/// Where in a package `--programs` writes its test programs.
const String _programsPath = '.dart_tool/test_programs';

/// Writes [package]'s test files [paths] into at most [count] programs of
/// about the same time ([timeOf] each file's), the longest first, each to
/// the program with the least so far; returns how many.
int _writePrograms(
  String package,
  List<String> paths,
  int count,
  double Function(String path) timeOf,
) {
  final dir = Directory('packages/$package/$_programsPath');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final world = File('packages/$package/test/support/world.dart').existsSync();
  final sorted = [...paths]
    ..sort((a, b) {
      final byTime = timeOf(b).compareTo(timeOf(a));
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  final n = count < sorted.length ? count : sorted.length;
  final load = List.filled(n, 0.0);
  final dealt = List.generate(n, (_) => <String>[]);
  for (final path in sorted) {
    var least = 0;
    for (var p = 1; p < n; p++) {
      if (load[p] < load[least]) least = p;
    }
    load[least] += timeOf(path);
    dealt[least].add(path);
  }
  for (final (k, mine) in dealt.indexed) {
    mine.sort();
    final source = StringBuffer()
      ..writeln('// Generated by tool/shard.dart --programs: do not edit.')
      ..writeln('library;')
      ..writeln()
      ..writeln("import 'package:test/test.dart';")
      ..writeln();
    if (world) source.writeln("import '../../test/support/world.dart';");
    for (final (i, path) in mine.indexed) {
      source.writeln("import '../../$path' as s$i;");
    }
    source
      ..writeln()
      ..writeln('void main() {');
    for (final (i, path) in mine.indexed) {
      final text = File('packages/$package/$path').readAsStringSync();
      final testOn = RegExp(
        r"""^@TestOn\((['"][^'"]*['"])\)""",
        multiLine: true,
      ).firstMatch(text)?.group(1);
      final tags = RegExp(
        r'^@Tags\((\[[^\]]*\])\)',
        multiLine: true,
      ).firstMatch(text)?.group(1);
      source.writeln("  group('$path', () {");
      if (world) source.writeln('    resetWorld();\n    setUpAll(resetWorld);');
      source.writeln('    s$i.main();');
      // (A file that changes the world while declaring its tests changes
      // it for the files before it: the program fails to load.)
      if (world) source.writeln("    checkWorld('$path');");
      source.writeln(
        '  }${testOn == null ? '' : ', testOn: $testOn'}'
        '${tags == null ? '' : ', tags: $tags'});',
      );
    }
    source.writeln('}');
    File('${dir.path}/program${k}_test.dart').writeAsStringSync('$source');
  }
  return n;
}

/// Writes the times file from the JSON reports [reports]
/// (`PACKAGE=REPORT.json`): each test file's time, its loading included.
void _writeTimes(Iterable<String> reports) {
  final times = <String, double>{};
  for (final report in reports) {
    final at = report.indexOf('=');
    final package = report.substring(0, at);
    // (Each test's file: its suite's, or in a program of several files,
    // its name's first word, the file's group.)
    final paths = <int, String>{};
    final fileOf = <int, String>{};
    final first = <String, int>{};
    final last = <String, int>{};
    for (final line in File(report.substring(at + 1)).readAsLinesSync()) {
      if (line.isEmpty) continue;
      final event = jsonDecode(line) as Map<String, Object?>;
      switch (event) {
        case {
          'type': 'suite',
          'suite': {'id': final int id, 'path': final String path},
        }:
          paths[id] = path.replaceAll(r'\', '/');
        case {
          'type': 'testStart',
          'test': {
            'id': final int id,
            'name': final String name,
            'suiteID': final int suite,
          },
          'time': final int time,
        }:
          final file = switch (_inProgram.firstMatch(name)) {
            final m? => m[1]!,
            _ => paths[suite],
          };
          if (file == null || file.startsWith('.dart_tool/')) continue;
          fileOf[id] = file;
          first[file] ??= time;
        case {
          'type': 'testDone',
          'testID': final int id,
          'time': final int time,
        }:
          if (fileOf[id] case final file?) last[file] = time;
      }
    }
    for (final MapEntry(key: file, value: start) in first.entries) {
      times['$package/$file'] = ((last[file] ?? start) - start) / 1000;
    }
  }
  final keys = times.keys.toList()..sort();
  stdout
    ..writeln("# Each test file's time, in seconds, on CI's Linux runners in a")
    ..writeln(
      "# shard's programs (tool/test_shard.sh): tool/shard.dart deals the files",
    )
    ..writeln(
      '# into shards by it. Written by `dart run tool/shard.dart --times` from',
    )
    ..writeln('# a run\'s reports, or from the times a CI shard prints.');
  for (final key in keys) {
    stdout.writeln('$key ${times[key]!.toStringAsFixed(2)}');
  }
}
