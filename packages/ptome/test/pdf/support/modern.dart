/// What the modern engine's tests (`test/pdf/modern_<n>_test.dart`) share:
/// documents converted to PDF, read back by Poppler and qpdf (their runs
/// recorded, each test file in its own store).
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';

import '../../support/oracles.dart';
import '../../support/pdf_tools.dart';

/// How many documents have been converted, for their files' names.
int modernCount = 0;

/// [source] converted to PDF (in the compatibility mode with [compat];
/// with the theme [theme], YAML extending the default theme, its fonts
/// in the test fonts), its messages logged to [logger].
String modernPdf(
  String source, {
  bool compat = false,
  String? theme,
  Map<String, String> attributes = const {},
  LoggerBase? logger,
}) {
  final input = File('${modernDir.path}/d${modernCount++}.adoc')
    ..writeAsStringSync(source);
  final out = '${input.path}.pdf';
  final themeFile = theme == null
      ? null
      : (File('${input.path}-theme.yml')
          ..writeAsStringSync('extends: default\n$theme'));
  convertFile(
    input.path,
    AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      toFile: out,
      attributes: {
        if (compat) 'pdf-compat': '',
        if (themeFile != null) ...{
          'pdf-theme': themeFile.path,
          'pdf-fontsdir': '${Directory.current.path}/test/pdf/fixtures/fonts',
        } else
          // asciidoctor-pdf's theme, which these tests were written for
          // (the house theme has its own tests).
          'pdf-theme': 'default',
        ...attributes,
      },
      logger: logger,
    ),
  );
  return out;
}

/// The lines of text on each page of [pdf] (the footer's page number
/// left out).
List<List<String>> modernPages(String pdf) => [
  for (final page
      in (recordedRunSync(modernRecorded, 'pdftotext', [
                '-layout',
                pdf,
                '-',
              ], stdoutEncoding: utf8).stdout
              as String)
          .split('\f'))
    [
      for (final line in page.split('\n'))
        if (line.trim().isNotEmpty && !RegExp(r'^\d+$').hasMatch(line.trim()))
          line.trim(),
    ],
];

/// The bottom of each line of [pdf]'s first page, by the line's first
/// word.
Map<String, double> modernBaselines(String pdf) {
  final xml =
      recordedRunSync(modernRecorded, 'pdftotext', [
            '-bbox-layout',
            '-f',
            '1',
            '-l',
            '1',
            pdf,
            '-',
          ]).stdout
          as String;
  return {
    for (final m in RegExp(
      r'<line [^>]*yMax="([\d.]+)">\s*<word [^>]*>([^<]*)<',
    ).allMatches(xml))
      m[2]!: double.parse(m[1]!),
  };
}

/// The content of [pdf], uncompressed (its drawing operators readable).
String modernContent(String pdf) {
  final out = '$pdf.qdf';
  recordedRunSync(modernRecorded, 'qpdf', [
    '--qdf',
    '--object-streams=disable',
    pdf,
    out,
  ]);
  return latin1.decode(File(out).readAsBytesSync());
}

/// The top (points from the page's top) of the first word [word] in
/// [pdf], or null.
double? modernTop(String pdf, String word) =>
    switch (RegExp('yMin="([\\d.]+)"[^>]*>${RegExp.escape(word)}<').firstMatch(
      recordedRunSync(modernRecorded, 'pdftotext', ['-bbox', pdf, '-']).stdout
          as String,
    )) {
      final match? => double.parse(match[1]!),
      null => null,
    };

/// The words of [lines], those hyphenated at a line end joined.
List<String> modernWords(List<String> lines) => lines
    .join('\n')
    .replaceAll(RegExp('[-\u00ad]\n'), '')
    .split(RegExp(r'\s+'));

const modernParagraph =
    'Hypermedia is a concept extending the idea of hypertext by allowing '
    'for more complex interactions with the user and the network. The '
    'hypertext transfer protocol, used to transfer hypermedia documents, is '
    'the backbone of the modern web, and its architecture has been '
    'described at length by Roy Fielding in his dissertation, which '
    'introduced the term representational state transfer, or REST.';

/// The tools' runs, recorded for the test file under way (each sets it:
/// `test/oracles/pdf_modern_<n>.json.gz`, test/support/oracles.dart;
/// ORACLES=record asks them again).
late final Oracle modernRecorded;

/// The folder the documents are converted in.
late Directory modernDir;
