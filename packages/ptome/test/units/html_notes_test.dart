// A units document's notes in HTML and EPUB: a stream `:note-asides:`
// names set beside the text, at its calls (a side column on a wide
// screen, opened under its line on a narrow one); the entries (the
// cross-references) with their units; in EPUB, every stream's notes the
// reading system's popups.
import 'dart:convert';
import 'dart:io';

import 'package:plain_compression/plain_compression.dart';
import 'package:ptome/src/epub3/epub3.dart';
import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const _fixture = 'test/units/fixtures/bible/asides.adoc';

void main() {
  test('HTML: a stream set beside the text, the footnotes without it', () {
    final html = loadFile(
      _fixture,
      options: const AsciidoctorOptions(
        safe: SafeMode.unsafe,
        standalone: true,
        attributes: {'reproducible': ''},
      ),
    ).convert();
    // The translators' note at its call, the call linking to it.
    expect(
      html,
      contains(
        'href="#_footnotedef_1" title="View footnote.">1</a>]</sup>'
        '<span class="note-aside" id="_footnotedef_1" data-stream="tn" '
        'role="note">',
      ),
    );
    // The document's own footnote in the list, the aside not.
    final list = html.substring(html.indexOf('<div id="footnotes"'));
    expect(list, contains('A footnote of the document.'));
    expect(list, isNot(contains('cried')));
    // Their style: the entries and asides beside the text when there is
    // room.
    expect(html, contains('.note-aside{display:none'));
    expect(html, contains('@media screen and (min-width:75em)'));
    // A reference outside the excerpt is text, without a warning.
    expect(html, contains('Joel 2:13'));
  });

  test('HTML: no asides named, every footnote listed', () {
    final html = loadFile(
      _fixture,
      options: const AsciidoctorOptions(
        safe: SafeMode.unsafe,
        standalone: true,
        attributes: {'reproducible': '', 'note-asides': ''},
      ),
    ).convert();
    expect(html, isNot(contains('class="note-aside"')));
    expect(
      html,
      contains('<div class="footnote" id="_footnotedef_1" data-stream="tn">'),
    );
  });

  test('EPUB: the notes popups, the entries styled', () {
    registerEpub3();
    final dir = Directory.systemTemp.createTempSync('units_epub.');
    addTearDown(() => dir.deleteSync(recursive: true));
    convertFile(
      _fixture,
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'epub3',
        toDir: dir.path,
        attributes: const {'reproducible': ''},
      ),
    );
    final files = {
      for (final entry in readZip(
        File('${dir.path}/asides.epub').readAsBytesSync(),
      ))
        entry.name: utf8.decode(entry.bytes),
    };
    final chapter = files.entries
        .firstWhere((e) => e.value.contains('v-exo-34-6'))
        .value;
    expect(
      chapter,
      contains('<aside id="note-1" epub:type="footnote" data-stream="tn">'),
    );
    expect(chapter, contains('.note-entry { display: block;'));
  });
}
