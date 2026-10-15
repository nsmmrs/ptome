/// ptome's fixes of bugs Asciidoctor still has, and its other deliberate
/// differences (benchmark/PARITY.md): each folder of test/upstream_fixes
/// holds a document, the files it reads, and in check.yml what ptome's
/// output must (and must not) contain. They were the CLI tests that failed
/// on the gem and passed here (test/bugfix, test/divergences).
///
/// check.yml: `format` (html5 by default), `standalone`, `doctype`,
/// `attributes`; then `contains`, `excludes` (text), `contains_joined`
/// (text with the line feeds removed), `counts` (text: times), `warns`
/// (messages), `quiet` (no warning), `well_formed` (XML, with xmllint),
/// `epub_contains` and `epub_excludes` (`{files: "EPUB/*.xhtml",
/// pattern: "a regular expression"}`: files in the EPUB).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plain_compression/plain_compression.dart' show readZip;
import 'package:ptome/io.dart';
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/oracles.dart';
import 'support/pdf_tools.dart';

/// The tools' runs, recorded (test/oracles/upstream_fixes.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('upstream_fixes', compressed: true);
  final root = Directory('test/upstream_fixes').absolute.path;
  final dirs = Directory(root).listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in dirs) {
    final check = loadYaml(
      File(p.join(dir.path, 'check.yml')).readAsStringSync(),
    ) as YamlMap;
    test(p.basename(dir.path), () async {
      final format = Backend.values.byName(
        check['format'] as String? ?? 'html5',
      );
      final scratch = p.join(dir.path, '.ptome');
      addTearDown(() {
        if (Directory(scratch).existsSync()) {
          Directory(scratch).deleteSync(recursive: true);
        }
      });
      // As the command line converts (unsafe by default).
      final document = await const Ptome(safe: SafeMode.unsafe).convertFile(
        p.join(dir.path, 'input.adoc'),
        toDir: scratch,
        mkdirs: true,
        backend: format,
        doctype: switch (check['doctype']) {
          final String name => Doctype.values.byName(name),
          _ => null,
        },
        standalone: check['standalone'] as bool? ?? true,
        attributes: {
          for (final MapEntry(:key, :value)
              in (check['attributes'] as YamlMap? ?? YamlMap()).entries)
            '$key': '$value',
        },
      );
      final written = Directory(scratch)
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.css'))
          .single;
      final messages = [
        for (final d in document.diagnostics)
          if (d.severity >= Severity.warning) d.message,
      ];
      if (check['quiet'] == true) {
        expect(messages, isEmpty, reason: 'warnings');
      }
      for (final message in check['warns'] as YamlList? ?? YamlList()) {
        expect(messages, contains(contains('$message')));
      }
      if (format == Backend.epub3) {
        final entries = readZip(written.readAsBytesSync());
        Iterable<String> texts(Object? glob) {
          final pattern = '$glob';
          final folder = p.posix.dirname(pattern);
          final suffix = p.posix.basename(pattern).replaceFirst('*', '');
          return [
            for (final entry in entries)
              if (p.posix.dirname(entry.name) == folder &&
                  p.posix.basename(entry.name).endsWith(suffix) &&
                  (pattern.contains('*') ||
                      p.posix.basename(entry.name) == suffix))
                utf8.decode(entry.bytes),
          ];
        }

        for (final rule in check['epub_contains'] as YamlList? ?? YamlList()) {
          final re = RegExp('${(rule as YamlMap)['pattern']}');
          expect(
            texts(rule['files']).any(re.hasMatch),
            isTrue,
            reason: '$rule',
          );
        }
        for (final rule in check['epub_excludes'] as YamlList? ?? YamlList()) {
          final re = RegExp('${(rule as YamlMap)['pattern']}');
          expect(
            texts(rule['files']).any(re.hasMatch),
            isFalse,
            reason: '$rule',
          );
        }
        return;
      }
      final output = utf8.decode(written.readAsBytesSync());
      for (final text in check['contains'] as YamlList? ?? YamlList()) {
        expect(output, contains('$text'));
      }
      for (final text in check['excludes'] as YamlList? ?? YamlList()) {
        expect(output, isNot(contains('$text')));
      }
      for (final text in check['contains_joined'] as YamlList? ?? YamlList()) {
        expect(output.replaceAll('\n', ''), contains('$text'));
      }
      for (final MapEntry(:key, :value)
          in (check['counts'] as YamlMap? ?? YamlMap()).entries) {
        expect('$key'.allMatches(output).length, value, reason: '$key');
      }
      if (check['well_formed'] == true) {
        final xmllint = recordedRunSync(_recorded, 'xmllint', [
          '--noout',
          written.path,
        ]);
        expect(xmllint.exitCode, 0, reason: '${xmllint.stderr}');
      }
    });
  }
}
