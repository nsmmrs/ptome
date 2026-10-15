/// The corpus (test/corpus), split across the `test/corpus_<n>_test.dart`
/// files: every case converts with ptome, with `asciidoctor-compat`, to
/// the files the Asciidoctor command line writes for it. Text formats
/// match the golden file's bytes (its generator stamp aside); an EPUB the
/// files in it; a PDF must be the one last found equal to its golden,
/// kept by its hash (ptome.yml). A PDF that isn't fails until recording
/// (ORACLES=record, or CORPUS_RECHECK) compares its pages, pixel for
/// pixel, and its outline and page labels, with Poppler's.
library;

import 'dart:convert';

import 'package:ptome/ptome.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:test/test.dart';

import 'support/corpus.dart';

/// The corpus's tests: those of every [parts]th case, from the
/// [part]th (the corpus is split across test files, which run side by
/// side).
void corpusTests({required int part, required int parts}) {
  final corpus = loadCorpus();
  final attributes = {...corpus.attributes, 'asciidoctor-compat': 'true'};

  // On JavaScript the PDF and EPUB backends are loaded on demand.
  setUpAll(() async {
    for (final format in [Format.pdf, Format.epub3]) {
      await const Ptome().loadBackend(format.backend);
    }
  });

  for (final (i, c) in corpus.cases.indexed) {
    if (i % parts != part) continue;
    group(c.name, () {
      for (final MapEntry(key: format, value: golden) in c.goldens.entries) {
        // (A PDF on JavaScript is compressed by Dart's own deflate, where
        // the VM's is zlib: the hash found equal on the VM can't be its,
        // and its pages are compared on the VM only. Its books are
        // compared here as there, file by file.)
        if (format == Format.pdf && _onJs) continue;
        test(
          format.name,
          skip: switch (c.defects[format]) {
            final defect? => "Asciidoctor's defect, not reproduced: $defect",
            _ => null,
          },
          () async {
            final want = io.readBytes(golden);
            final got = await c.convert(format, attributes);
            if (!format.expensive) {
              final (a, b) = (_text(want), _text(got));
              if (sha256Of(utf8.encode(a)) == sha256Of(utf8.encode(b))) {
                return;
              }
              fail(
                'differs from ${corpus.release} at ${firstDifference(a, b)}',
              );
            }
            final hash = sha256Of(got);
            if (c.verified[format] == hash && !_recheck) return;
            // (A PDF other than the one found equal is compared again by
            // its pages, Poppler's, only when recording: everywhere else it
            // fails the same way. An EPUB's files are compared here.)
            final String result;
            if (format == Format.epub3) {
              result = compareEntries(want, got);
            } else if (_recheck || _recording) {
              result =
                  comparePages(want, got) ??
                  (throw StateError('comparing pages needs pdftoppm'));
            } else {
              fail(
                "not the PDF found equal to ${corpus.release}'s "
                '(ptome.yml): compare its pages again, '
                'ORACLES=record dart test -t corpus, with Poppler installed',
              );
            }
            if (result != 'identical') {
              fail('differs from ${corpus.release}: $result');
            }
            // Equal: kept by its hash from now on, when recording (commit
            // ptome.yml); a run doesn't write it.
            if (_recording || _recheck) c.promote(corpus.release, format, hash);
          },
        );
      }
    });
  }
}

String _text(List<int> bytes) =>
    withoutGenerator(utf8.decode(bytes, allowMalformed: true));

const _onJs = bool.fromEnvironment('dart.library.js_interop');

/// Whether every PDF and EPUB is compared again, its hash recorded or not
/// (`CORPUS_RECHECK=1`): after the comparison itself changes.
final bool _recheck = io.environment['CORPUS_RECHECK'] != null;

/// Whether the outside tools are asked again (ORACLES=record, as
/// test/support/oracles.dart has it).
final bool _recording = io.environment['ORACLES'] == 'record';
