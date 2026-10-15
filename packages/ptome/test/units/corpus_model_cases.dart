// The units corpus (test/units/corpus, NOTICE.md): real documents written
// in numbered units (the KJV, the catechism and the commonplace book as
// excerpts, test/units/corpus/excerpts by tool/units_excerpts.dart: the
// wholes are the benchmarks'), each read as conversion reads it and its
// units model (test/units/model_dump.dart) compared with the model frozen in
// test/units/corpus/model. A change to the model is a change to those
// files, made on purpose:
//
//   UNITS_MODEL_UPDATE=1 dart test test/units/corpus_model_0_test.dart \
//     test/units/corpus_model_1_test.dart test/units/corpus_model_2_test.dart \
//     test/units/corpus_model_3_test.dart
//
// and reviewed in the diff of the dumps (zcat).

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

import 'model_dump.dart';

const String _corpus = 'test/units/corpus';

/// The corpus's documents (the files they include aside).
const List<String> _documents = [
  'bible/bsb-study/study.adoc',
  'bible/kjv/genesis.adoc',
  'excerpts/bible/kjv/kjv.adoc',
  'excerpts/catechism/westminster-larger.adoc',
  'classics/ethics/ethics-en.adoc',
  'classics/ethics/ethics-grc.adoc',
  'classics/euthyphro/euthyphro-en.adoc',
  'classics/euthyphro/euthyphro-grc.adoc',
  'hymns/otterbein-hymnal.adoc',
  'law-eu/gdpr.adoc',
  'law-uk/computer-misuse-act-1990.adoc',
  'law-us/title-5-chapter-5.adoc',
  'liturgy/bcp-1662/litany.adoc',
  'liturgy/bcp-1662/morning-prayer.adoc',
  'liturgy/bcp-1662/psalter.adoc',
  'excerpts/quotations/commonplace.adoc',
  'quran/ar/quran-ar.adoc',
  'quran/en/quran-en.adoc',
  'specs/cpp-basic.adoc',
  'suttas/dn1/dn1-en.adoc',
  'suttas/dn1/dn1-pli.adoc',
  'suttas/mn1/mn1-en.adoc',
  'suttas/mn1/mn1-pli.adoc',
  'suttas/mn10/mn10-en.adoc',
  'suttas/mn10/mn10-pli.adoc',
];

final bool _update = Platform.environment['UNITS_MODEL_UPDATE'] == '1';

/// The model tests: those of every [parts]th document, from the [part]th
/// (split across `corpus_model_<n>_test.dart`, which run side by side).
void corpusModelTests({required int part, required int parts}) {
  final root = Directory(_corpus).absolute.path;
  for (final (i, doc) in _documents.indexed) {
    if (i % parts != part) continue;
    test(doc, () {
      final document = loadFile(
        '$_corpus/$doc',
        options: const AsciidoctorOptions(safe: SafeMode.unsafe),
      );
      final analysis = document.unitsSession?.analysis;
      expect(analysis, isNotNull, reason: 'not read as a document in units');
      final got = dumpLines(analysis!, root);
      final frozen = File('$_corpus/model/$doc.jsonl.gz');
      if (_update) {
        frozen
          ..createSync(recursive: true)
          ..writeAsBytesSync(
            gzip.encode(utf8.encode(got.map((l) => '$l\n').join())),
          );
        return;
      }
      expect(
        frozen.existsSync(),
        isTrue,
        reason: 'no frozen model: run with UNITS_MODEL_UPDATE=1',
      );
      final want = const LineSplitter().convert(
        utf8.decode(gzip.decode(frozen.readAsBytesSync())),
      );
      final differences = _differences(want, got);
      expect(
        differences,
        isEmpty,
        reason:
            '${differences.join('\n')}\n'
            '(a change on purpose: UNITS_MODEL_UPDATE=1)',
      );
    });
  }
}

/// Where the records of [want] and [got] differ, part by part: the
/// counts, and the first record that differs.
List<String> _differences(List<String> want, List<String> got) {
  Map<String, List<String>> byPart(List<String> lines) {
    final parts = <String, List<String>>{};
    for (final line in lines) {
      final part = RegExp('^{"part":"([a-z]+)"').firstMatch(line)?[1] ?? '?';
      (parts[part] ??= []).add(line);
    }
    return parts;
  }

  final wanted = byPart(want);
  final found = byPart(got);
  final differences = <String>[];
  for (final part in {...wanted.keys, ...found.keys}) {
    final frozen = wanted[part] ?? const <String>[];
    final now = found[part] ?? const <String>[];
    if (_firstDifference(frozen, now) case final i?) {
      differences.add(
        '$part: ${frozen.length} frozen, ${now.length} now; first at $i:\n'
        '  frozen ${frozen._at(i)}\n'
        '  now    ${now._at(i)}',
      );
    }
  }
  return differences;
}

int? _firstDifference(List<String> a, List<String> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length
      ? null
      : (a.length < b.length ? a.length : b.length);
}

extension on List<String> {
  String _at(int i) => i < length ? this[i] : '(none)';
}
