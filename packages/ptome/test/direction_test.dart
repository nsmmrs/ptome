// A document's direction and writing mode in HTML and EPUB (FEAT-5gt09c):
// `dir`, `page-progression-direction`, the writing-mode stylesheet and
// tate-chu-yoko; nothing under asciidoctor-compat.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_compression/plain_compression.dart';
import 'package:ptome/ptome.dart';
import 'package:ptome/src/epub3/epub3.dart';
import 'package:test/test.dart';

/// epubcheck's jar (`EPUBCHECK_JAR`, else where the work cache keeps it).
final String _epubcheck =
    Platform.environment['EPUBCHECK_JAR'] ??
    '${Platform.environment['HOME']}/.cache/asciidart-work/tools/'
        'epubcheck-5.4.0/epubcheck.jar';

const String _vertical =
    '= 本\n:lang: ja\n:writing-mode: vertical-rl\n:doctype: book\n\n'
    '== 一\n\n11月10日の8時30分、151台。[.tcy]#!?#\n\n'
    '|===\n|区 |人口\n|===\n';

const String _rtl =
    '= كتاب\n:lang: ar\n:dir: rtl\n:doctype: book\n\n== الفصل\n\nنص.\n';

void main() {
  setUpAll(registerEpub3);

  group('HTML', () {
    test('dir on the root of a right-to-left document', () {
      expect(asciidoc.convert(_rtl, standalone: true), contains(' dir="rtl"'));
    });

    test('a vertical document: its writing mode, tables across, numbers '
        'of one or two digits combined', () {
      final html = asciidoc.convert(_vertical, standalone: true);
      expect(html, contains('html{-epub-writing-mode:vertical-rl;'));
      expect(html, contains('table.tableblock,'));
      expect(
        html,
        contains(
          '<span class="tcy">11</span>月<span class="tcy">10</span>日の'
          '<span class="tcy">8</span>時<span class="tcy">30</span>分、151台。'
          '<span class="tcy">!?</span>',
        ),
      );
    });

    test("a block's own writing mode", () {
      final html = asciidoc.convert('[.vertical-rl]\n縦の段落。', standalone: true);
      expect(html, contains('.vertical-rl{'));
      expect(html, contains('class="paragraph vertical-rl"'));
      // (A horizontal document's numbers aren't combined.)
      expect(asciidoc.convert('10日'), isNot(contains('tcy')));
    });

    test('nothing under asciidoctor-compat', () {
      final html = asciidoc.convert(
        _vertical,
        standalone: true,
        attributes: {'asciidoctor-compat': ''},
      );
      expect(html, isNot(contains('writing-mode')));
      expect(html, isNot(contains('<span class="tcy">11')));
      expect(
        asciidoc.convert(
          _rtl,
          standalone: true,
          attributes: {'asciidoctor-compat': ''},
        ),
        isNot(contains(' dir="rtl"')),
      );
    });
  });

  group('EPUB', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('direction.'));
    tearDown(() => dir.deleteSync(recursive: true));

    String book(String source, {Map<String, String> attributes = const {}}) {
      final path = '${dir.path}/book.epub';
      File(path).writeAsBytesSync(
        asciidoc.convertToBytes(
          source,
          backend: Backend.epub3,
          attributes: {'reproducible': '', ...attributes},
        ),
      );
      return path;
    }

    Map<String, String> files(String path) => {
      for (final entry in readZip(File(path).readAsBytesSync()))
        entry.name: utf8.decode(entry.bytes, allowMalformed: true),
    };

    test('pages turn to the left in a right-to-left or vertical-rl book', () {
      for (final source in [_rtl, _vertical]) {
        expect(
          files(book(source))['EPUB/package.opf'],
          contains('<spine toc="ncx" page-progression-direction="rtl">'),
        );
      }
      expect(
        files(book('= Book\n\n== One\n\nText.'))['EPUB/package.opf'],
        isNot(contains('page-progression-direction')),
      );
    });

    test('dir and the writing mode in the content documents', () {
      final rtl = files(book(_rtl));
      expect(
        rtl.entries.where((e) => e.key.endsWith('.xhtml')).map((e) => e.value),
        everyElement(contains(' dir="rtl"')),
      );
      final vertical = files(book(_vertical));
      final chapter = vertical.entries
          .firstWhere(
            (e) => e.key.endsWith('.xhtml') && !e.key.endsWith('nav.xhtml'),
          )
          .value;
      expect(chapter, contains('-epub-writing-mode:vertical-rl'));
      expect(chapter, contains('<span class="tcy">11</span>'));
    });

    test('nothing under asciidoctor-compat', () {
      final opf = files(
        book(_vertical, attributes: {'asciidoctor-compat': ''}),
      )['EPUB/package.opf'];
      expect(opf, isNot(contains('page-progression-direction')));
    });

    test('epubcheck passes them', () {
      for (final source in [_rtl, _vertical]) {
        final r = Process.runSync('java', ['-jar', _epubcheck, book(source)]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }
    }, skip: File(_epubcheck).existsSync() ? false : 'needs epubcheck');
  });
}
