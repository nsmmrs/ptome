/// The XML reader: what XML 1.0 and its namespaces say, where it is
/// lenient, and its errors.
// (XML written in pieces.)
// ignore_for_file: missing_whitespace_between_adjacent_strings
library;

import 'package:plain_svg/src/xml.dart';
import 'package:test/test.dart';

String texts(XmlElement element) => [
  for (final child in element.children)
    switch (child) {
      XmlText(:final text, :final cdata) => cdata ? '[$text]' : text,
      XmlElement(:final name) => '<$name>',
    },
].join('|');

void main() {
  group('documents', () {
    test('a prolog: declaration, comments, instructions, doctype, BOM', () {
      final root = parseXml(
        '﻿<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!-- a comment -->\n<?pi data?>\n'
        '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '
        '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n'
        '<svg/>\n<!-- after -->\n',
      );
      expect(root.name, 'svg');
      expect(root.children, isEmpty);
    });

    test('elements, text, CDATA; comments and instructions leave none', () {
      final root = parseXml(
        '<a>one<b x="1"/>two<!-- c -->three<![CDATA[<four>]]><?p?>five</a>',
      );
      expect(texts(root), 'one|<b>|two|three|[<four>]|five');
      expect(root.innerText, 'onetwothree<four>five');
      expect(root.childElements.single.parent, same(root));
    });

    test('descendants in document order', () {
      final root = parseXml('<a><b><c/></b><d/></a>');
      expect(root.descendantElements.map((e) => e.name), ['b', 'c', 'd']);
    });
  });

  group('references', () {
    test('characters and the predefined entities', () {
      final root = parseXml(
        '<a v="&lt;&#65;&#x42;&amp;">&lt;&gt;&amp;&quot;&apos;&#169;&#x1F600;</a>',
      );
      expect(root.getAttribute('v'), '<AB&');
      expect(root.innerText, '<>&"\'©😀');
    });

    test('the internal subset declares entities, in text and values', () {
      final root = parseXml('''
<!DOCTYPE svg [
  <!ENTITY st0 "fill:#FFFFFF;stroke:none;">
  <!ENTITY ns "http://www.w3.org/2000/svg">
  <!ENTITY both "&st0; &ns;">
  <!ENTITY st0 "ignored: the first declaration binds">
  <!ENTITY % parameter "skipped">
  <!ELEMENT svg ANY>
  <!ATTLIST svg a CDATA "x>y">
  <!-- a comment with > in it -->
]>
<svg xmlns="&ns;" style="&st0;">&both;</svg>''');
      expect(root.namespaceUri, 'http://www.w3.org/2000/svg');
      expect(root.getAttribute('style'), 'fill:#FFFFFF;stroke:none;');
      expect(
        root.innerText,
        'fill:#FFFFFF;stroke:none; http://www.w3.org/2000/svg',
      );
    });

    test('an entity with markup is read as content', () {
      final root = parseXml(
        '<!DOCTYPE a [<!ENTITY e "<b>bold</b> and &amp;">]><a>x&e;y</a>',
      );
      expect(texts(root), 'x|<b>| and &y');
      expect(root.childElements.single.innerText, 'bold');
      expect(root.childElements.single.parent, same(root));
    });

    test('entities that refer to themselves are kept as written', () {
      final root = parseXml(
        '<!DOCTYPE a [<!ENTITY e "x&e;"><!ENTITY m "<b>&m;</b>">]>'
        '<a v="&e;">&e;&m;</a>',
      );
      expect(root.getAttribute('v'), 'x&e;');
      expect(root.innerText, 'x&e;&m;');
    });

    test('entities that blow up stop', () {
      final declarations = StringBuffer('<!ENTITY l0 "lol">');
      for (var i = 1; i < 12; i++) {
        final previous = '&l${i - 1};' * 10;
        declarations.write('<!ENTITY l$i "$previous">');
      }
      expect(
        () => parseXml('<!DOCTYPE a [$declarations]><a>&l11;</a>'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('entities expand too far'),
          ),
        ),
      );
    });

    test('leniently: unknown entities, stray &, bad characters', () {
      final root = parseXml('<a v="&nope; & &#0;">&nope; a & b &#xD800;</a>');
      expect(root.getAttribute('v'), '&nope; & &#0;');
      expect(root.innerText, '&nope; a & b &#xD800;');
    });
  });

  group('normalization', () {
    test(r'line breaks become \n (2.11)', () {
      expect(parseXml('<a>1\r\n2\r3\n4</a>').innerText, '1\n2\n3\n4');
    });

    test('white space in attribute values becomes spaces (3.3.3)', () {
      final root = parseXml('<a v="1\n2\t3\r\n4&#10;5&#9;6"/>');
      expect(root.getAttribute('v'), '1 2 3 4\n5\t6');
    });
  });

  group('namespaces', () {
    test('prefixes, the default namespace, xml:, scopes', () {
      final root = parseXml(
        '<s:svg xmlns:s="http://www.w3.org/2000/svg" '
        'xmlns:xl="http://www.w3.org/1999/xlink" xml:space="preserve">'
        '<s:use xl:href="#a" href="#b"/>'
        '<g xmlns="urn:other"><h xmlns=""/></g></s:svg>',
      );
      expect(root.localName, 'svg');
      expect(root.namespaceUri, 'http://www.w3.org/2000/svg');
      expect(
        root.getAttributeNS('http://www.w3.org/XML/1998/namespace', 'space'),
        'preserve',
      );
      final [use, g] = root.childElements.toList();
      expect(use.getAttribute('xl:href'), '#a');
      expect(use.getAttributeNS('http://www.w3.org/1999/xlink', 'href'), '#a');
      expect(use.attributes.last.namespaceUri, isNull);
      expect(g.namespaceUri, 'urn:other');
      expect(g.childElements.single.namespaceUri, isNull);
    });

    test('an undeclared prefix has no namespace', () {
      expect(parseXml('<x:a/>').namespaceUri, isNull);
    });
  });

  group('leniently', () {
    test('< in values and repeated attributes are kept', () {
      final root = parseXml('<a v="<" w="1" w="2"/>');
      expect(root.getAttribute('v'), '<');
      expect(root.getAttribute('w'), '1');
      expect(root.attributes.map((a) => a.value), ['<', '1', '2']);
    });

    test(']]> in text and -- in comments are kept', () {
      expect(parseXml('<a>x ]]> y<!-- a -- b --></a>').innerText, 'x ]]> y');
    });
  });

  group('errors', () {
    void fails(String text, String message) => expect(
      () => parseXml(text),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'message', message),
      ),
    );

    test('say what and where', () {
      fails('', 'no root element (line 1, column 1)');
      fails('  \n <!-- x -->', 'no root element (line 2, column 12)');
      fails('<svg', 'start tag <svg> not closed (line 1, column 1)');
      fails('<a>\n<b></a>', '<b> closed by </a> (line 2, column 4)');
      fails('<a>text', 'element <a> not closed (line 1, column 1)');
      fails('<a v=1/>', 'a quoted value expected for v (line 1, column 6)');
      fails('<a v="1/>', 'literal not closed (line 1, column 6)');
      fails('<a v/>', '"=" expected after v (line 1, column 5)');
      fails(
        '<a b="1"c="2"/>',
        'white space expected before an attribute '
            '(line 1, column 9)',
      );
      fails('<a/><b/>', 'a second root element (line 1, column 5)');
      fails('<a/>text', 'text after the root element (line 1, column 5)');
      fails('<a><!-- x</a>', 'comment not closed (line 1, column 4)');
      fails('<a><![CDATA[x</a>', 'CDATA section not closed (line 1, column 4)');
      fails(
        '<a><?x</a>',
        'processing instruction not closed '
            '(line 1, column 4)',
      );
      fails(
        '<!DOCTYPE a [<!ENTITY x "y">',
        'internal subset not closed '
            '(line 1, column 29)',
      );
      fails(
        '<!DOCTYPE a',
        'document type declaration not closed '
            '(line 1, column 1)',
      );
      fails('<a></ >', 'a name expected (line 1, column 6)');
      fails('<a></a', '">" expected (line 1, column 7)');
      fails(
        '<!DOCTYPE a [<!ENTITY e "<b>">]><a>&e;</a>',
        'in entity &e;: element <b> not closed (line 1, column 39)',
      );
      fails(
        '<!DOCTYPE a [<!ENTITY e "x</a>">]><a>&e;</a>',
        'in entity &e;: </a> closes an element the entity did not open '
            '(line 1, column 41)',
      );
    });
  });
}
