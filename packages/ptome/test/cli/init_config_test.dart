/// Tests for the `init-config` scaffold and the reusable CLI entrypoint.
///
/// Covers `lib/src/cli/init_config.dart` (file generation, `--force`,
/// misuse diagnostics, constraint freshness vs. this package's pubspec)
/// and `lib/src/cli/run.dart` (the `init-config` dispatch; the
/// conversion path is owned by `invoker_test.dart` and the bats e2e
/// suite). The scaffold end to end, in-process: its configuration is
/// test/cli/fixtures/scaffold_config.dart, which the workspace's analysis
/// holds clean, and it applies to every conversion, on worker isolates
/// too.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/api/api.dart' show configureCli;
import 'package:ptome/src/cli/init_config.dart';
import 'package:ptome/src/cli/run.dart';
import 'package:test/test.dart';

import 'fixtures/scaffold_config.dart' as scaffold;

/// Finds this package's root (the directory holding its pubspec).
String findPackageRoot() {
  var dir = Directory.current;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: ptome')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'ptome package root not found above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Creates an empty temp directory, deleted after the test.
Directory makeTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Generates the scaffold into a fresh temp directory, asserting success.
Directory generateScaffold([List<String> extraArgs = const <String>[]]) {
  final dir = makeTempDir('init-config-test');
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runInitConfig([dir.path, ...extraArgs], out: out, err: err);
  expect(code, equals(0), reason: 'stderr: $err');
  expect(err.toString(), isEmpty);
  return dir;
}

void main() {
  group('runInitConfig', () {
    test('generates a pubspec, configuration, main and README', () {
      final dir = generateScaffold();
      final name = dir.path
          .split(Platform.pathSeparator)
          .last
          .toLowerCase()
          .replaceAll('-', '_');
      final pubspec = File('${dir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: $name'));
      expect(pubspec, contains('ptome: $scaffoldPtomeConstraint'));
      expect(pubspec, contains('sdk: $scaffoldSdkConstraint'));

      final config = File('${dir.path}/lib/config.dart').readAsStringSync();
      expect(config, contains('final ptome = Ptome('));

      final main = File('${dir.path}/bin/main.dart').readAsStringSync();
      expect(main, contains("import 'package:ptome/cli.dart';"));
      expect(main, contains("import 'package:$name/config.dart';"));
      expect(main, contains('runCli(args, ptome: ptome)'));

      final readme = File('${dir.path}/README.md').readAsStringSync();
      expect(readme, contains('dart compile exe bin/main.dart'));
    });

    test('sanitizes the project name from the directory basename', () {
      final parent = makeTempDir('init-config-test');
      final target = '${parent.path}/My-Custom.Config';
      final code = runInitConfig(
        [target],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, equals(0));
      final pubspec = File('$target/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: my_custom_config'));
      final main = File('$target/bin/main.dart').readAsStringSync();
      expect(main, contains("import 'package:my_custom_config/config.dart';"));
    });

    test('refuses to overwrite without --force, overwrites with it', () {
      final dir = generateScaffold();
      final err = StringBuffer();
      final code = runInitConfig([dir.path], out: StringBuffer(), err: err);
      expect(code, equals(1));
      expect(err.toString(), contains('refusing to overwrite'));
      expect(err.toString(), contains('--force'));

      final forced = runInitConfig(
        [dir.path, '--force'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(forced, equals(0));
      expect(File('${dir.path}/bin/main.dart').existsSync(), isTrue);
    });

    test('reports misuse and answers --help', () {
      var err = StringBuffer();
      expect(
        runInitConfig(['--bogus'], out: StringBuffer(), err: err),
        equals(1),
      );
      expect(err.toString(), contains('unknown option'));

      err = StringBuffer();
      expect(
        runInitConfig(['a', 'b'], out: StringBuffer(), err: err),
        equals(1),
      );
      expect(err.toString(), contains('at most one directory'));

      final out = StringBuffer();
      expect(
        runInitConfig(['--help'], out: out, err: StringBuffer()),
        equals(0),
      );
      expect(out.toString(), contains('Usage: ptome init-config'));
    });

    test('scaffold constraints match this package', () {
      // The generated pubspec must track releases: the asciidoctor
      // constraint matches this package's version and the SDK constraint
      // matches its own.
      final pubspec = File('${findPackageRoot()}/pubspec.yaml')
          .readAsStringSync();
      final version = RegExp(
        r'^version: (\S+)$',
        multiLine: true,
      ).firstMatch(pubspec)![1]!;
      expect(scaffoldPtomeConstraint, equals('^$version'));
      final sdk = RegExp(
        r'^\s+sdk: (\S+)$',
        multiLine: true,
      ).firstMatch(pubspec)![1]!;
      expect(scaffoldSdkConstraint, equals(sdk));
    });
  });

  group('runCliCode', () {
    test(
      'dispatches init-config and reports --version without converting',
      () async {
        final dir = makeTempDir('init-config-test');
        final code = await runCliCode(
          ['init-config', dir.path],
          out: StringBuffer(),
          err: StringBuffer(),
        );
        expect(code, equals(0));
        expect(File('${dir.path}/pubspec.yaml').existsSync(), isTrue);

        final out = StringBuffer();
        final versionCode = await runCliCode(
          ['--version'],
          out: out,
          err: StringBuffer(),
        );
        expect(versionCode, equals(0));
        expect(out.toString(), contains('Asciidoctor'));
      },
    );

    test('--progress reports each phase as it finishes', () async {
      final dir = makeTempDir('progress-test');
      final input = File('${dir.path}/doc.adoc')..writeAsStringSync('Text.\n');
      final err = StringBuffer();
      final code = await runCliCode(
        ['--progress', input.path],
        out: StringBuffer(),
        err: err,
      );
      expect(code, equals(0));
      for (final phase in ['parse', 'convert', 'write']) {
        expect(
          err.toString(),
          matches(RegExp('ptome: .*doc.adoc: $phase done in \\d+ ms')),
        );
      }
      expect(err.toString(), isNot(contains('Total time')));
    });

    test('returns 1 and reports uncaught errors', () async {
      // A conversion failure under `--trace` rethrows, exercising the
      // uncaught-exception path: message plus backtrace on the error sink,
      // exit 1.
      final dir = makeTempDir('init-config-test');
      final input = File('${dir.path}/input.adoc')..writeAsStringSync('hi\n');
      final err = StringBuffer();
      final code = await runCliCode(
        ['--trace', '-E', 'bogus', '-T', dir.path, input.path],
        out: StringBuffer(),
        err: err,
      );
      expect(code, equals(1));
      expect(err.toString(), contains("unknown template engine 'bogus'"));
    });
  });

  group('the scaffold end to end', () {
    test('serves the current directory without a target', () {
      final parent = makeTempDir('init-config-test');
      final current = Directory('${parent.path}/here')..createSync();
      final code = runInitConfig(
        [],
        out: StringBuffer(),
        err: StringBuffer(),
        current: current.path,
      );
      expect(code, equals(0));
      expect(File('${current.path}/pubspec.yaml').existsSync(), isTrue);
      expect(File('${current.path}/lib/config.dart').existsSync(), isTrue);
      expect(
        File('${current.path}/bin/main.dart').readAsStringSync(),
        contains("import 'package:here/config.dart';"),
      );
    });

    test('its configuration is the fixture the workspace analyzes', () {
      final dir = generateScaffold();
      expect(
        File('${dir.path}/lib/config.dart').readAsStringSync(),
        File('test/cli/fixtures/scaffold_config.dart').readAsStringSync(),
      );
    });

    test(
      'the configuration applies to every conversion, on workers too',
      () async {
        final dir = makeTempDir('init-config-test');
        final a = File('${dir.path}/a.adoc')
          ..writeAsStringSync('See issue:7[].');
        final b = File('${dir.path}/b.adoc')..writeAsStringSync('Plain.');
        final err = StringBuffer();
        final code = await runCliCode(
          ['-j', '2', a.path, b.path],
          out: StringBuffer(),
          err: err,
          configure: (options) => configureCli(scaffold.ptome, options),
        );
        expect(code, equals(0), reason: '$err');
        final html = File('${dir.path}/a.html').readAsStringSync();
        expect(html, contains('<a href="https://example.org/issues/7">#7</a>'));
        expect(html, contains('<div class="paragraph custom">'));
        expect(
          File('${dir.path}/b.html').readAsStringSync(),
          contains('<div class="paragraph custom">'),
        );
      },
    );
  });
}
