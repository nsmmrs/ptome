/// The XML reader against package:xml, the reader plain_pdf used before:
/// the same tree for seeded random documents and for the workspace's SVG
/// files, but where this one follows XML 1.0 and package:xml doesn't
/// (line breaks and attribute white space normalized, attributes without
/// a prefix in no namespace; documents with entity declarations, which
/// package:xml doesn't expand, are left out).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_svg/src/xml.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' as oracle;

/// [element] as a line per node: names, namespaces, attributes, text.
String dump(XmlElement element) {
  final out = StringBuffer();
  void walk(XmlElement e, String indent) {
    out.writeln('$indent<${e.name} ${e.namespaceUri}>');
    for (final a in e.attributes) {
      out.writeln(
        '$indent  @${a.name} ${a.namespaceUri} ${jsonEncode(a.value)}',
      );
    }
    for (final child in e.children) {
      switch (child) {
        case XmlText(:final text, :final cdata):
          out.writeln(
            '$indent  ${cdata ? 'cdata' : 'text'} ${jsonEncode(text)}',
          );
        case final XmlElement child:
          walk(child, '$indent  ');
      }
    }
  }

  walk(element, '');
  return out.toString();
}

/// package:xml's tree of [text] dumped alike, normalized as XML 1.0 says.
String dumpOracle(String text) {
  String lines(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = StringBuffer();
  void walk(oracle.XmlElement e, String indent) {
    out.writeln('$indent<${e.name.qualified} ${e.namespaceUri}>');
    for (final a in e.attributes) {
      final value = lines(a.value).replaceAll(RegExp('[\t\n]'), ' ');
      // (An attribute without a prefix is in no namespace, Namespaces in
      // XML 1.0, 6.2: package:xml puts it in the default one.)
      final namespace = a.name.prefix == null && a.name.local != 'xmlns'
          ? null
          : a.namespaceUri;
      out.writeln(
        '$indent  @${a.name.qualified} $namespace ${jsonEncode(value)}',
      );
    }
    for (final child in e.children) {
      switch (child) {
        case oracle.XmlCDATA(:final value):
          out.writeln('$indent  cdata ${jsonEncode(lines(value))}');
        case oracle.XmlText(:final value) when value.isNotEmpty:
          out.writeln('$indent  text ${jsonEncode(lines(value))}');
        case final oracle.XmlElement child:
          walk(child, '$indent  ');
        default:
          break;
      }
    }
  }

  walk(oracle.XmlDocument.parse(text).rootElement, '');
  return out.toString();
}

/// A random well-formed document of [random]'s.
String document(math.Random random) {
  String pick(List<String> options) => options[random.nextInt(options.length)];
  String text() => [
    for (var i = random.nextInt(4); i > 0; i--)
      pick([
        'a',
        ' ',
        '\n',
        '\r\n',
        '\t',
        '&amp;',
        '&lt;',
        '&#65;',
        '&#x1F600;',
        'é',
        '>',
        '"',
        "'",
      ]),
  ].join();
  String value() => text().replaceAll('"', '&quot;');
  String element(int depth) {
    final name = pick(['svg', 'g', 'rect', 's:path', 'xl:use', 'text']);
    final attributes = [
      for (var i = random.nextInt(3); i > 0; i--)
        ' ${pick(['x', 'id', 'xl:href', 'xml:space', 'style'])}$i="${value()}"',
      if (random.nextInt(4) == 0) ' xmlns="urn:${random.nextInt(3)}"',
      if (random.nextInt(4) == 0) ' xmlns:s="http://www.w3.org/2000/svg"',
      if (random.nextInt(4) == 0) ' xmlns:xl="http://www.w3.org/1999/xlink"',
    ].join();
    if (depth > 3 || random.nextInt(4) == 0) return '<$name$attributes/>';
    final content = [
      for (var i = random.nextInt(4); i > 0; i--)
        switch (random.nextInt(5)) {
          0 => '<![CDATA[${text()}]]>',
          1 => '<!-- ${text().replaceAll('-', '')} -->',
          2 || 3 => element(depth + 1),
          _ => text().replaceAll('>', '&gt;'),
        },
    ].join();
    return '<$name$attributes>$content</$name>';
  }

  return '${pick(['', '<?xml version="1.0"?>\n', '<!-- c -->'])}'
      '${element(0)}${pick(['', '\n', '<!-- after -->'])}';
}

void main() {
  test('seeded random documents', () {
    final random = math.Random(20261013);
    for (var i = 0; i < 3000; i++) {
      final text = document(random);
      expect(dump(parseXml(text)), dumpOracle(text), reason: text);
    }
  });

  final files = [
    for (final root in ['..', '../../../hypermedia-systems-ptome'])
      if (Directory(root).existsSync())
        for (final entity in Directory(root).listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.svg') &&
              !entity.path.contains('/build/') &&
              !entity.path.contains('node_modules'))
            entity,
  ];
  test("the workspace's SVG files (${files.length})", () {
    var compared = 0;
    for (final file in files) {
      final text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
      if (text.contains('<!ENTITY')) continue;
      String? expected;
      try {
        expected = dumpOracle(text);
      } on oracle.XmlException {
        expect(() => parseXml(text), throwsFormatException, reason: file.path);
        continue;
      }
      expect(dump(parseXml(text)), expected, reason: file.path);
      compared++;
    }
    expect(compared, files.isEmpty ? 0 : greaterThan(0));
  });
}
