/// A Standard Ebooks production (CC0) as AsciiDoc, for the showcase
/// corpus (test/showcase): each XHTML file of its spine one AsciiDoc file
/// under `text/`, the book's file including them in order, its endnotes
/// as footnotes where they are referred to, and the images it uses listed
/// in the work's `fetch.yml` for tool/showcase.dart to fetch from the
/// production's repository at the commit (they are too large to commit:
/// Tenniel's illustrations are 300 MB of SVG). What a work needs beyond
/// what this writes is edited in by hand afterwards; its NOTICE.md says
/// what.
///
///     dart run tool/showcase_import.dart --repo NAME --commit SHA \
///         --checkout DIR --slug SLUG [--part PART] [--skip FILE,...]
///
/// DIR is the repository at SHA (`codeload.github.com` tarball,
/// unpacked); NAME its name under github.com/standardebooks. The
/// production's own pages (title page, imprint, colophon, uncopyright,
/// list of illustrations, the contents) and those `--skip` names are
/// left out. With `--part`, the production is one part of a work of
/// several (Alice's two books): its files go under `text/PART/`, its
/// images are named `PART-<name>`, and `PART.adoc` lists its files for
/// the work's own file to include; without it, `SLUG.adoc` is the book.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
// (The workspace's XML reader, plain_svg's.)
import 'package:plain_svg/src/xml.dart';
import 'package:yaml/yaml.dart';

const String _github = 'https://github.com/standardebooks';

const Set<String> _productionPages = {
  'titlepage',
  'imprint',
  'colophon',
  'uncopyright',
  'loi',
  'toc',
  'halftitlepage',
  'endnotes',
};

/// A file the work fetches: its name in `images/`, where from, and its
/// SHA-256.
typedef Fetched = ({String name, String url, String sha256});

Future<void> main(List<String> arguments) async {
  String? repo;
  String? commit;
  String? checkout;
  String? slug;
  String? part;
  final skip = <String>{};
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--repo':
        repo = arguments[++i];
      case '--commit':
        commit = arguments[++i];
      case '--checkout':
        checkout = arguments[++i];
      case '--slug':
        slug = arguments[++i];
      case '--part':
        part = arguments[++i];
      case '--skip':
        skip.addAll(arguments[++i].split(','));
      default:
        stderr.writeln('showcase_import: unknown argument ${arguments[i]}');
        exit(64);
    }
  }
  if (repo == null || commit == null || checkout == null || slug == null) {
    stderr.writeln(
      'usage: dart run tool/showcase_import.dart --repo NAME --commit SHA '
      '--checkout DIR --slug SLUG [--part PART] [--skip FILE,...]',
    );
    exit(64);
  }
  final epub = '$checkout/src/epub';
  final opf = parseXml(File('$epub/content.opf').readAsStringSync());
  final manifest = {
    for (final item in opf.descendantElements)
      if (item.localName == 'item')
        item.getAttribute('id')!: item.getAttribute('href')!,
  };
  final spine = [
    for (final ref in opf.descendantElements)
      if (ref.localName == 'itemref') manifest[ref.getAttribute('idref')]!,
  ];
  String meta(String name) => opf.descendantElements
      .firstWhere(
        (e) => e.localName == name,
        orElse: () => throw StateError('no $name in content.opf'),
      )
      .innerText
      .trim();
  final title = meta('title');
  final author = meta('creator');
  final language = meta('language');

  final notes = <String, XmlElement>{};
  if (File('$epub/text/endnotes.xhtml').existsSync()) {
    final doc = parseXml(File('$epub/text/endnotes.xhtml').readAsStringSync());
    for (final li in doc.descendantElements) {
      final id = li.getAttribute('id');
      if (li.localName == 'li' && id != null) notes[id] = li;
    }
  }

  final texts = [
    for (final href in spine)
      if (href.startsWith('text/'))
        href.substring('text/'.length, href.length - '.xhtml'.length),
  ].where((name) => !_productionPages.contains(name) && !skip.contains(name));

  final work = 'test/showcase/$slug';
  final textDir = part == null ? 'text' : 'text/$part';
  Directory('$work/$textDir').createSync(recursive: true);
  final hasParts = texts.any(
    (name) =>
        File('$epub/text/$name.xhtml')
            .readAsStringSync()
            .contains('epub:type="part"'),
  );
  final converter = _Converter(
    notes,
    prefix: part == null ? '' : '$part-',
    // (A part's chapters are level 1 whether or not the production has
    // parts of its own: its parts become the work's.)
    partsOffset: hasParts ? 1 : 0,
  );
  for (final name in texts) {
    final doc = parseXml(File('$epub/text/$name.xhtml').readAsStringSync());
    final body = doc.descendantElements.firstWhere(
      (e) => e.localName == 'body',
    );
    File('$work/$textDir/$name.adoc')
        .writeAsStringSync(converter.document(body));
  }

  final includes = [for (final name in texts) 'include::$textDir/$name.adoc[]']
      .join('\n\n');
  if (part == null) {
    File('$work/$slug.adoc').writeAsStringSync(
      [
        '= $title',
        author,
        ':doctype: book',
        ':lang: ${language.split('-').first}',
        ':look: $slug',
        ':looksdir: {docdir}',
        ':imagesdir: images',
        '',
        includes,
        '',
      ].join('\n'),
    );
  } else {
    File('$work/$part.adoc').writeAsStringSync('$includes\n');
  }

  final fetchFile = File('$work/fetch.yml');
  final fetched = <String, Fetched>{
    if (fetchFile.existsSync())
      for (final entry in readFetched(fetchFile.readAsStringSync()))
        entry.name: entry,
  };
  for (final (name, original) in converter.images) {
    fetched[name] = (
      name: name,
      url:
          'https://raw.githubusercontent.com/standardebooks/$repo/$commit/'
          'src/epub/images/$original',
      sha256:
          '${sha256.convert(File('$epub/images/$original').readAsBytesSync())}',
    );
  }
  fetchFile.writeAsStringSync(
    [
      '# The images the work uses that are too large to commit, fetched by',
      '# tool/showcase.dart into the work cache and checked by their SHA-256.',
      for (final entry
          in fetched.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name))) ...[
        '- name: ${entry.name}',
        '  url: ${entry.url}',
        '  sha256: ${entry.sha256}',
      ],
      '',
    ].join('\n'),
  );
  final notice = File('$work/NOTICE.md');
  final credit =
      'Imported from Standard Ebooks (CC0), $_github/$repo at $commit, '
      'by tool/showcase_import.dart.';
  if (!notice.existsSync()) {
    notice.writeAsStringSync(
      [
        '---',
        'title: "$title"',
        'source: $slug.adoc',
        'looks: [$slug]',
        'compare: []',
        '---',
        '',
        '# $title',
        '',
        credit,
        '',
      ].join('\n'),
    );
  }
  stdout.writeln(
    '${texts.length} files, ${converter.images.length} images, '
    '${converter.notesUsed} notes into $work/$textDir',
  );
}

/// The entries of a `fetch.yml`.
List<Fetched> readFetched(String yaml) => [
  for (final entry in (loadYaml(yaml) as YamlList?) ?? YamlList())
    if (entry case {
      'name': final String name,
      'url': final String url,
      'sha256': final String sha256,
    })
      (name: name, url: url, sha256: sha256)
    else
      throw FormatException('fetch.yml: not a name, url and sha256: $entry'),
];

/// What an element's `epub:type` says it is.
Set<String> _types(XmlElement element) =>
    (element.getAttribute('epub:type') ?? '').split(' ').toSet()..remove('');

Set<String> _classes(XmlElement element) =>
    (element.getAttribute('class') ?? '').split(' ').toSet()..remove('');

/// XHTML to AsciiDoc, file by file.
final class _Converter {
  new(this.notes, {required this.prefix, required this.partsOffset});

  /// The endnotes, by id.
  final Map<String, XmlElement> notes;

  /// Put before each image's name in `images/` and each id (a part's
  /// chapters' ids apart from another part's).
  final String prefix;

  /// 1 when the book has parts (a part's section is level 0).
  final int partsOffset;

  /// The images the files use: their names in `images/`, and the
  /// production's.
  final Set<(String, String)> images = {};

  /// How many notes were set as footnotes.
  int notesUsed = 0;

  /// [element]'s id, prefixed.
  String? _id(XmlElement element) => switch (element.getAttribute('id')) {
    final id? => '$prefix$id',
    null => null,
  };

  /// [body]'s blocks.
  String document(XmlElement body) {
    final out = StringBuffer();
    _blocks(body.childElements, out, depth: 0);
    return '${out.toString().trim()}\n';
  }

  void _blocks(
    Iterable<XmlElement> elements,
    StringBuffer out, {
    required int depth,
  }) {
    for (final element in elements) {
      _block(element, out, depth: depth);
    }
  }

  void _blank(StringBuffer out) {
    final text = out.toString();
    if (text.isEmpty || text.endsWith('\n\n')) return;
    out.write(text.endsWith('\n') ? '\n' : '\n\n');
  }

  void _block(XmlElement element, StringBuffer out, {required int depth}) {
    final types = _types(element);
    final classes = _classes(element);
    switch (element.localName) {
      case 'section' || 'article':
        final id = _id(element);
        final heading = element.childElements
            .where(
              (e) => const {
                'h1',
                'h2',
                'h3',
                'h4',
                'h5',
                'h6',
                'hgroup',
              }.contains(e.localName),
            )
            .firstOrNull;
        if (heading == null) {
          // (A part's wrapper in a chapter's file: its heading is in the
          // part's own file.)
          _blocks(element.childElements, out, depth: depth + 1);
          return;
        }
        final level = (depth + 1 - partsOffset).clamp(0, 5);
        final roles = [
          for (final type in types)
            if (type != 'chapter' && type != 'part') type.split(':').last,
        ];
        final (:number, :title) = _numberedHeading(heading);
        _blank(out);
        out
          ..writeln(
            '[${id == null ? '' : '#$id'}'
            '${[for (final role in roles) '.$role'].join()}'
            '${number == null ? '' : ',number=$number'}]',
          )
          ..writeln('${'=' * (level + 1)} $title');
        _blank(out);
        _blocks(
          element.childElements.where((e) => e != heading),
          out,
          depth: depth + 1,
        );
      case 'header':
        _blocks(element.childElements, out, depth: depth);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'hgroup':
        // (A heading outside a section's start: a bridgehead.)
        _blank(out);
        out
          ..writeln('[discrete]')
          ..writeln(
            '${'=' * (depth + 2).clamp(2, 6)} ${_headingText(element)}',
          );
        _blank(out);
      case 'p':
        _paragraph(element, out, classes);
      case 'blockquote':
        _quote(element, out, depth: depth, types: types);
      case 'div':
        if (types.intersection(const {
          'z3998:poem',
          'z3998:verse',
          'z3998:song',
        }).isNotEmpty) {
          _verse(element, out, types);
        } else {
          _blocks(element.childElements, out, depth: depth);
        }
      case 'figure':
        _figure(element, out);
      case 'img':
        _image(element, out, block: true);
      case 'hr':
        _blank(out);
        out.writeln("'''");
        _blank(out);
      case 'ol' || 'ul':
        _list(element, out, 1);
      case 'table':
        _table(element, out);
      case 'footer':
        for (final child in element.childElements) {
          if (child.localName == 'p') {
            _paragraph(child, out, {..._classes(child), 'footer'});
          } else {
            _block(child, out, depth: depth);
          }
        }
      case 'nav' || 'link' || 'title' || 'head':
        break;
      default:
        _blank(out);
        out.writeln(_inline(element).trim());
        _blank(out);
    }
  }

  /// A section's heading: an hgroup's ordinal (`III`) apart from its
  /// title, for the look to number by (`[number=III]`); else its text.
  ({String? number, String title}) _numberedHeading(XmlElement heading) {
    final children = heading.childElements.toList();
    if (heading.localName == 'hgroup' &&
        children.length >= 2 &&
        _types(children.first).contains('z3998:ordinal')) {
      return (
        number: children.first.innerText.trim(),
        title: [for (final child in children.skip(1)) _inline(child).trim()]
            .join(': '),
      );
    }
    return (number: null, title: _headingText(heading));
  }

  String _headingText(XmlElement heading) {
    if (heading.localName != 'hgroup') return _inline(heading).trim();
    final parts = [
      for (final child in heading.childElements) _inline(child).trim(),
    ];
    return parts.join(': ');
  }

  void _paragraph(XmlElement p, StringBuffer out, Set<String> classes) {
    final types = _types(p);
    final roles = [...classes, for (final type in types) type.split(':').last];
    final text = _inline(p).trim();
    if (text.isEmpty) return;
    _blank(out);
    if (roles.isNotEmpty) {
      out.writeln('[${[for (final role in roles) '.$role'].join()}]');
    }
    out.writeln(_lineStart(text));
    _blank(out);
  }

  void _quote(
    XmlElement quote,
    StringBuffer out, {
    required int depth,
    required Set<String> types,
  }) {
    final children = quote.childElements.toList();
    final poems = types.intersection(const {
      'z3998:poem',
      'z3998:verse',
      'z3998:song',
    });
    if (poems.isNotEmpty) {
      _verse(quote, out, types);
      return;
    }
    final cite = children.where((e) => e.localName == 'cite').firstOrNull;
    final roles = [for (final type in types) type.split(':').last];
    _blank(out);
    out.writeln(
      '[quote${cite == null ? '' : ', ${_attribute(_inline(cite).trim())}'}]',
    );
    if (roles.isNotEmpty) {
      out.writeln('[${[for (final role in roles) '.$role'].join()}]');
    }
    out.writeln('____');
    _blocks(children.where((e) => e != cite), out, depth: depth);
    _blank(out);
    out.writeln('____');
    _blank(out);
  }

  /// A poem: its stanzas (paragraphs of lines, each a span; `i1`... an
  /// indent of that many em spaces) in a verse block.
  void _verse(XmlElement poem, StringBuffer out, Set<String> types) {
    final roles = [for (final type in types) type.split(':').last];
    final stanzas = <List<String>>[];
    XmlElement? cite;
    void collect(XmlElement element) {
      for (final child in element.childElements) {
        switch (child.localName) {
          case 'p':
            final lines = <String>[];
            var line = StringBuffer();
            for (final node in child.children) {
              switch (node) {
                case XmlElement(localName: 'br'):
                  lines.add('$line');
                  line = StringBuffer();
                case final XmlElement span when span.localName == 'span':
                  final indent = _classes(span)
                      .where((c) => RegExp(r'^i\d+$').hasMatch(c))
                      .map((c) => int.parse(c.substring(1)))
                      .firstOrNull;
                  line.write('${' ' * (indent ?? 0)}${_inline(span).trim()}');
                case final XmlElement other:
                  line.write(_inlineNode(other));
                case XmlText(:final text):
                  if (text.trim().isNotEmpty) line.write(_escape(text));
              }
            }
            if ('$line'.trim().isNotEmpty) lines.add('$line');
            stanzas.add(lines);
          case 'cite':
            cite = child;
          case 'header' || 'h3' || 'h4' || 'h5' || 'h6' || 'hgroup':
            stanzas.add(['[.title]#${_headingText(child)}#']);
          default:
            collect(child);
        }
      }
    }

    collect(poem);
    _blank(out);
    final attribution = switch (cite) {
      final XmlElement c => ', ${_attribute(_inline(c).trim())}',
      null => '',
    };
    out.writeln('[verse$attribution]');
    if (roles.isNotEmpty) {
      out.writeln('[${[for (final role in roles) '.$role'].join()}]');
    }
    out
      ..writeln('____')
      ..writeln([for (final s in stanzas) s.join('\n')].join('\n\n'))
      ..writeln('____');
    _blank(out);
  }

  void _figure(XmlElement figure, StringBuffer out) {
    final img = figure.descendantElements
        .where((e) => e.localName == 'img')
        .firstOrNull;
    final caption = figure.childElements
        .where((e) => e.localName == 'figcaption')
        .firstOrNull;
    _blank(out);
    if (caption != null) out.writeln('.${_inline(caption).trim()}');
    final id = _id(figure);
    final roles = _classes(figure);
    if (img != null) {
      out.writeln(_imageMacro(img, block: true, id: id, roles: roles));
    }
    _blank(out);
  }

  void _image(XmlElement img, StringBuffer out, {required bool block}) {
    _blank(out);
    out.writeln(_imageMacro(img, block: block));
    _blank(out);
  }

  String _imageMacro(
    XmlElement img, {
    required bool block,
    String? id,
    Set<String> roles = const {},
  }) {
    final src = img.getAttribute('src')!;
    final original = src.substring(src.lastIndexOf('/') + 1);
    final name = '$prefix$original';
    images.add((name, original));
    final alt = img.getAttribute('alt') ?? '';
    final attrs = [
      _attribute(alt),
      if (id != null) 'id=$id',
      if (roles.isNotEmpty) 'role=${roles.join(' ')}',
    ];
    return '${block ? 'image::' : 'image:'}$name[${attrs.join(',')}]';
  }

  void _list(XmlElement list, StringBuffer out, int level) {
    final marker = list.localName == 'ol' ? '.' * level : '*' * level;
    _blank(out);
    for (final li in list.childElements.where((e) => e.localName == 'li')) {
      final blocks = li.childElements
          .where(
            (e) => const {'p', 'ol', 'ul', 'blockquote'}.contains(e.localName),
          )
          .toList();
      if (blocks.isEmpty) {
        out.writeln('$marker ${_inline(li).trim()}');
        continue;
      }
      var first = true;
      for (final block in blocks) {
        switch (block.localName) {
          case 'p' when first:
            out.writeln('$marker ${_inline(block).trim()}');
          case 'p':
            out
              ..writeln('+')
              ..writeln(_lineStart(_inline(block).trim()));
          case 'ol' || 'ul':
            _list(block, out, level + 1);
          default:
            out.writeln('+');
            final inner = StringBuffer();
            _block(block, inner, depth: 0);
            out.writeln(inner.toString().trim());
        }
        first = false;
      }
    }
    _blank(out);
  }

  void _table(XmlElement table, StringBuffer out) {
    final rows = [
      for (final row in table.descendantElements)
        if (row.localName == 'tr')
          [
            for (final cell in row.childElements)
              if (cell.localName == 'td' || cell.localName == 'th') cell,
          ],
    ];
    final columns = rows.fold(0, (n, row) => row.length > n ? row.length : n);
    if (columns == 0) return;
    _blank(out);
    out
      ..writeln('[cols="${List.filled(columns, '1').join(',')}"]')
      ..writeln('|===');
    for (final row in rows) {
      for (final cell in row) {
        out.writeln('|${_inline(cell).trim().replaceAll('|', r'\|')}');
      }
      out.writeln();
    }
    out.writeln('|===');
    _blank(out);
  }

  /// [element]'s content as inline AsciiDoc.
  String _inline(XmlElement element) {
    final out = StringBuffer();
    for (final node in element.children) {
      switch (node) {
        case XmlText(:final text):
          out.write(_escape(text.replaceAll(RegExp(r'\s+'), ' ')));
        case final XmlElement child:
          out.write(_inlineNode(child));
      }
    }
    return '$out';
  }

  String _inlineNode(XmlElement element) {
    final types = _types(element);
    final lang = element.getAttribute('xml:lang');
    String wrap(String text) =>
        lang == null || text.isEmpty ? text : '[lang=$lang]#$text#';
    switch (element.localName) {
      case 'em' || 'i':
        return wrap(_mark('_', _inline(element)));
      case 'strong':
        return wrap(_mark('*', _inline(element)));
      case 'b':
        // (Standard Ebooks sets <b> in small capitals.)
        return '[.sc]#${_inline(element)}#';
      case 'br':
        return ' +\n';
      case 'sup':
        return '^${_inline(element)}^';
      case 'sub':
        return '~${_inline(element)}~';
      case 's':
        return '[.line-through]#${_inline(element)}#';
      case 'q':
        return '“${_inline(element)}”';
      case 'img':
        return _imageMacro(element, block: false);
      case 'a' when types.contains('noteref'):
        final href = element.getAttribute('href')!;
        final note = notes[href.substring(href.indexOf('#') + 1)];
        if (note == null) return '';
        notesUsed++;
        return 'footnote:[${_noteText(note)}]';
      case 'a':
        final href = element.getAttribute('href') ?? '';
        final text = _inline(element);
        if (href.startsWith('http')) return '$href[$text]';
        final hash = href.indexOf('#');
        final target = hash >= 0
            ? href.substring(hash + 1)
            : href.replaceAll('.xhtml', '');
        return '<<$prefix$target,$text>>';
      case 'ruby':
        final base = StringBuffer();
        final annotation = StringBuffer();
        for (final node in element.children) {
          switch (node) {
            case XmlText(:final text):
              base.write(_escape(text));
            case XmlElement(localName: 'rt') && final rt:
              annotation.write(_inline(rt));
            case XmlElement(localName: 'rp'):
              break;
            case final XmlElement other:
              base.write(_inlineNode(other));
          }
        }
        return '$base ($annotation)';
      case 'span' || 'abbr' || 'time' || 'cite' || 'dfn' || 'var' || 'code':
        final text = _inline(element);
        if (_classes(element).contains('blackletter')) {
          return '[.blackletter]#$text#';
        }
        return wrap(text);
      default:
        return wrap(_inline(element));
    }
  }

  /// An endnote's text as a footnote's: its paragraphs run together, its
  /// backlink left out, notes in it set in brackets.
  String _noteText(XmlElement note) {
    final parts = <String>[];
    for (final p in note.childElements) {
      final clone = StringBuffer();
      for (final node in p.children) {
        switch (node) {
          case XmlElement(localName: 'a') && final a
              when _types(a).contains('backlink'):
            break;
          case XmlElement(localName: 'a') && final a
              when _types(a).contains('noteref'):
            final href = a.getAttribute('href')!;
            final inner = notes[href.substring(href.indexOf('#') + 1)];
            if (inner != null) clone.write(' [${_noteText(inner)}]');
          case XmlText(:final text):
            clone.write(_escape(text.replaceAll(RegExp(r'\s+'), ' ')));
          case final XmlElement child:
            clone.write(_inlineNode(child));
        }
      }
      parts.add('$clone'.trim());
    }
    return parts.join(' ').replaceAll(']', r'\]');
  }
}

/// [text] in an unconstrained mark pair (`__x__`), which holds wherever
/// it stands, its spaces outside it.
String _mark(String mark, String text) {
  if (text.trim().isEmpty) return text;
  final lead = text.substring(0, text.length - text.trimLeft().length);
  final trail = text.substring(text.trimRight().length);
  final inner = text.trim();
  return '$lead$mark$mark$inner$mark$mark$trail';
}

/// [text] with what AsciiDoc would read as markup written as character
/// references.
String _escape(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    out.write(switch (rune) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x2A => '&#42;',
      0x5F => '&#95;',
      0x23 => '&#35;',
      0x60 => '&#96;',
      0x5E => '&#94;',
      0x7E => '&#126;',
      0x2B => '&#43;',
      0x7B => '&#123;',
      0x5B => '&#91;',
      0x5D => '&#93;',
      0x7C => '&#124;',
      _ => String.fromCharCode(rune),
    });
  }
  return '$out'
      .replaceAll('--', '-&#45;')
      .replaceAll('...', '..&#46;')
      .replaceAll('::', ':&#58;')
      .replaceAll(';;', ';&#59;')
      .replaceAll('(C)', '(&#67;)')
      .replaceAll('(R)', '(&#82;)')
      .replaceAll('(TM)', '(&#84;M)');
}

/// [text] as an attribute value: quoted.
String _attribute(String text) => '"${text.replaceAll('"', r'\"')}"';

/// [line] safe to start a paragraph: `{empty}` before what would start a
/// list, a heading, a block title or an attribute entry.
String _lineStart(String line) =>
    RegExp(r'^(\*+ |-+ |\.+\S|\.+ |\d+\. |[a-zA-Z]\. |=+ |:\w[\w-]*:|/{2})')
        .hasMatch(line)
    ? '{empty}$line'
    : line;
