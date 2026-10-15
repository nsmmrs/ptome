// The modern engine (the default): what it does differently from the
// asciidoctor-pdf compatibility mode, read back from the PDFs it makes;
// part 4 of 4: a right-to-left document (test/pdf/support/modern.dart).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';
import 'support/modern.dart';

void main() {
  // (Set as the file's tests start: files may share a program.)
  final recorded = Oracle('pdf_modern_3', compressed: true);
  setUpAll(() => modernRecorded = recorded);
  setUpAll(useVendoredFonts);
  setUpAll(() {
    registerPdf();
    modernDir = Directory.systemTemp.createTempSync('ptome-modern.');
  });
  tearDownAll(() => modernDir.deleteSync(recursive: true));

  group('a right-to-left document (dir: rtl)', () {
    const theme = '''
font:
  catalog:
    merge: true
    Hebrew:
      normal: notoserifhebrew-subset.ttf
      italic: notoserifhebrew-subset.ttf
      bold: notoserifhebrew-subset.ttf
      bold_italic: notoserifhebrew-subset.ttf
    Yrsa:
      normal: yrsa-regular-latin.ttf
      italic: yrsa-italic-latin.ttf
      bold: yrsa-regular-latin.ttf
      bold_italic: yrsa-italic-latin.ttf
  fallbacks: [Yrsa]
base:
  font_family: Hebrew
heading:
  font_family: Hebrew
''';
    const source = '''
= ספר
:dir: rtl
:toc:
:toc-title: תוכן

== בראשית

שלום עולם
''';

    /// Each word on the first two pages of [pdf] (in logical order, as
    /// written: poppler gives a right-to-left word as it is drawn, or as
    /// it is read) with its left and right edges.
    List<(String, double, double)> words(String pdf) => [
      for (final m
          in RegExp(
            r'<word xMin="([\d.]+)" yMin="[\d.]+" xMax="([\d.]+)" '
            r'yMax="[\d.]+">([^<]*)</word>',
          ).allMatches(
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  pdf,
                  '-',
                ]).stdout
                as String,
          ))
        (m[3]!, double.parse(m[1]!), double.parse(m[2]!)),
    ];

    (double, double) edges(List<(String, double, double)> all, String word) {
      final reversed = String.fromCharCodes(word.runes.toList().reversed);
      final (_, left, right) = all.lastWhere(
        (w) => w.$1 == word || w.$1 == reversed,
      );
      return (left, right);
    }

    test('sets its paragraphs and headings from the right', () {
      final all = words(modernPdf(source, theme: theme));
      final (shalomLeft, shalomRight) = edges(all, 'שלום');
      final (olamLeft, _) = edges(all, 'עולם');
      final (_, headingRight) = edges(all, 'בראשית');
      // The first word at the right margin, the second to its left.
      expect(shalomRight, closeTo(headingRight, 0.5));
      expect(olamLeft, lessThan(shalomLeft));
      expect(shalomRight, greaterThan(500));
    });

    test('mirrors its contents: the title right, the page number left', () {
      final all = words(modernPdf(source, theme: theme));
      // (The contents' entry is the first of the heading's words.)
      final (_, _, entryRight) = all.firstWhere(
        (w) => w.$1 == 'בראשית' || w.$1 == 'תישארב',
      );
      expect(entryRight, greaterThan(500), reason: 'the entry at the right');
      // (Beside the footer's page number at the right.)
      expect(
        all.where((w) => w.$1 == '1' && w.$2 < 100),
        isNotEmpty,
        reason: 'its page number at the left',
      );
    });

    test('its contents entry: the dots between, the number at the left', () {
      final pdf = modernPdf(source, theme: theme);
      final boxes = [
        for (final m
            in RegExp(
              r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
              r'yMax="[\d.]+">([^<]*)</word>',
            ).allMatches(
              recordedRunSync(modernRecorded, 'pdftotext', [
                    '-bbox',
                    pdf,
                    '-',
                  ]).stdout
                  as String,
            ))
          (
            m[4]!,
            double.parse(m[1]!),
            double.parse(m[2]!),
            double.parse(m[3]!),
          ),
      ];
      final (_, titleLeft, y, _) = boxes.firstWhere(
        (w) => w.$1 == 'בראשית' || w.$1 == 'תישארב',
      );
      final line = [
        for (final w in boxes)
          if ((w.$3 - y).abs() < 2) w,
      ];
      // (The number on the entry's line at the left margin, not beside the
      // title, and the dots from it to the title.)
      final (_, numberLeft, _, numberRight) = line.firstWhere(
        (w) => w.$1 == '1',
      );
      expect(numberLeft, lessThan(100));
      final dots = [
        for (final w in line)
          if (w.$1 == '.') w,
      ];
      expect(dots, isNotEmpty);
      expect(dots.first.$2, greaterThan(numberRight));
      expect(dots.last.$4, lessThan(titleLeft));
    });

    /// The words of page [page] of [pdf], with their left and right edges
    /// and their top.
    List<(String, double, double, double)> wordsOf(String pdf, int page) => [
      for (final m
          in RegExp(
            r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
            r'yMax="[\d.]+">([^<]*)</word>',
          ).allMatches(
            recordedRunSync(modernRecorded, 'pdftotext', [
                  '-bbox',
                  '-f',
                  '$page',
                  '-l',
                  '$page',
                  pdf,
                  '-',
                ], stdoutEncoding: utf8).stdout
                as String,
          ))
        (m[4]!, double.parse(m[1]!), double.parse(m[3]!), double.parse(m[2]!)),
    ];

    test("its pages mirrored: the running content, a verso's folio at its "
        'right', () {
      final pdf = modernPdf(
        '$source\n\n<<<\n\nעוד\n\n<<<\n\nעוד\n',
        theme: theme,
      );
      // (Page 2, a verso, bound at its left in a right-to-left book: its
      // outer edge, where its number goes, at its right; page 3, a recto,
      // at its left.)
      final verso = wordsOf(pdf, 2).firstWhere((w) => w.$1 == '2');
      expect(verso.$4, greaterThan(700));
      expect(verso.$2, greaterThan(400));
      final recto = wordsOf(pdf, 3).firstWhere((w) => w.$1 == '3');
      expect(recto.$2, lessThan(100));
    });

    test('a book for print bound at its right: the inner margins', () {
      final words = List.filled(80, 'שלום עולם').join(' ');
      final pdf = modernPdf(
        '= ספר\n:doctype: book\n:dir: rtl\n:media: prepress\n\n'
        '== פרק\n\n$words\n\n$words\n\n$words\n\n$words\n\n$words\n\n'
        '$words\n\n$words\n\n$words\n',
        theme:
            '$theme'
            'page:\n  margin: [54, 36, 54, 36]\n  margin_inner: 72\n'
            '  margin_outer: 36\n',
      );
      (double, double) block(int page) {
        final body = [
          for (final w in wordsOf(pdf, page))
            if (w.$4 > 60 && w.$4 < 780) w,
        ];
        return (
          body.map((w) => w.$2).reduce(math.min),
          body.map((w) => w.$3).reduce(math.max),
        );
      }

      // (A recto's binding at its right, a verso's at its left.)
      final (rectoLeft, rectoRight) = block(3);
      expect(rectoLeft, closeTo(36, 1));
      expect(595.28 - rectoRight, closeTo(72, 4));
      final (versoLeft, versoRight) = block(4);
      expect(versoLeft, closeTo(72, 1));
      expect(595.28 - versoRight, closeTo(36, 4));
    });

    test('its lists marked at the right, its tables from the right', () {
      final pdf = modernPdf(
        '= ספר\n:dir: rtl\n\n* אחד\n* שתיים\n\n'
        '[cols="1,1,1"]\n|===\n|א |ב |ג\n|===\n',
        theme: theme,
      );
      final all = wordsOf(pdf, 1);
      (String, double, double, double) find(String word) => all.firstWhere(
        (w) =>
            w.$1 == word ||
            w.$1 == String.fromCharCodes(word.runes.toList().reversed),
      );
      // (The bullet right of its item's text: whatever the fonts draw it
      // as, on the item's line past its text.)
      final item = find('אחד');
      expect(
        all.where((w) => (w.$4 - item.$4).abs() < 4 && w.$2 > item.$3),
        isNotEmpty,
      );
      // (The table's first column at the right.)
      expect(find('א').$2, greaterThan(find('ב').$2));
      expect(find('ב').$2, greaterThan(find('ג').$2));
    });

    test('characters no font has: one warning for them all', () {
      final logger = MemoryLogger();
      modernPdf(
        '= Doc\n\nبِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ\n\nאבג\n',
        logger: logger,
      );
      final warnings = [
        for (final m in logger.messages)
          if (m.severity == Severity.warn) '${m.message}',
      ];
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('no glyph for'));
      expect(warnings.single, contains('U+0628'));
      expect(warnings.single, contains('U+05D0'));
    });

    test('Arabic taken from the page as written (no U+FFFD)', () {
      const arabic = '''
font:
  catalog:
    merge: true
    Naskh:
      normal: notonaskharabic-subset.ttf
      italic: notonaskharabic-subset.ttf
      bold: notonaskharabic-subset.ttf
      bold_italic: notonaskharabic-subset.ttf
  fallbacks: [Yrsa]
base:
  font_family: Naskh
heading:
  font_family: Naskh
''';
      const verse = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ';
      const title = 'البينة';
      final pdf = modernPdf('= $title\n:dir: rtl\n\n$verse\n', theme: arabic);
      final text =
          recordedRunSync(modernRecorded, 'pdftotext', [
                '-enc',
                'UTF-8',
                pdf,
                '-',
              ], stdoutEncoding: utf8).stdout
              as String;
      expect(text, isNot(contains('\ufffd')));
      String bare(String t) => t.replaceAll(RegExp(r'[\s\u202a-\u202e]'), '');
      expect(bare(text), contains(bare(verse)));
      expect(bare(text), contains(title));
    });

    test('is left to right in the compatibility mode', () {
      final all = words(modernPdf(source, theme: theme, compat: true));
      final (_, right) = edges(all, 'שלום');
      expect(right, lessThan(300));
    });
  });
}
