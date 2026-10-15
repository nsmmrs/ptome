/// The test files of [packages] dealt into [shards] of about the same
/// time, by each file's time in `tool/test_times.txt` (a second for one it
/// doesn't list), the longest first, each to the shard with the least so
/// far (a package lighter than half a shard whole). Prints shard
/// [index]'s files, a line per package: the package and its files (paths
/// in the package; none for the whole package), for `dart test` there.
///
/// ```sh
/// dart run tool/shard.dart SHARDS INDEX PACKAGE...
/// dart run tool/shard.dart --times REPORT.json... > tool/test_times.txt
/// ```
///
/// With `--times`, writes the times file from test runs' JSON reports,
/// each `PACKAGE=REPORT.json` (`dart test --file-reporter json:…`, one file
/// at a time: `-j 1`).
library;

import 'dart:convert';
import 'dart:io';

const String _timesPath = 'tool/test_times.txt';

void main(List<String> args) {
  if (args.isNotEmpty && args.first == '--times') {
    _writeTimes(args.skip(1));
    return;
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
  for (final MapEntry(key: package, value: paths)
      in byPackage.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    // (A whole package: no files named, `dart test` runs them all.)
    stdout.writeln(
      paths.isEmpty ? package : '$package ${(paths..sort()).join(' ')}',
    );
  }
}

/// Writes the times file from the JSON reports [reports]
/// (`PACKAGE=REPORT.json`): each test file's time, its loading included.
void _writeTimes(Iterable<String> reports) {
  final times = <String, double>{};
  for (final report in reports) {
    final at = report.indexOf('=');
    final package = report.substring(0, at);
    final paths = <int, String>{};
    final first = <int, int>{};
    final last = <int, int>{};
    final suiteOf = <int, int>{};
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
          'test': {'id': final int id, 'suiteID': final int suite},
          'time': final int time,
        }:
          suiteOf[id] = suite;
          first[suite] ??= time;
        case {
          'type': 'testDone',
          'testID': final int id,
          'time': final int time,
        }:
          last[suiteOf[id]!] = time;
      }
    }
    for (final MapEntry(key: suite, value: start) in first.entries) {
      if (paths[suite] case final path?) {
        times['$package/$path'] = ((last[suite] ?? start) - start) / 1000;
      }
    }
  }
  final keys = times.keys.toList()..sort();
  stdout
    ..writeln('# Each test file\'s time, in seconds, run alone (dart test')
    ..writeln('# -j 1): tool/shard.dart deals the files into shards by it.')
    ..writeln('# Written by `dart run tool/shard.dart --times`.');
  for (final key in keys) {
    stdout.writeln('$key ${times[key]!.toStringAsFixed(2)}');
  }
}
