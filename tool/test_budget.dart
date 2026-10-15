/// The tests' time budget, as a gate: reads the JSON reports of test runs
/// and fails when one test, one test file (its loading included) or a
/// whole run took longer than `tool/test_budget.txt` allows. A file over
/// the suite limit can be given a limit of its own there, with the card
/// that brings it back under; `--times` prints every file's time instead,
/// and `--running` the tests a report has started and not finished (a run
/// that seems to hang).
///
/// ```sh
/// dart test --file-reporter json:ptome.json        # in packages/ptome
/// dart run tool/test_budget.dart ptome=packages/ptome/ptome.json [...]
/// ```
library;

import 'dart:convert';
import 'dart:io';

const budgetPath = 'tool/test_budget.txt';

void main(List<String> arguments) {
  final args = [...arguments];
  final times = args.remove('--times');
  if (args.remove('--running')) {
    for (final arg in args) {
      final at = arg.indexOf('=');
      for (final name in Run.unfinished(File(arg.substring(at + 1)))) {
        stdout.writeln('  ${arg.substring(0, at)}: running: $name');
      }
    }
    return;
  }
  if (args.isEmpty || args.any((a) => !a.contains('='))) {
    stderr.writeln(
      'usage: dart run tool/test_budget.dart [--times] PACKAGE=REPORT.json...',
    );
    exit(64);
  }
  final budget = Budget.parse(File(budgetPath).readAsLinesSync());
  final over = <String>[];
  var tests = 0;
  var files = 0;
  for (final arg in args) {
    final at = arg.indexOf('=');
    final package = arg.substring(0, at);
    final run = Run.read(File(arg.substring(at + 1)));
    tests += run.tests.length;
    files += run.suites.length;
    if (run.seconds > budget.run) {
      over.add('$package: the run took ${_s(run.seconds)} (${_s(budget.run)})');
    }
    for (final MapEntry(key: path, value: seconds) in run.suites.entries) {
      final name = '$package/$path';
      final limit = budget.suites[name] ?? budget.suite;
      if (times) stdout.writeln('${_s(seconds).padLeft(8)}  $name');
      if (seconds > limit) {
        over.add('$name took ${_s(seconds)} (${_s(limit)})');
      }
    }
    for (final (:name, :path, :seconds) in run.tests) {
      final limit = budget.suites.containsKey('$package/$path')
          ? double.infinity
          : budget.test;
      if (seconds > limit) {
        over.add('$package/$path: "$name" took ${_s(seconds)} (${_s(limit)})');
      }
    }
  }
  stdout.writeln(
    'budget: $tests tests in $files files; ${over.length} over the budget',
  );
  for (final line in over) {
    stdout.writeln('  OVER BUDGET: $line');
  }
  exit(over.isEmpty ? 0 : 1);
}

/// A test's name in a program of several files (`tool/shard.dart
/// --programs`): its file's group, then its own name.
final RegExp _inProgram = RegExp(r'^(test/\S+_test\.dart) ');

String _s(double seconds) => '${seconds.toStringAsFixed(2)} s';

/// The limits, in seconds: any one [test], any one test file ([suite],
/// unless [suites] gives the file a limit of its own) and any one [run].
final class Budget {
  Budget({
    required this.test,
    required this.suite,
    required this.run,
    required this.suites,
  });

  /// The budget file's lines: `test S`, `suite S`, `run S`, and
  /// `PACKAGE/PATH S CARD` for a file's own limit; `#` starts a comment.
  factory Budget.parse(List<String> lines) {
    final limits = <String, double>{};
    final suites = <String, double>{};
    for (final line in lines) {
      final words = line.split('#').first.trim().split(RegExp(r'\s+'));
      switch (words) {
        case [''] || []:
          break;
        case [final kind, final seconds] when !kind.contains('/'):
          limits[kind] = double.parse(seconds);
        case [final path, final seconds, _]:
          suites[path] = double.parse(seconds);
        default:
          throw FormatException('$budgetPath: not a limit: $line');
      }
    }
    double limit(String kind) =>
        limits[kind] ??
        (throw FormatException('$budgetPath: no `$kind` limit'));
    return Budget(
      test: limit('test'),
      suite: limit('suite'),
      run: limit('run'),
      suites: suites,
    );
  }

  final double test;
  final double suite;
  final double run;
  final Map<String, double> suites;
}

/// A run's times from its JSON report: each visible test's, each test
/// file's (from its first test, loading, to its last; in a program of
/// several files, `tool/shard.dart --programs`, the file's group's), and
/// the whole run's.
final class Run {
  Run(this.tests, this.suites, this.seconds);

  factory Run.read(File report) {
    final paths = <int, String>{};
    final started = <int, ({String name, int suite, int time, bool hidden})>{};
    final firstStart = <int, int>{};
    final lastDone = <int, int>{};
    // (A program's files, keyed below the suites' ids.)
    final fileKeys = <String, int>{};
    final files = <int, String>{};
    final fileOf = <int, int>{};
    int key(String path) => fileKeys[path] ??= () {
      final key = -1 - fileKeys.length;
      files[key] = path;
      return key;
    }();
    final tests = <({String name, String path, double seconds})>[];
    var end = 0;
    for (final line in report.readAsLinesSync()) {
      if (line.isEmpty) continue;
      final event = jsonDecode(line) as Map<String, Object?>;
      switch (event) {
        case {
          'type': 'suite',
          'suite': {'id': final int id, 'path': final String path},
        }:
          paths[id] = path;
        case {
          'type': 'testStart',
          'test': {
            'id': final int id,
            'name': final String name,
            'suiteID': final int suite,
          },
          'time': final int time,
        }:
          // (In a program, a test's file is its name's first word: the
          // file's group.)
          final file = switch (_inProgram.firstMatch(name)) {
            final m? => key(m[1]!),
            _ => null,
          };
          started[id] = (
            name: name,
            suite: suite,
            time: time,
            hidden: name.startsWith('loading '),
          );
          for (final key in [suite, ?file]) {
            firstStart[key] = switch (firstStart[key]) {
              final t? when t < time => t,
              _ => time,
            };
          }
          if (file != null) fileOf[id] = file;
        case {
          'type': 'testDone',
          'testID': final int id,
          'skipped': final bool skipped,
          'time': final int time,
        }:
          final start = started[id]!;
          for (final key in [start.suite, ?fileOf[id]]) {
            lastDone[key] = switch (lastDone[key]) {
              final t? when t > time => t,
              _ => time,
            };
          }
          if (!start.hidden && !skipped) {
            tests.add((
              name: start.name,
              path: files[fileOf[id]] ?? paths[start.suite]!,
              seconds: (time - start.time) / 1000,
            ));
          }
        case {'type': 'done', 'time': final int time}:
          end = time;
      }
    }
    return Run(tests, {
      for (final MapEntry(key: suite, value: start) in firstStart.entries)
        // (A program's files each, not the program: the run's limit
        // holds it.)
        if (paths[suite] ?? files[suite] case final path?
            when !path.startsWith('.dart_tool/'))
          path: ((lastDone[suite] ?? start) - start) / 1000,
    }, end / 1000);
  }

  /// The tests [report] has started and not finished, by name.
  static List<String> unfinished(File report) {
    final running = <int, String>{};
    for (final line in report.readAsLinesSync()) {
      if (!line.startsWith('{')) continue;
      final event = jsonDecode(line) as Map<String, Object?>;
      switch (event) {
        case {
          'type': 'testStart',
          'test': {'id': final int id, 'name': final String name},
        }:
          running[id] = name;
        case {'type': 'testDone', 'testID': final int id}:
          running.remove(id);
      }
    }
    return running.values.toList();
  }

  final List<({String name, String path, double seconds})> tests;

  /// Each test file's time, by its path in the package.
  final Map<String, double> suites;

  /// The whole run's time.
  final double seconds;
}
