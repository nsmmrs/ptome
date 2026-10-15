/// The units corpus's excerpts (test/units/corpus/excerpts), which
/// test/units/corpus_model_test.dart reads in place of the whole works
/// they come from, a few chapters where the whole is many:
///
/// - the Westminster Larger Catechism's first [_questions] questions;
/// - the KJV with only the chapters those questions' proof texts and the
///   commonplace book's quotations cite (each book's header kept, its
///   other chapters left out);
/// - the commonplace book, citing the two excerpts in place of the
///   wholes.
///
/// ```sh
/// dart run tool/units_excerpts.dart
/// ```
///
/// The whole works stay for the benchmarks and the throughput tool.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

const String _corpus = 'test/units/corpus';
const String _out = '$_corpus/excerpts';

/// How many of the catechism's questions the excerpt keeps.
const int _questions = 10;

void main() {
  // The catechism's first questions.
  final catechism = File('$_corpus/catechism/westminster-larger.adoc')
      .readAsStringSync();
  final starts = [
    for (final m in RegExp('^@ ', multiLine: true).allMatches(catechism))
      m.start,
  ];
  final catechismExcerpt =
      '${catechism.substring(0, starts[_questions]).trimRight()}\n';
  final quotations = File('$_corpus/quotations/commonplace.adoc')
      .readAsStringSync();

  // The chapters cited: the proof texts' and the KJV quotations'.
  final canon =
      (loadYaml(
            File('$_corpus/schemes/canon-protestant.yml').readAsStringSync(),
          ) as YamlMap)['book']
          as YamlList;
  final files = {
    for (final book in canon.cast<YamlMap>())
      '${book['abbr']}': '${book['file']}',
  };
  final cited = <String, Set<int>>{};
  final reference = RegExp(r'((?:\d )?[A-Z][a-z]+) (\d+)');
  void cite(String text) {
    for (final m in reference.allMatches(text)) {
      if (files[m[1]] case final file?) {
        (cited[file] ??= {}).add(int.parse(m[2]!));
      }
    }
  }

  for (final m in RegExp('<<([^>]*)>>').allMatches(catechismExcerpt)) {
    cite(m[1]!);
  }
  for (final m in RegExp(
    r'include::kjv\[unit="([^"]*)"',
  ).allMatches(quotations)) {
    cite(m[1]!);
  }

  // Each cited book: its header, and its cited chapters.
  final books = Directory('$_out/bible/kjv/books')..createSync(recursive: true);
  for (final entity in books.listSync()) {
    entity.deleteSync();
  }
  for (final MapEntry(key: file, value: chapters) in cited.entries) {
    final text = File('$_corpus/bible/kjv/books/$file').readAsStringSync();
    final heads = [
      for (final m in RegExp(r'^=== @(\d+)$', multiLine: true).allMatches(text))
        (m.start, int.parse(m[1]!)),
    ];
    final out = StringBuffer(text.substring(0, heads.first.$1));
    for (final (i, (start, chapter)) in heads.indexed) {
      if (!chapters.contains(chapter)) continue;
      final end = i + 1 < heads.length ? heads[i + 1].$1 : text.length;
      out.write(text.substring(start, end));
    }
    File('${books.path}/$file').writeAsStringSync('${'$out'.trimRight()}\n');
  }

  // The KJV's document, its books the excerpt's (in the canon's order),
  // its front matter and images the whole's.
  final kjv = File('$_corpus/bible/kjv/kjv.adoc').readAsLinesSync();
  final kept = cited.keys.toSet();
  File('$_out/bible/kjv/kjv.adoc').writeAsStringSync(
    '${[for (final line in kjv)
      if (RegExp(r'^include::books/(.+)\[\]$').firstMatch(line) case final m?)
        if (kept.contains(m[1])) line else null
      else if (line.startsWith('include::front/'))
        line.replaceFirst('include::', 'include::../../../bible/kjv/')
      else if (line == ':reproducible:')
        '$line\n:imagesdir: ../../../bible/kjv'
      else
        line].nonNulls.join('\n')}\n',
  );

  Directory('$_out/catechism').createSync(recursive: true);
  File('$_out/catechism/westminster-larger.adoc')
      .writeAsStringSync(catechismExcerpt);

  // The commonplace book, citing the excerpts (the other works whole).
  Directory('$_out/quotations').createSync(recursive: true);
  final works = RegExp(r'^:works: (.*)$', multiLine: true);
  File('$_out/quotations/commonplace.adoc').writeAsStringSync(
    quotations.replaceFirstMapped(works, (m) {
      final entries = [
        for (final entry in m[1]!.split('; '))
          switch (entry.split('=')) {
            [_, final path]
                when path == '../bible/kjv/kjv.adoc' ||
                    path == '../catechism/westminster-larger.adoc' =>
              entry,
            [final name, final path] => '$name=../$path',
            _ => entry,
          },
      ];
      return ':works: ${entries.join('; ')}';
    }),
  );
  stdout.writeln(
    'excerpts in $_out: $_questions questions, '
    '${cited.values.fold(0, (n, c) => n + c.length)} chapters of '
    '${cited.length} books',
  );
}
