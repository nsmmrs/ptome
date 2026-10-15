// The PDF converter's output beyond its pages: destinations stable from
// run to run, and the viewer settings from the theme. (How its pages look
// against asciidoctor-pdf's is the corpus's: test/corpus, the ptome-pdf-*
// cases among them.)
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';

/// The tools' runs, recorded (test/oracles/pdf_converter.json.gz,
/// test/support/oracles.dart; ORACLES=record asks them again).
late final Oracle _recorded;

void main() {
  _recorded = Oracle('pdf_converter', compressed: true);
  setUpAll(registerPdf);

  test('sections without ids have the same destinations on every run', () {
    // (Made up from a hash code, they differed from run to run, and so did
    // the PDF.)
    final dir = Directory.systemTemp.createTempSync('ptome-pdf.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File('${dir.path}/doc.adoc')
      ..writeAsStringSync(
        '= Doc\n:sectids!:\n:toc:\n\n== One\n\ntext\n\n== Two\n\ntext\n',
      );
    // (To the same file: the second half of the file's /ID comes from its
    // name.)
    final out = '${dir.path}/doc.pdf';
    List<int> convert() {
      convertFile(
        source.path,
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: 'pdf',
          toFile: out,
          // (A fixed time: the creation date is the conversion's.)
          attributes: const {
            'reproducible': '',
            'localdatetime': '2026-10-08 12:00:00 +0000',
          },
        ),
      );
      return File(out).readAsBytesSync();
    }

    final first = convert();
    expect(convert(), first);
    // Numbered in order (read where qpdf can decompress the names).
    {
      final qdf =
          recordedRunSync(_recorded, 'qpdf', [
                '--qdf',
                '--object-streams=disable',
                out,
                '-',
              ], stdoutEncoding: latin1).stdout
              as String;
      expect(qdf, contains('(__section-1)'));
      expect(qdf, contains('(__section-2)'));
    }
  });

  test('the page mode and the initial zoom come from the theme', () {
    final dir = Directory.systemTemp.createTempSync('ptome-pdf.');
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = '${dir.path}/theme-keys2.pdf';
    convertFile(
      'test/corpus/ptome-pdf-theme-keys2/input.adoc',
      AsciidoctorOptions(safe: SafeMode.unsafe, backend: 'pdf', toFile: out),
    );
    final qdf =
        recordedRunSync(_recorded, 'qpdf', [
              '--qdf',
              '--object-streams=disable',
              out,
              '-',
            ], stdoutEncoding: latin1).stdout
            as String;
    expect(qdf, contains('/PageMode /FullScreen'));
    // In the viewer preferences, where ISO 32000 puts it (the gem writes
    // it in the catalog).
    expect(
      qdf,
      matches(
        RegExp('/ViewerPreferences <<[^>]*/NonFullScreenPageMode /UseThumbs'),
      ),
    );
    expect(qdf, matches(RegExp(r'/OpenAction \[\s*\d+ 0 R\s*/FitH\s+841.89')));
  });
}
