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

import 'showcase_text.dart';

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
/// SHA-256; an image's regions to paint white (`blank`, each `[x, y,
/// width, height]` in its pixels) and the region to keep (`crop`), when
/// it is edited (written as a PNG), as the McGuffey's woodcuts are freed
/// of the words printed beside them.
typedef Fetched = ({
  String name,
  String url,
  String sha256,
  List<List<int>> blank,
  List<int>? crop,
});

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
  final converter = _Converter(notes, prefix: part == null ? '' : '$part-');
  for (final name in texts) {
    final doc = parseXml(File('$epub/text/$name.xhtml').readAsStringSync());
    converter.knownIds.addAll([
      for (final e in doc.descendantElements)
        if (const {
          'section',
          'article',
          'figure',
          'p',
          'blockquote',
        }.contains(e.localName))
          ?e.getAttribute('id'),
    ]);
  }
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
      blank: const [],
      crop: null,
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
List<Fetched> readFetched(String yaml) {
  List<int> rectangle(Object? value) => switch (value) {
    YamlList(length: 4) && final list when list.every((n) => n is int) => [
      for (final n in list) n as int,
    ],
    _ => throw FormatException('fetch.yml: not [x, y, width, height]: $value'),
  };
  return [
    for (final entry in (loadYaml(yaml) as YamlList?) ?? YamlList())
      if (entry case {
        'name': final String name,
        'url': final String url,
        'sha256': final String sha256,
      })
        (
          name: name,
          url: url,
          sha256: sha256,
          blank: [
            for (final region
                in (entry as YamlMap)['blank'] as YamlList? ?? YamlList())
              rectangle(region),
          ],
          crop: entry['crop'] == null ? null : rectangle(entry['crop']),
        )
      else
        throw FormatException('fetch.yml: not a name, url and sha256: $entry'),
  ];
}

/// What an element's `epub:type` says it is.
Set<String> _types(XmlElement element) =>
    (element.getAttribute('epub:type') ?? '').split(' ').toSet()..remove('');

Set<String> _classes(XmlElement element) =>
    (element.getAttribute('class') ?? '').split(' ').toSet()..remove('');

/// XHTML to AsciiDoc, file by file.
final class _Converter {
  new(this.notes, {required this.prefix});

  /// The endnotes, by id.
  final Map<String, XmlElement> notes;

  /// Put before each image's name in `images/` and each id (a part's
  /// chapters' ids apart from another part's).
  final String prefix;

  /// The images the files use: their names in `images/`, and the
  /// production's.
  final Set<(String, String)> images = {};

  /// How many notes were set as footnotes.
  int notesUsed = 0;

  /// The ids of the elements imported (sections, figures, paragraphs),
  /// which links may point at.
  final Set<String> knownIds = {};

  /// How many italic elements the text being converted is in.
  int _italic = 0;

  /// The level of the section [element]: a part's 0; a chapter's 1, and
  /// one more for each section around it that isn't a part (the files
  /// of a production with parts wrap a chapter in its part's section, or
  /// not).
  int _level(XmlElement element) {
    if (_types(element).contains('part')) return 0;
    var level = 1;
    for (var at = element.parent; at != null; at = at.parent) {
      if ((at.localName == 'section' || at.localName == 'article') &&
          !_types(at).contains('part')) {
        level++;
      }
    }
    return level.clamp(1, 5);
  }

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
        // (Its heading: a heading element, or a header of a paragraph
        // alone, as Standard Ebooks heads a subchapter.)
        final heading = element.childElements
            .where(
              (e) =>
                  const {
                    'h1',
                    'h2',
                    'h3',
                    'h4',
                    'h5',
                    'h6',
                    'hgroup',
                  }.contains(e.localName) ||
                  (e.localName == 'header' &&
                      e.childElements.length == 1 &&
                      e.childElements.single.localName == 'p'),
            )
            .firstOrNull;
        // (Or a header holding the heading and more: a chapter's number
        // and its summary, as Gibbon's chapters have them.)
        final header = heading == null
            ? element.childElements
                  .where(
                    (e) =>
                        e.localName == 'header' &&
                        e.childElements.any(
                          (c) => const {
                            'h1',
                            'h2',
                            'h3',
                            'h4',
                            'h5',
                            'h6',
                            'hgroup',
                          }.contains(c.localName),
                        ),
                  )
                  .firstOrNull
            : null;
        final inHeader = header?.childElements.firstWhere(
          (c) => const {
            'h1',
            'h2',
            'h3',
            'h4',
            'h5',
            'h6',
            'hgroup',
          }.contains(c.localName),
        );
        if (heading == null && inHeader == null) {
          // (A part's wrapper in a chapter's file: its heading is in the
          // part's own file. Another section without a heading, a
          // dedication, an untitled section of its own.)
          if (!types.contains('part') && !types.contains('chapter')) {
            final roles = [for (final type in types) type.split(':').last];
            _blank(out);
            out
              ..writeln(
                '[${id == null ? '' : '#$id'}'
                '${[for (final role in roles) '.$role'].join()}%notitle]',
              )
              ..writeln(
                '${'=' * (_level(element) + 1)} '
                '${roles.isEmpty ? 'Untitled' : capitalized(roles.first)}',
              );
            _blank(out);
          }
          _blocks(element.childElements, out, depth: depth + 1);
          return;
        }
        final level = _level(element);
        final roles = [
          for (final type in types)
            if (type != 'chapter' && type != 'part') type.split(':').last,
        ];
        final (:number, :title) = _numberedHeading(heading ?? inHeader!);
        _blank(out);
        out
          ..writeln(
            '[${id == null ? '' : '#$id'}'
            '${[for (final role in roles) '.$role'].join()}'
            '${number == null ? '' : ',number=$number'}]',
          )
          ..writeln('${'=' * (level + 1)} $title');
        _blank(out);
        if (header != null) {
          _blocks(
            header.childElements.where((e) => e != inHeader),
            out,
            depth: depth + 1,
          );
        }
        _blocks(
          element.childElements.where((e) => e != heading && e != header),
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
    // (Its id where it has one: links point at paragraphs.)
    final id = _id(p);
    if (roles.isNotEmpty || id != null) {
      out.writeln(
        '[${id == null ? '' : '#$id'}'
        '${[for (final role in roles) '.$role'].join()}]',
      );
    }
    out.writeln(lineStart(text));
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
      '[quote${cite == null ? '' : ', ${citation(_inline(cite).trim())}'}]',
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
                  if (text.trim().isNotEmpty) line.write(escapeText(text));
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
      final XmlElement c => ', ${citation(_inline(c).trim())}',
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
      attributeValue(alt),
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
              ..writeln(lineStart(_inline(block).trim()));
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
    if (table.descendantElements.any(
      (e) => _types(e).contains('z3998:persona') && e.localName == 'td',
    )) {
      _drama(table, out);
      return;
    }
    final rows = [
      for (final row in table.descendantElements)
        if (row.localName == 'tr')
          [
            for (final cell in row.childElements)
              if (cell.localName == 'td' || cell.localName == 'th') cell,
          ],
    ];
    final columns = rows.fold(0, (n, row) {
      final width = row.fold(
        0,
        (w, cell) =>
            w + (int.tryParse(cell.getAttribute('colspan') ?? '') ?? 1),
      );
      return width > n ? width : n;
    });
    if (columns == 0) return;
    _blank(out);
    out
      ..writeln('[cols="${List.filled(columns, '1').join(',')}"]')
      ..writeln('|===');
    for (final row in rows) {
      for (final cell in row) {
        // (A cell spanning columns or rows: `2+|`, `.2+|`.)
        final columnSpan = int.tryParse(cell.getAttribute('colspan') ?? '');
        final rowSpan = int.tryParse(cell.getAttribute('rowspan') ?? '');
        final span = [
          if (columnSpan != null && columnSpan > 1) '$columnSpan',
          if (rowSpan != null && rowSpan > 1) '.$rowSpan',
        ].join();
        out.writeln(
          '${span.isEmpty ? '' : '$span+'}'
          '|${_inline(cell).trim().replaceAll('|', r'\|')}',
        );
      }
      out.writeln();
    }
    out.writeln('|===');
    _blank(out);
  }

  /// A play's speeches (Standard Ebooks' table of a persona's cell and a
  /// speech's): a description list of them, the speaker the term and the
  /// speech the description (a verse speech's lines broken where they
  /// are, its paragraphs joined by list continuations); a row with no
  /// speaker a stage direction, a `[.direction]` paragraph between lists.
  void _drama(XmlElement table, StringBuffer out) {
    var inList = false;
    for (final row in table.descendantElements) {
      if (row.localName != 'tr') continue;
      final cells = [
        for (final cell in row.childElements)
          if (cell.localName == 'td' || cell.localName == 'th') cell,
      ];
      if (cells.isEmpty) continue;
      final persona = cells.length > 1 ? _inline(cells.first).trim() : '';
      final speech = cells.last;
      // (A row with no speaker whose text isn't all stage directions: the
      // last speaker's speech going on after one, a paragraph of its own.)
      final directionsOnly = speech.children.every(
        (node) => switch (node) {
          XmlText(:final text) => text.trim().isEmpty,
          final XmlElement e =>
            _types(e).contains('z3998:stage-direction') ||
                (e.localName == 'p' &&
                    e.childElements.every(
                      (c) => _types(c).contains('z3998:stage-direction'),
                    )),
        },
      );
      final paragraphs = speech.childElements
          .where((e) => e.localName == 'p')
          .toList();
      final parts = paragraphs.isEmpty
          ? [_speechLines(speech)]
          : [for (final p in paragraphs) _speechLines(p)];
      if (persona.isEmpty && !directionsOnly) {
        for (final part in parts) {
          _blank(out);
          out
            ..writeln('[.continued]')
            ..writeln(lineStart(part));
          _blank(out);
        }
        inList = false;
        continue;
      }
      if (persona.isEmpty) {
        // (A direction is italic by its role, not its markup.)
        final text = _direction(speech);
        if (text.isEmpty) continue;
        _blank(out);
        out
          ..writeln('[.direction]')
          ..writeln(lineStart(text));
        _blank(out);
        inList = false;
        continue;
      }
      if (!inList) _blank(out);
      inList = true;
      out.writeln(
        '${persona.replaceAll(':', '&#58;')}:: '
        '${parts.join('\n+\n')}',
      );
    }
    _blank(out);
  }

  /// A speech's text: its lines (spans between line breaks) each on a line
  /// of its own, hard-broken; its stage directions `[.sd]` spans.
  String _speechLines(XmlElement element) {
    final lines = <String>[];
    var line = StringBuffer();
    for (final node in element.children) {
      switch (node) {
        case XmlElement(localName: 'br'):
          lines.add('$line'.trim());
          line = StringBuffer();
        case XmlText(:final text):
          line.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
        case final XmlElement child:
          line.write(_speechInline(child));
      }
    }
    if ('$line'.trim().isNotEmpty) lines.add('$line'.trim());
    return [
      ...lines.take(1),
      for (final line in lines.skip(1)) lineStart(line),
    ].join(' +\n');
  }

  String _speechInline(XmlElement element) {
    if (_types(element).contains('z3998:stage-direction')) {
      return '[.sd]##${_direction(element)}##';
    }
    if (element.localName == 'span') {
      final out = StringBuffer();
      for (final node in element.children) {
        switch (node) {
          case XmlText(:final text):
            out.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
          case final XmlElement child:
            out.write(_speechInline(child));
        }
      }
      return '$out';
    }
    return _inlineNode(element);
  }

  /// A stage direction's text, its italics left to its role: the names in
  /// it (Standard Ebooks' personas) kept as small capitals.
  String _direction(XmlElement element) {
    final out = StringBuffer();
    for (final node in element.children) {
      switch (node) {
        case XmlText(:final text):
          out.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
        case XmlElement(localName: 'i' || 'em' || 'span' || 'td') && final e:
          out.write(_direction(e));
        case final XmlElement child:
          out.write(_inlineNode(child));
      }
    }
    return '$out'.trim();
  }

  /// [element]'s content as inline AsciiDoc.
  String _inline(XmlElement element) {
    final out = StringBuffer();
    for (final node in element.children) {
      switch (node) {
        case XmlText(:final text):
          out.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
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
        lang == null || text.isEmpty ? text : '[lang=$lang]##$text##';
    switch (element.localName) {
      case 'em' || 'i':
        // (Italic in italic is set roman, as the production's stylesheet
        // sets it.)
        final attributes = lang == null ? '' : '[lang=$lang]';
        if (_italic > 0) {
          return '[.roman${lang == null ? '' : ',lang=$lang'}]'
              '##${_inline(element)}##';
        }
        _italic++;
        try {
          return markPair('_', _inline(element), attributes: attributes);
        } finally {
          _italic--;
        }
      case 'strong':
        return wrap(markPair('*', _inline(element)));
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
        // (A link to what isn't imported, a chapter left out or a note,
        // which is a footnote here, is its text.)
        if (!knownIds.contains(target)) return text;
        return '<<$prefix$target,$text>>';
      case 'ruby':
        final base = StringBuffer();
        final annotation = StringBuffer();
        for (final node in element.children) {
          switch (node) {
            case XmlText(:final text):
              base.write(escapeText(text));
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
        // (A span's classes its roles: a marginal date's `timeline`, a
        // blackletter word; not a poem line's indent or an abbreviation's
        // end of clause.)
        final roles = [
          for (final role in _classes(element))
            if (!RegExp(r'^i\d+$').hasMatch(role) && role != 'eoc') role,
        ];
        if (roles.isNotEmpty && text.trim().isNotEmpty) {
          return '[${[for (final role in roles) '.$role'].join()}'
              '${lang == null ? '' : ',lang=$lang'}]##$text##';
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
            clone.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
          case final XmlElement child:
            clone.write(_inlineNode(child));
        }
      }
      parts.add('$clone'.trim());
    }
    // (Its text's brackets are character references already: the brackets
    // left are its markup's.)
    return parts.join(' ');
  }
}
