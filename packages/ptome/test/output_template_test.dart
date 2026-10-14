import 'package:ptome/ptome.dart';
import 'package:ptome/src/output_template.dart';
import 'package:test/test.dart';

void main() {
  test('optional parts and links around the number', () {
    expect(
      renderTemplate('{{#n}}{{n}}. {{/n}}{{t}}', {'n': '3', 't': 'Title'}),
      '3. Title',
    );
    expect(
      renderTemplate('{{#n}}{{n}}. {{/n}}{{t}}', {'n': '', 't': 'T'}),
      'T',
    );
    expect(
      renderNumbered('[{{number}}]', '2', (n) => '<a>$n</a>'),
      '[<a>2</a>]',
    );
  });

  group('footnote markers in HTML', () {
    const source = 'Text.footnote:[A note.]';

    test('are the default without templates', () {
      final html = asciidoc.convert(source);
      expect(html, contains('[<a id="_footnoteref_1" class="footnote"'));
      expect(html, contains('<a href="#_footnoteref_1">1</a>. A note.'));
    });

    test('come from the templates', () {
      final html = asciidoc.convert(
        ':footnote-reference-template: {{number}}\n'
        ':footnote-label-template: ({{number}}){sp}\n\n$source',
      );
      expect(html, contains('<sup class="footnote"><a id="_footnoteref_1"'));
      expect(html, contains('(<a href="#_footnoteref_1">1</a>) A note.'));
    });
  });

  group('caption numbers', () {
    const chapters =
        '= Book\n:doctype: book\n:table-caption: 表\n:figure-caption: 图\n'
        ':table-numbering: chapter\n:figure-numbering: chapter\n\n'
        '== One\n\n.A\n|===\n|a\n|===\n\n.B\n|===\n|b\n|===\n\n'
        '== Two\n\n.C\nimage::c.png[]\n\n.D\n[#d]\n|===\n|d\n|===\n\n'
        'See <<d>>.\n\n[appendix]\n== Extra\n\n.E\n|===\n|e\n|===\n';

    test('by chapter: 表 2.1, with `<kind>-numbering: chapter`', () {
      final html = asciidoc.convert(
        chapters,
        attributes: {'xrefstyle': 'short'},
      );
      for (final title in ['表 1.1. A', '表 1.2. B', '表 2.1. D', '表 A.1. E']) {
        expect(html, contains('<caption class="title">$title</caption>'));
      }
      expect(html, contains('<div class="title">图 2.1. C</div>'));
      expect(html, contains('<a href="#d">表 2.1</a>'));
      // (Numbered chapters keep their own numbers.)
      expect(
        asciidoc.convert(chapters, attributes: {'sectnums': ''}),
        contains('<caption class="title">表 2.1. D</caption>'),
      );
    });

    test('by chapter: {{chapter}} and {{index}} in the template', () {
      final html = asciidoc.convert(
        ':table-caption-template: pass:[{{caption}} {{chapter}}-{{index}} ]\n'
        '$chapters',
      );
      expect(html, contains('<caption class="title">表 2-1 D</caption>'));
    });

    test('by chapter: not under asciidoctor-compat', () {
      expect(
        asciidoc.convert(chapters, attributes: {'asciidoctor-compat': ''}),
        contains('<caption class="title">表 3. D</caption>'),
      );
    });

    test('come from <kind>-caption-template', () {
      final html = asciidoc.convert(
        ':listing-caption: Listing\n'
        ':listing-caption-template: pass:[{{caption}} {{number}}: ]\n'
        ':figure-caption-template: {{caption}} {{number}} —{sp}\n\n'
        '.A route\n----\ncode\n----\n\n.A picture\nimage::pic.png[]\n',
      );
      expect(html, contains('<div class="title">Listing 1: A route</div>'));
      expect(html, contains('<div class="title">Figure 1 — A picture</div>'));
    });

    test('leave cross references their word and number', () {
      final html = asciidoc.convert(
        ':xrefstyle: short\n'
        ':figure-caption-template: pass:[{{caption}} {{number}}: ]\n\n'
        'See <<pic>> and xref:pic[xrefstyle=full].\n\n'
        '[#pic]\n.A picture\nimage::pic.png[]\n',
      );
      expect(html, contains('<a href="#pic">Figure 1</a>'));
      expect(
        html,
        contains('<a href="#pic">Figure 1, &#8220;A picture&#8221;</a>'),
      );
    });

    test("are Asciidoctor's without a template", () {
      final html = asciidoc.convert(
        ':listing-caption: Listing\n\n.A route\n----\ncode\n----\n',
      );
      expect(html, contains('<div class="title">Listing 1. A route</div>'));
    });

    test('count untitled blocks with <kind>-numbering: all', () {
      const source =
          ':listing-caption: Listing\n\n----\nuntitled\n----\n\n'
          'image::a.png[]\n\n.A route\n----\ncode\n----\n\n'
          '.A picture\nimage::pic.png[]\n';
      final counted = asciidoc.convert(
        ':listing-numbering: all\n:figure-numbering: all\n$source',
      );
      expect(counted, contains('<div class="title">Listing 2. A route</div>'));
      expect(counted, contains('<div class="title">Figure 2. A picture</div>'));
      // The untitled ones without a caption.
      expect('class="title"'.allMatches(counted), hasLength(2));
      final plain = asciidoc.convert(source);
      expect(plain, contains('<div class="title">Listing 1. A route</div>'));
      final unnumbered = source.replaceFirst(
        '----\nuntitled',
        '[%unnumbered]\n----\nuntitled',
      );
      final skipped = asciidoc.convert(':listing-numbering: all\n$unnumbered');
      expect(skipped, contains('<div class="title">Listing 1. A route</div>'));
    });

    test('of appendices too', () {
      final html = asciidoc.convert(
        '= Book\n:doctype: book\n'
        ':appendix-caption-template: pass:[{{caption}} {{number}} — ]\n\n'
        '[appendix]\n== Extra\n\nText.\n',
      );
      expect(html, contains('Appendix A — Extra'));
    });
  });
}
