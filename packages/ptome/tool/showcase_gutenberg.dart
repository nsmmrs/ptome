/// A Project Gutenberg text as AsciiDoc, for the showcase corpus
/// (test/showcase): its HTML edition read, its header, footer and
/// licence left out (Project Gutenberg's own pages; the text is in the
/// public domain), the text written to the work's folder as its parts'
/// files under `text/`. Each work's text is marked up in its own way, so
/// each has its own reading here; what a work needs beyond what this
/// writes is edited in by hand afterwards, and its NOTICE.md says what.
///
///     dart run tool/showcase_gutenberg.dart WORK HTML
///
/// HTML is the edition's `pg<number>-images.html` (from its
/// `pg<number>-h.zip`, unpacked). WORK is one of:
///
/// - `burton`: The Anatomy of Melancholy (eBook #10800), into
///   test/showcase/burton.
/// - `beeton`: Mrs Beeton's Book of Household Management (eBook
///   #10136), into test/showcase/beeton.
/// - `punch`: Punch, or the London Charivari, the issues of 17 July, 14
///   and 21 August 1841 (eBooks #13639, #14923, #14924), into
///   test/showcase/punch: HTML is then each issue's file, in order.
library;

import 'dart:io';
import 'dart:math' as math;

// (The workspace's XML reader, plain_svg's.)
import 'package:plain_svg/src/xml.dart';

import 'showcase_text.dart';

void main(List<String> arguments) {
  if (arguments.length < 2) {
    stderr.writeln('usage: dart run tool/showcase_gutenberg.dart WORK HTML...');
    exit(64);
  }
  if (arguments.first == 'punch') {
    _Punch([
      for (final html in arguments.skip(1))
        (
          html.split('/').last.replaceAll(RegExp(r'\D'), ''),
          readGutenberg(File(html).readAsStringSync()),
        ),
    ]).write('test/showcase/punch');
    return;
  }
  final [work, html] = arguments;
  final source = File(html).readAsStringSync();
  final body = readGutenberg(source);
  switch (work) {
    case 'burton':
      _Burton(body).write('test/showcase/burton');
    case 'beeton':
      _Beeton(body).write('test/showcase/beeton');
    default:
      stderr.writeln('unknown work: $work');
      exit(64);
  }
}

/// The body of Project Gutenberg's HTML [html] as an XML tree: its void
/// elements closed, so that the XML reader reads it.
XmlElement readGutenberg(String html) {
  // (After the head, whose stylesheet may name `<body>` in a comment.)
  final start = html.indexOf('<body', html.indexOf('</head>'));
  final end = html.lastIndexOf('</body>');
  final body = html
      .substring(start, end + '</body>'.length)
      .replaceAllMapped(
        RegExp(r'<(br|hr|img|meta|link|input|col|wbr)\b([^>]*?)/?>'),
        (m) => '<${m[1]}${m[2]}/>',
      );
  return parseXml(body);
}

/// [html] with the straight quotation marks and apostrophes of its text
/// (not its markup) curled, as the printed book has them: a double one
/// opening after a space, a dash or a bracket, else closing.
String curled(String html) => html.replaceAllMapped(RegExp('>([^<]*)'), (m) {
  final text = m[1]!
      .replaceAllMapped(RegExp(r'(^|[\s(\[—])"'), (q) => '${q[1]}“')
      .replaceAll('"', '”')
      .replaceAll("'", '’');
  return '>$text';
});

/// [element]'s classes.
Set<String> classesOf(XmlElement element) =>
    (element.getAttribute('class') ?? '').split(' ').toSet()..remove('');

/// [element]'s language: its `lang`, or the `data-invalid-lang` Project
/// Gutenberg writes for a code it doesn't know (`gr`, Greek's `el`).
String? languageOf(XmlElement element) =>
    element.getAttribute('lang') ??
    switch (element.getAttribute('data-invalid-lang')) {
      'gr' => 'el',
      final other => other,
    };

/// A Gutenberg text's inline content as AsciiDoc: its notes (by their
/// ids) footnotes where they are referred to, its links to the [ids]
/// written cross-references, the rest as text.
base class GutenbergText {
  new(this.notes);

  /// The notes, by their ids.
  final Map<String, String> notes;

  /// The ids the text's anchors keep.
  final Set<String> ids = {};

  /// The notes used so far, by their ids.
  final Set<String> notesUsed = {};

  int _italic = 0;

  /// [element]'s content as inline AsciiDoc.
  String inline(XmlElement element) {
    final out = StringBuffer();
    for (final node in element.children) {
      out.write(switch (node) {
        XmlText(:final text) => escapeText(
          text.replaceAll(RegExp(r'\s+'), ' '),
        ),
        final XmlElement child => inlineNode(child),
      });
    }
    return '$out';
  }

  /// The inline element [element] as AsciiDoc.
  String inlineNode(XmlElement element) {
    final lang = languageOf(element);
    switch (element.localName) {
      case 'i' || 'em' || 'cite':
        final attributes = lang == null ? '' : '[lang=$lang]';
        // (Italic in italic set roman.)
        if (_italic > 0) {
          return '[.roman${lang == null ? '' : ',lang=$lang'}]'
              '##${inline(element)}##';
        }
        _italic++;
        try {
          return markPair('_', inline(element), attributes: attributes);
        } finally {
          _italic--;
        }
      case 'strong' || 'b':
        return markPair('*', inline(element));
      case 'br':
        return ' +\n';
      case 'sup':
        return '^${inline(element)}^';
      case 'sub':
        return '~${inline(element)}~';
      case 'img':
        return '';
      case 'a':
        return link(element);
      case 'span':
        return span(element);
      default:
        return inline(element);
    }
  }

  /// A link or an anchor: a note's reference its footnote, a link to an
  /// anchor kept a cross-reference, an anchor kept (an id) an inline
  /// anchor.
  String link(XmlElement element) {
    final href = element.getAttribute('href');
    final id = element.getAttribute('id');
    final text = inline(element);
    if (href == null) {
      return id != null && ids.contains(id) ? '[[$id]]$text' : text;
    }
    if (href.startsWith('#')) {
      final target = href.substring(1);
      if (notes[target] case final note?) {
        notesUsed.add(target);
        return 'footnote:[$note]';
      }
      if (ids.contains(target)) return '<<$target,$text>>';
      return text;
    }
    if (href.startsWith('http')) return '$href[$text]';
    return text;
  }

  /// A span: its language and classes ([spanRoles]) a phrase's, else its
  /// text.
  String span(XmlElement element) {
    final text = inline(element);
    final lang = languageOf(element);
    final roles = spanRoles(element);
    if (text.trim().isEmpty || (roles.isEmpty && lang == null)) return text;
    final attributes = [
      for (final role in roles) '.$role',
      if (lang != null) ',lang=$lang',
    ].join();
    return '[$attributes]##$text##';
  }

  /// The roles a span's classes give it.
  List<String> spanRoles(XmlElement element) => [...classesOf(element)];
}

/// The Anatomy of Melancholy: its front matter, the three Partitions
/// (parts), each opened by its synopsis (lists of braces), their
/// Sections (sections without titles of their own: the first member's
/// heading names its section), Members and Subsections; its notes,
/// Burton's marginal citations and the editor's notes, footnotes. The
/// index, which has no page numbers, and Project Gutenberg's
/// introduction are left out.
final class _Burton extends GutenbergText {
  new(this.body) : super(_notes(body));

  final XmlElement body;

  /// The parts' files, in order.
  final List<String> _files = [];

  static Map<String, String> _notes(XmlElement body) {
    final text = GutenbergText(const {});
    return {
      for (final note in body.descendantElements)
        if (classesOf(note).contains('note'))
          ?note.childElements.firstOrNull?.getAttribute('id'): text
              .inline(note)
              .trim()
              // (Its number, and the full stop after it.)
              .replaceFirst(RegExp(r'^\d+\.\s*'), ''),
    };
  }

  @override
  List<String> spanRoles(XmlElement element) => [
    for (final role in classesOf(element))
      switch (role) {
        // (A title: italic, as the edition sets it.)
        'cite' => 'title',
        // (A Bible reference, set as text.)
        'bibcite' => null,
        // (What the translator left in Latin.)
        'prudish' => null,
        final other => other,
      },
  ].nonNulls.toList();

  @override
  String span(XmlElement element) {
    if (classesOf(element).contains('cite')) {
      return markPair('_', inline(element));
    }
    final lang = languageOf(element);
    // (Latin and the other languages Burton quotes: italic, as the early
    // editions set them, by the look's `foreign` role.)
    if (lang != null && lang != 'en' && spanRoles(element).isEmpty) {
      final text = inline(element);
      if (text.trim().isEmpty) return text;
      return '[.foreign,lang=$lang]##$text##';
    }
    return super.span(element);
  }

  void write(String dir) {
    // (The anchors the text links to: kept.)
    final present = {
      for (final e in body.descendantElements) ?e.getAttribute('id'),
    };
    for (final a in body.descendantElements.where((e) => e.localName == 'a')) {
      if (a.getAttribute('href') case final href?
          when href.startsWith('#') && !href.startsWith('#note')) {
        if (present.contains(href.substring(1))) ids.add(href.substring(1));
      }
    }
    final textDir = Directory('$dir/text')..createSync(recursive: true);
    for (final old in textDir.listSync().whereType<File>()) {
      old.deleteSync();
    }
    final front = body.descendantElements.firstWhere(
      (e) => e.getAttribute('id') == 'front',
    );
    _front(front, dir);
    _reader(
      body.descendantElements.firstWhere(
        (e) => e.getAttribute('id') == 'toreader',
      ),
      dir,
    );
    for (final (n, part)
        in body.descendantElements
            .where((e) => classesOf(e).contains('partition'))
            .indexed) {
      _partition(part, n + 1, dir);
    }
    stdout.writeln('${_files.length} files, ${notesUsed.length} notes');
    final unused = notes.keys.where((id) => !notesUsed.contains(id)).toList();
    if (unused.isNotEmpty) stdout.writeln('notes not referred to: $unused');
  }

  void _file(String dir, String name, StringBuffer out) {
    final text = '$out'
        .trim()
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        // (The signs of the zodiac as text, not emoji: their text
        // presentation selector after them.)
        .replaceAllMapped(
          RegExp('[\u2648-\u2653](?!\ufe0e)'),
          (m) => '${m[0]}\ufe0e',
        );
    File('$dir/text/$name.adoc').writeAsStringSync('$text\n');
    _files.add(name);
  }

  // The front matter.

  void _front(XmlElement front, String dir) {
    // (Project Gutenberg's introduction, up to the first rule, left out;
    // then the frontispiece, the title page and the dedication, a rule
    // after each, their headings lines of their own; then the edition's
    // front matter, each heading a chapter's.)
    final nodes = front.children.toList();
    final start = nodes.indexWhere(
      (n) => n is XmlElement && n.localName == 'hr',
    );
    const pages = ['frontispiece', 'title-page', 'dedication'];
    var page = 0;
    var out = StringBuffer();
    var name = pages.first;
    var chapters = 0;
    // (The frontispiece: the engraving, its description, which the
    // edition prints after it, its alternative text.)
    out
      ..writeln('[.frontispiece%notitle%noheader%nofooter]')
      ..writeln('== Frontispiece')
      ..writeln();
    for (final node in nodes.skip(start + 1)) {
      if (page == 0 && node is XmlText) continue;
      if (node is XmlElement) {
        if (chapters == 0 && node.localName == 'hr') {
          _flush(out);
          if (page + 1 < pages.length && '$out'.trim().isNotEmpty) {
            _file(dir, name, out);
            out = StringBuffer();
            name = pages[++page];
            out
              ..writeln('[.$name%notitle%noheader%nofooter]')
              ..writeln(
                name == 'title-page' ? '== Title Page' : '== Dedication',
              )
              ..writeln();
          }
          continue;
        }
        if (page == 0) {
          if (node.descendantElements.where((e) => e.localName == 'img')
              case final images when images.isNotEmpty) {
            final description = front.children
                .skipWhile((n) => n != node)
                .skip(1)
                .takeWhile((n) => !(n is XmlElement && n.localName == 'hr'))
                .whereType<XmlText>()
                .map((t) => t.text)
                .join(' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .replaceAll(RegExp(r'"\s*>?\s*$'), '')
                .trim();
            out
              ..writeln()
              ..writeln(
                'image::frontispiece.png['
                '${attributeValue('The engraved title page of the sixth '
                'edition (1652), its ten panels: $description')},'
                'align=center,pdfwidth=100%]',
              )
              ..writeln();
          }
          continue;
        }
        final level = switch (node.localName) {
          'h2' => 2,
          'h3' when chapters > 0 => 3,
          _ => 0,
        };
        if (level > 0) {
          final title = _title(node);
          _flush(out);
          // (A section of the account of the author.)
          if (title.startsWith('EXTRACTED FROM')) {
            out
              ..writeln()
              ..writeln('=== ${_headingCase(title)}')
              ..writeln();
            continue;
          }
          _file(dir, name, out);
          out = StringBuffer();
          chapters++;
          name = 'front-$chapters';
          out
            ..writeln('== ${_headingCase(title)}')
            ..writeln();
          continue;
        }
      }
      _block(node, out);
    }
    _flush(out);
    _file(dir, name, out);
  }

  /// Democritus Junior to the Reader, the satirical preface.
  void _reader(XmlElement reader, String dir) {
    final out = StringBuffer();
    for (final node in reader.children) {
      if (node is XmlElement && node.localName == 'h1') {
        out
          ..writeln('== ${_headingCase(_title(node))}')
          ..writeln();
        continue;
      }
      _block(node, out);
    }
    _flush(out);
    _file(dir, 'to-the-reader', out);
  }

  // The partitions.

  void _partition(XmlElement part, int number, String dir) {
    final out = StringBuffer();
    final ordinal = const ['First', 'Second', 'Third'][number - 1];
    // (The anchors in its headings, which the synopses link to: kept
    // in its title.)
    final anchors = [
      for (final h in part.childElements.where((e) => e.localName == 'h2'))
        if (_anchorIn(h) case final id?) '[[$id]]',
    ].join();
    out
      ..writeln('[#partition-$number]')
      ..writeln('= ${anchors}The $ordinal Partition')
      ..writeln();
    // (Its synopsis, before it in the edition: a chapter of its own.)
    final synopsis = _previousSibling(part, 'synopsis');
    if (synopsis != null) {
      out
        ..writeln('[.synopsis]')
        ..writeln(
          '== [[rh-synopsis-$number,Synopsis.]]'
          'The Synopsis of the $ordinal Partition',
        )
        ..writeln();
      _synopsis(synopsis, out);
    }
    _file(dir, 'partition-$number', out);
    // (The partition's own headings after the first: the second's "The
    // Cure of Melancholy", the third's "Love-Melancholy", its subtitle.)
    final subtitles = [
      for (final h
          in part.childElements.where((e) => e.localName == 'h2').skip(1))
        _title(h),
    ];
    var section = 0;
    for (final child in part.childElements) {
      if (!classesOf(child).contains('section')) continue;
      section++;
      final out = StringBuffer();
      if (section == 1 && subtitles.isNotEmpty) {
        // (The partition's subject, at its first section.)
        for (final subtitle in subtitles) {
          out
            ..writeln('[.partition-subject]')
            ..writeln(_headingCase(subtitle))
            ..writeln();
        }
      }
      _section(child, number, section, out);
      _file(dir, 'partition-$number-section-$section', out);
    }
  }

  XmlElement? _previousSibling(XmlElement element, String className) {
    final siblings = element.parent!.childElements.toList();
    final i = siblings.indexOf(element);
    for (var j = i - 1; j >= 0; j--) {
      if (classesOf(siblings[j]).contains(className)) return siblings[j];
      if (classesOf(siblings[j]).contains('partition')) return null;
    }
    return null;
  }

  /// A section: headed (for the running heads, the contents and the
  /// outline, not on the page) as the edition's running heads name it,
  /// "Part. 1. Sect. 2.".
  void _section(XmlElement section, int part, int number, StringBuffer out) {
    out
      ..writeln('[%notitle]')
      ..writeln('== Part. $part. Sect. $number.')
      ..writeln();
    var member = 0;
    for (final child in section.children) {
      if (child is XmlElement && classesOf(child).contains('member')) {
        member++;
        _member(child, '$part-$number-$member', member, out);
      } else {
        _block(child, out);
      }
    }
  }

  /// A member, [key] its place (`1-2-3`, for its running head's mark),
  /// [number] its number in its section.
  void _member(XmlElement member, String key, int number, StringBuffer out) {
    final section = int.parse(key.split('-')[1]);
    // (Its heading: its own, or the one its first subsection opens with,
    // "THE FIRST SECTION, MEMBER, SUBSECTION.", which heads all three.)
    final own = member.childElements
        .where((e) => e.localName == 'h3')
        .firstOrNull;
    final first = member.childElements
        .where((e) => classesOf(e).contains('subsection'))
        .firstOrNull;
    final opening =
        own ??
        first?.childElements.where((e) => e.localName == 'h3').firstOrNull;
    var title = opening == null
        ? 'Memb. ${_roman(number)}.'
        : _memberTitle(_title(opening), section, number);
    // (A member without subsections: its subject, the h4 after its
    // heading, after its number.)
    final subject = member.childElements
        .where((e) => e.localName == 'h4')
        .firstOrNull;
    if (subject != null) title = '$title—${_subject(subject)}';
    final id =
        (opening == null ? null : _anchorIn(opening)) ??
        (subject == null ? null : _anchorIn(subject));
    out.writeln();
    if (id != null) out.writeln('[[$id]]');
    // (Its mark, "Memb. 3.", the running head's at the right.)
    out
      ..writeln('=== [[rh-$key,Memb. $number.]]$title')
      ..writeln();
    var subsection = 0;
    for (final child in member.children) {
      if (child is XmlElement) {
        if (child == own || child == subject) continue;
        if (classesOf(child).contains('subsection')) {
          subsection++;
          _subsection(child, '$key-$subsection', number, subsection, out);
          continue;
        }
      }
      _block(child, out);
    }
  }

  void _subsection(
    XmlElement subsection,
    String key,
    int member,
    int number,
    StringBuffer out,
  ) {
    final h4 = subsection.childElements
        .where((e) => e.localName == 'h4')
        .firstOrNull;
    var title = h4 == null ? 'Subsect. ${_roman(number)}.' : _subject(h4);
    if (!title.toUpperCase().startsWith('SUBSECT')) {
      title = 'Subsect. ${_roman(number)}.—$title';
    }
    // (Its anchor, before its heading or in it.)
    final id =
        _anchorBefore(subsection, h4) ?? (h4 == null ? null : _anchorIn(h4));
    out.writeln();
    if (id != null) out.writeln('[[$id]]');
    out
      ..writeln('==== [[rh-$key,Memb. $member. Subs. $number.]]$title')
      ..writeln();
    for (final child in subsection.children) {
      if (child is XmlElement && (child == h4 || child.localName == 'h3')) {
        continue;
      }
      if (child is XmlElement &&
          child.localName == 'a' &&
          id != null &&
          child.getAttribute('id') == id) {
        continue;
      }
      _block(child, out);
    }
  }

  /// The anchor (`<a id>`) right before [heading] in [parent], if any.
  String? _anchorBefore(XmlElement parent, XmlElement? heading) {
    for (final child in parent.childElements) {
      if (child == heading) break;
      if (child.localName != 'a') continue;
      if (child.getAttribute('id') case final id?) return id;
    }
    return null;
  }

  String? _anchorIn(XmlElement heading) => [
    for (final a in heading.descendantElements)
      if (a.localName == 'a' && a.getAttribute('id') != null)
        a.getAttribute('id')!,
  ].firstOrNull;

  /// A member's heading: the edition's ("SECT. II. MEMB. I.", "MEMB.
  /// III."), the first member's "THE FIRST SECTION, MEMBER, SUBSECTION."
  /// as its section and number.
  String _memberTitle(String heading, int section, int number) {
    if (heading.startsWith('THE FIRST SECTION')) {
      return 'Sect. ${_roman(section)}. Memb. ${_roman(number)}.';
    }
    return _smallCaps(heading);
  }

  /// A subsection's heading: "SUBSECT. II.—_The Definition…_".
  String _subject(XmlElement h4) => _smallCaps(_title(h4));

  /// "SECT. II. MEMB. I." as "Sect. II. Memb. I.", the edition's
  /// capitals the look's to set.
  String _smallCaps(String heading) => heading
      .replaceAll('SUBSECT.', 'Subsect.')
      .replaceAll('SECT.', 'Sect.')
      .replaceAll('MEMB.', 'Memb.');

  // The synopses.

  /// A synopsis: its trees, each a list of braces (`[.braces]`): the text
  /// before each of its top lists the root, that list its branches.
  void _synopsis(XmlElement synopsis, StringBuffer out) {
    var root = StringBuffer();
    for (final node in synopsis.children) {
      switch (node) {
        case XmlElement(localName: 'h2'):
          break;
        case XmlElement(localName: 'ul') && final ul:
          out
            ..writeln()
            ..writeln('[.braces]')
            ..writeln('* ${'$root'.trim().replaceAll(RegExp(r'\s+'), ' ')}');
          _branches(ul, 2, out);
          out.writeln();
          root = StringBuffer();
        case XmlText(:final text):
          root.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
        case final XmlElement element:
          root.write(inlineNode(element));
      }
    }
  }

  /// [ul]'s items at [depth] (from 1), each with its own branches.
  void _branches(XmlElement ul, int depth, StringBuffer out) {
    for (final li in ul.childElements.where((e) => e.localName == 'li')) {
      final label = StringBuffer();
      XmlElement? sublist;
      for (final node in li.children) {
        switch (node) {
          case XmlElement(localName: 'ul') && final ul:
            sublist = ul;
          case XmlText(:final text) when sublist == null:
            label.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
          case final XmlElement element when sublist == null:
            label.write(inlineNode(element));
          case _:
            break;
        }
      }
      out.writeln('${_marker(depth)} ${'$label'.trim()}');
      if (sublist != null) _branches(sublist, depth + 1, out);
    }
  }

  /// The list marker of [depth]: `*` to `*****`, then `-`, then `•` to
  /// `•••••` (AsciiDoc's markers, five of each, a new kind a level
  /// deeper).
  static String _marker(int depth) => depth <= 5
      ? '*' * depth
      : depth == 6
      ? '-'
      : '•' * (depth - 6);

  // Blocks.

  /// The paragraph being gathered from text outside any block (the
  /// edition's text after a poem, going on).
  final StringBuffer _loose = StringBuffer();

  void _flush(StringBuffer out) {
    final text = '$_loose'.trim();
    _loose.clear();
    if (text.isEmpty) return;
    out
      ..writeln()
      ..writeln(lineStart(text))
      ..writeln();
  }

  void _block(XmlNode node, StringBuffer out) {
    switch (node) {
      case XmlText(:final text):
        _loose.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
        return;
      case final XmlElement element:
        final classes = classesOf(element);
        switch (element.localName) {
          case 'p':
            _flush(out);
            final text = inline(element).trim();
            if (text.isEmpty) return;
            out
              ..writeln()
              ..writeln(lineStart(text.replaceAll(RegExp(r' *\+\n *'), ' +\n')))
              ..writeln();
          case 'hr':
            _flush(out);
          case 'h3' || 'h4' || 'h5' || 'h6':
            // (The title page's and the dedication's lines.)
            _flush(out);
            out
              ..writeln()
              ..writeln('[.${element.localName}]')
              ..writeln(lineStart(inline(element).trim()))
              ..writeln();
          case 'h1':
            // (The title on the title page: the document's first heading,
            // as PDF/UA asks.)
            _flush(out);
            out
              ..writeln()
              ..writeln('[discrete.title-line]')
              ..writeln('= ${inline(element).trim()}')
              ..writeln();
          case 'div' when classes.contains('fig'):
            _flush(out);
            for (final img in element.descendantElements) {
              if (img.localName == 'img') {
                final src = img.getAttribute('src')!.split('/').last;
                final alt = switch (src) {
                  'horoscope.png' =>
                    "Burton's horoscope, as it is drawn on his monument",
                  _ => img.getAttribute('alt') ?? '',
                };
                out
                  ..writeln()
                  ..writeln('image::$src[${attributeValue(alt)},align=center]')
                  ..writeln();
              }
            }
          case 'div'
              when classes.contains('poem') ||
                  classes.contains('blackletter') ||
                  classes.contains('stanza') ||
                  classes.contains('line'):
            _flush(out);
            _verse(element, out);
          case 'div' when classes.contains('bq'):
            _flush(out);
            final lang = languageOf(element);
            out
              ..writeln()
              ..writeln(lang == null ? '[quote]' : '[quote,lang=$lang]')
              ..writeln('____');
            final text = inline(element).trim();
            out
              ..writeln(lineStart(text))
              ..writeln('____')
              ..writeln();
          case 'div' || 'section':
            _flush(out);
            for (final child in element.children) {
              _block(child, out);
            }
            _flush(out);
          default:
            _loose.write(inlineNode(element));
        }
    }
  }

  /// A poem: its lines, its stanzas (couplets, stanzas, refrains) apart,
  /// its short lines (`bob`) set in.
  void _verse(XmlElement poem, StringBuffer out) {
    final stanzas = <List<String>>[[]];
    // (Text in the poem outside its lines: lines where it breaks.)
    final loose = StringBuffer();
    void endLoose() {
      for (final line in '$loose'.split('\n')) {
        if (line.trim().isNotEmpty) stanzas.last.add(line.trim());
      }
      loose.clear();
    }

    void lines(XmlElement element) {
      for (final node in element.children) {
        final XmlElement child;
        switch (node) {
          case XmlText(:final text):
            loose.write(escapeText(text.replaceAll(RegExp(r'[ \t]+'), ' ')));
            continue;
          case final XmlElement e
              when !const {'div', 'p'}.contains(e.localName):
            loose.write(inlineNode(e));
            continue;
          case final XmlElement e:
            endLoose();
            child = e;
        }
        final classes = classesOf(child);
        if (classes.contains('line')) {
          stanzas.last.add(inline(child).trim());
        } else if (classes.contains('bob')) {
          for (final line in child.childElements) {
            stanzas.last.add('   ${inline(line).trim()}');
          }
        } else if (classes.contains('couplet') ||
            classes.contains('stanza') ||
            classes.contains('refrain')) {
          if (stanzas.last.isNotEmpty) stanzas.add([]);
          lines(child);
          stanzas.add([]);
        } else {
          lines(child);
        }
      }
      endLoose();
    }

    if (classesOf(poem).contains('line')) {
      stanzas.last.add(inline(poem).trim());
    } else {
      lines(poem);
    }
    final kept = [
      for (final stanza in stanzas)
        if (stanza.isNotEmpty) stanza,
    ];
    if (kept.isEmpty) return;
    final lang = languageOf(poem);
    final roles = [
      if (classesOf(poem).contains('blackletter')) '.blackletter',
      if (lang != null && lang != 'en') '.foreign',
    ].join();
    out
      ..writeln()
      ..writeln('[verse$roles${lang == null ? '' : ',lang=$lang'}]')
      ..writeln('____')
      ..writeln([for (final stanza in kept) stanza.join('\n')].join('\n\n'))
      ..writeln('____')
      ..writeln();
  }

  /// [heading]'s text, without its anchors (the heading's id).
  String _title(XmlElement heading) {
    final out = StringBuffer();
    for (final node in heading.children) {
      out.write(switch (node) {
        XmlText(:final text) => escapeText(text),
        XmlElement(localName: 'a') && final a
            when a.getAttribute('href') == null =>
          inline(a),
        final XmlElement element => inlineNode(element),
      });
    }
    return '$out'.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// "ADVERTISEMENT TO THE LAST LONDON EDITION." as a heading in the
  /// edition's capitals, without its full stop.
  String _headingCase(String title) => title.replaceFirst(RegExp(r'\.$'), '');

  static String _roman(int number) {
    const numerals = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
    final out = StringBuffer();
    var rest = number;
    for (final (value, numeral) in numerals) {
      while (rest >= value) {
        out.write(numeral);
        rest -= value;
      }
    }
    return '$out';
  }
}

/// Mrs Beeton's Book of Household Management (1861): its preface and its
/// forty-four chapters, each heading a section; each recipe a section
/// with the `recipe` role, its paragraphs typed by their roles
/// (`ingredients`, `mode`, `particulars`: the time, the average cost,
/// how many it is sufficient for, when it is seasonable); the natural
/// history between the recipes, small, with the `note` role; the
/// numbered paragraphs anchored (`p-105`), and the analytical index,
/// which refers to them, as index terms in the paragraphs it names, so
/// that every format makes the index. The general contents and the
/// lists of engravings and plates are left out; of the engravings,
/// those the work has (`fetch.yml`) are set where the text has them.
final class _Beeton extends GutenbergText {
  new(this.body) : super(const {});

  final XmlElement body;

  /// The index terms for each numbered paragraph, by its number.
  final Map<int, List<List<String>>> _terms = {};

  /// The vulgar fractions, by how the transcription writes them.
  static const Map<String, String> _fractions = {
    '1/2': '½',
    '1/4': '¼',
    '3/4': '¾',
    '1/3': '⅓',
    '2/3': '⅔',
    '1/8': '⅛',
    '3/8': '⅜',
    '5/8': '⅝',
    '7/8': '⅞',
  };

  /// The engravings the work has, by their captions in the text.
  static const Map<String, String> _engravings = {
    'ROUEN DUCKS.': 'rouen-ducks.gif',
    'BOW-BILL DUCKS.': 'bow-bill-ducks.jpg',
  };

  void write(String dir) {
    final textDir = Directory('$dir/text')..createSync(recursive: true);
    for (final old in textDir.listSync().whereType<File>()) {
      old.deleteSync();
    }
    final nodes = body.childElements.toList();
    // (The analytical index, between its heading and the next.)
    final indexAt = nodes.indexWhere(
      (e) => e.localName == 'h2' && inline(e).startsWith('ANALYTICAL INDEX'),
    );
    for (final node in nodes.skip(indexAt + 1)) {
      if (node.localName == 'h2') break;
      if (node.localName == 'p') _indexLines(node);
    }
    final files = <String>[];
    void file(String name, StringBuffer out) {
      final text = '$out'
          .trim()
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          // (The fractions as the edition prints them, "1½ pint", where
          // the transcription writes "1-1/2 pint".)
          .replaceAllMapped(RegExp(r'\b(?:(\d+)-)?([1-7])/([2348])\b'), (m) {
            final fraction = _fractions['${m[2]}/${m[3]}'];
            if (fraction == null) return m[0]!;
            return '${m[1] ?? ''}$fraction';
          });
      File('$dir/text/$name.adoc').writeAsStringSync('$text\n');
      files.add(name);
    }

    // The preface.
    final prefaceAt = nodes.indexWhere(
      (e) => e.localName == 'h2' && inline(e).startsWith('PREFACE'),
    );
    final preface = StringBuffer()
      ..writeln('[preface]')
      ..writeln('== Preface')
      ..writeln();
    for (final node in nodes.skip(prefaceAt + 1)) {
      if (node.localName.startsWith('h') && node.localName != 'h5') break;
      if (node.localName == 'h5') {
        preface
          ..writeln()
          ..writeln('[.signature]')
          ..writeln(_titleCase(inline(node).trim()))
          ..writeln();
        continue;
      }
      _paragraph(node, preface);
    }
    file('preface', preface);

    // (The chapters' titles, from the general contents: "6.—RECIPES.")
    final contentsAt = nodes.indexWhere(
      (e) => e.localName == 'h2' && inline(e).startsWith('GENERAL CONTENTS'),
    );
    final titles = <String>[];
    for (final node in nodes.skip(contentsAt + 1)) {
      if (node.localName == 'h2') break;
      final text = node.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      for (final m in RegExp(
        r'(?:^|\s)(?:[IVX]+|\d+)\.?—(.*?)(?=\s(?:[IVX]+|\d+)\.?—|$)',
      ).allMatches(text)) {
        titles.add(m[1]!.trim());
      }
    }
    String key(String text) =>
        text.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');

    // The chapters.
    final start = nodes.indexWhere((e) => e.localName == 'h1');
    _number(nodes.skip(start + 1));
    StringBuffer? out;
    var chapter = 0;
    var expectTitle = false;
    for (final node in nodes.skip(start + 1)) {
      if (node.getAttribute('id') == 'pg-end-separator') break;
      final text = inline(node).trim();
      final plain = node.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      // (A heading: an element's, a paragraph set apart by its margin, or
      // one in capitals alone (a recipe's name and its kind).)
      final heading =
          node.localName.startsWith('h') ||
          (node.localName == 'p' &&
              !plain.startsWith('[Illustration') &&
              // (Not a paragraph that opens a section of the text.)
              !RegExp(r'^\d+\.').hasMatch(text) &&
              plain.length < 120 &&
              ((node.getAttribute('style') ?? '').contains('margin-top') ||
                  RegExp(
                    r"^[A-Z][A-Z\s,.&;’'-]*[A-Z]{3}[A-Z\s,.&;’'-]*"
                    r'(\([^)]*\))?\.?$',
                  ).hasMatch(plain)));
      if (heading && RegExp(r'^CHAPTER [IVXLC]+\.$').hasMatch(text)) {
        if (out != null) file('chapter-${'$chapter'.padLeft(2, '0')}', out);
        chapter++;
        out = StringBuffer();
        expectTitle = true;
        continue;
      }
      if (out == null) continue;
      // ("RECIPES.", which heads the recipes of a chapter: left out.)
      if (heading && text == 'RECIPES.') continue;
      if (expectTitle) {
        expectTitle = false;
        final title = chapter <= titles.length ? titles[chapter - 1] : plain;
        out
          ..writeln('[#chapter-$chapter]')
          ..writeln('== ${escapeText(_titleCase(title))}')
          ..writeln();
        // (The chapter's own heading, its title: not again.)
        if (heading &&
            key(plain).startsWith(key(title).split('GENERAL').first)) {
          continue;
        }
      }
      if (heading) {
        // (A recipe: its first paragraph after the heading (and a
        // subtitle in brackets) numbered and its ingredients.)
        final rest = nodes.skip(nodes.indexOf(node) + 1).take(3);
        final recipe = rest.any(
          (n) => RegExp(r'^\d+\.[ —]INGREDIENTS').hasMatch(inline(n).trim()),
        );
        out
          ..writeln()
          ..writeln(recipe ? '[.recipe]' : '')
          ..writeln('=== ${escapeText(_titleCase(plain))}')
          ..writeln();
        continue;
      }
      _paragraph(node, out);
    }
    if (out != null) file('chapter-${'$chapter'.padLeft(2, '0')}', out);
    final unplaced = _terms.keys.where((n) => !_placed.contains(n)).toList();
    stdout.writeln(
      '${files.length} files; ${_placed.length} paragraphs indexed'
      '${unplaced.isEmpty ? '' : '; not found: $unplaced'}',
    );
  }

  /// The numbered paragraphs whose index terms are placed.
  final Set<int> _placed = {};

  /// The numbers of the book's numbered paragraphs, by their elements:
  /// the book numbers its paragraphs in order, so a number out of order
  /// is a list's, the text's own (not here), and a few are misprinted
  /// (1510 as 510, 1526 as 1536, 2071 as 1071, 2548 as 4548): a number
  /// that differs from the one after the last in one figure, or lacks its
  /// first, where the next goes on from that, is taken as that.
  final Map<XmlElement, int> _numbers = {};

  void _number(Iterable<XmlElement> nodes) {
    final numbered = [
      for (final node in nodes)
        if (node.localName == 'p')
          if (RegExp(r'^(\d+)\.(?: |—)').firstMatch(node.innerText.trim())
              case final m?)
            (node, int.parse(m[1]!)),
    ];
    var last = 0;
    for (final (i, (node, printed)) in numbered.indexed) {
      final next = i + 1 < numbered.length ? numbered[i + 1].$2 : null;
      final expected = last + 1;
      final misprint =
          last > 0 &&
          printed != expected &&
          (_oneFigureApart('$printed', '$expected') ||
              ('$printed'.length == '$expected'.length - 1 &&
                  '$expected'.endsWith('$printed'))) &&
          (next == null || next == expected + 1);
      final number = misprint
          ? expected
          : printed > last && printed <= last + 40
          ? printed
          : null;
      if (number == null) continue;
      _numbers[node] = number;
      last = number;
    }
  }

  static bool _oneFigureApart(String a, String b) =>
      a.length == b.length &&
      [
            for (var i = 0; i < a.length; i++)
              if (a[i] != b[i]) i,
          ].length ==
          1;

  /// A paragraph of the text, by what it is.
  void _paragraph(XmlElement node, StringBuffer out) {
    if (node.localName != 'p') return;
    var text = inline(node).trim();
    if (text.isEmpty || text == '[Illustration]') return;
    final plain = node.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (RegExp(r'^\[Illustration\]\.?$').hasMatch(plain)) return;
    if (RegExp(r'^\[Illustration: (.*?)\]\.?$').firstMatch(plain)
        case final m?) {
      final image = _engravings[m[1]];
      if (image != null) {
        out
          ..writeln()
          ..writeln('.${_titleCase(m[1]!)}')
          ..writeln(
            'image::$image[${attributeValue(_titleCase(m[1]!))},'
            'align=center]',
          )
          ..writeln();
      }
      return;
    }
    // (An engraving's place in the text, which the work hasn't: left
    // out.)
    text = text
        .replaceAll(RegExp(r' ?&#91;Illustration(?::[^&]*)?&#93;\.?'), '')
        .trim();
    // (Lines broken with spaces before them: verse.)
    if (text.contains(' +\n') &&
        node.children.whereType<XmlText>().any(
          (t) => t.text.startsWith('  ') || t.text.contains('\n  '),
        )) {
      final lines = [
        for (final line in text.split(' +\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      out
        ..writeln()
        ..writeln('[verse]')
        ..writeln('____')
        ..writeln(lines.join('\n'))
        ..writeln('____')
        ..writeln();
      return;
    }
    final indented = (node.getAttribute('style') ?? '').contains('margin-left');
    String? role;
    String? anchor;
    // (A numbered paragraph: its number an anchor, its index terms in it;
    // a recipe's ingredients; the capitals it opens with small capitals.)
    if (RegExp(r'^(\d+)\.(?: |—)(.*)$', dotAll: true).firstMatch(text)
        case final m? when _numbers[node] != null) {
      final number = _numbers[node]!;
      anchor = 'p-$number';
      var rest = m[2]!;
      if (rest.startsWith('INGREDIENTS')) {
        role = 'ingredients';
        rest = rest.replaceFirst('INGREDIENTS', '[.label]#Ingredients#');
      } else {
        rest = _smallCaps(rest);
      }
      final terms = [
        for (final term in _terms[number] ?? const <List<String>>[])
          '(((${term.map(_indexText).join(', ')})))',
      ].join();
      if (terms.isNotEmpty) _placed.add(number);
      final dash = text.startsWith('$number.—') ? '—' : ' ';
      text = '[[$anchor]]$number.$dash$terms$rest';
    } else if (indented) {
      role = 'note';
      text = _smallCaps(text);
    } else if (RegExp('^_(Mode|Choosing and Trussing)_').hasMatch(text) ||
        text.startsWith('__Mode__')) {
      role = 'mode';
    } else if (RegExp('^_{1,2}(Time|Average cost|Sufficient|Seasonable)')
        .hasMatch(text)) {
      role = 'particulars';
    } else if (RegExp(r'^\(_{1,2}.*_{1,2}\.?\)$').hasMatch(text)) {
      role = 'subtitle';
    }
    out.writeln();
    if (role != null) out.writeln('[.$role]');
    out
      ..writeln(lineStart(text.replaceAll(RegExp(r' *\+\n *'), ' ')))
      ..writeln();
  }

  /// [text] with the capitals it opens with ("THE BUENOS AYRES DUCK.—",
  /// "IN NATURAL HISTORY, FISHES") in small capitals, as the edition sets
  /// them.
  String _smallCaps(String text) {
    final m = RegExp(
      r"^([A-Z][A-Z’'&;#0-9 -]*[A-Z](?:[,.][A-Z’' -]*[A-Z])*)(?=[.,—: ]|$)",
    ).firstMatch(text);
    if (m == null || !m[1]!.contains(RegExp('[A-Z]{2}'))) return text;
    return '[.sc]#${_titleCase(m[1]!)}#${text.substring(m.end)}';
  }

  /// "THE BUENOS AYRES DUCK" as "The Buenos Ayres Duck".
  static String _titleCase(String text) =>
      text.replaceAllMapped(RegExp(r"(\p{L})([\p{L}’']*)", unicode: true), (m) {
        final word = m[0]!;
        const small = {
          'OF',
          'AND',
          'THE',
          'A',
          'AN',
          'IN',
          'ON',
          'TO',
          'FOR',
          'OR',
          'AT',
          'BY',
          'WITH',
          'FROM',
        };
        if (m.start > 0 && small.contains(word.toUpperCase())) {
          return word.toLowerCase();
        }
        return '${m[1]!.toUpperCase()}${m[2]!.toLowerCase()}';
      });

  /// An index term's level as an index term's text: quoted when it holds
  /// a comma, its closing brackets written as references.
  static String _indexText(String text) {
    final escaped = escapeText(text.trim()).replaceAll(')', '&#41;');
    return escaped.contains(',')
        ? '"${escaped.replaceAll('"', '&#34;')}"'
        : escaped;
  }

  /// The lines of a paragraph of the analytical index: each a term (set
  /// in under the one above for a subentry) and the paragraphs it is in
  /// (`2705-7`, `933, 1022`; a page, `p. 955`, has no paragraph and is
  /// left out).
  void _indexLines(XmlElement p) {
    // (Its lines broken by `<br>`, or, in a paragraph without them, where
    // its source's lines break.)
    final broken = p.childElements.any((e) => e.localName == 'br');
    final lines = <String>[];
    var line = StringBuffer();
    for (final node in p.children) {
      switch (node) {
        case XmlElement(localName: 'br'):
          lines.add('$line');
          line = StringBuffer();
        case XmlText(:final text) when broken:
          line.write(text.replaceAll('\n', ''));
        case XmlText(:final text):
          final parts = text.split('\n');
          line.write(parts.first);
          for (final part in parts.skip(1)) {
            lines.add('$line');
            line = StringBuffer(part);
          }
        case final XmlElement e:
          line.write(e.innerText);
      }
    }
    lines.add('$line');
    for (final raw in lines) {
      if (raw.trim().isEmpty) continue;
      final depth = (raw.length - raw.trimLeft().length) ~/ 2;
      final m = RegExp(r'^(.*?)[ ,]*((?:pp?\.\s*)?\d[\d\s,\-p.]*)$')
          .firstMatch(raw.trim());
      final term = (m == null ? raw.trim() : m[1]!).trim();
      final refs = m == null ? '' : m[2]!;
      final level = depth.clamp(0, 2);
      // (A subentry under the heading above it; one set in further than
      // that, under it all the same.)
      if (_path.length > level) _path.length = level;
      _path.add(term);
      if (refs.isEmpty) continue;
      for (final number in _paragraphs(refs)) {
        (_terms[number] ??= []).add([..._path]);
      }
    }
  }

  /// The heading and subheadings above the index's line being read.
  final List<String> _path = [];

  /// The paragraph numbers in [refs]: `2705-7` 2705 to 2707, `909-52`
  /// 909 to 952; pages (`p. 955`, `pp. 909-52`) left out.
  static List<int> _paragraphs(String refs) {
    final numbers = <int>[];
    for (final part in refs.split(',')) {
      final ref = part.trim();
      if (ref.isEmpty || ref.startsWith('p')) continue;
      final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(ref);
      if (range == null) {
        if (int.tryParse(ref) case final n?) numbers.add(n);
        continue;
      }
      final from = int.parse(range[1]!);
      final short = range[2]!;
      // (The end's last figures: 2705-7 is 2705 to 2707.)
      final keep = '$from'.length - short.length;
      final to = int.parse(
        keep <= 0 ? short : '${'$from'.substring(0, keep)}$short',
      );
      if (to < from || to - from > 60) {
        numbers.add(from);
        continue;
      }
      for (var n = from; n <= to; n++) {
        numbers.add(n);
      }
    }
    return numbers;
  }
}

/// Punch, or the London Charivari: three issues of its first volume
/// (1841), each a chapter headed by its date (the look sets the masthead
/// over it), in columns; its pieces sections, their subheads discrete
/// headings; the pieces without heads between rules; the cuts where the
/// text has them, as wide as Project Gutenberg sets them (a quarter of
/// its page more than half the column, a half the column, the whole the
/// page across, the `cut` role), their captions their titles; a
/// pictorial initial floated at its piece's start, the letter it stands
/// for hidden (`hide`); the verse with its indents; the tables
/// (prescriptions, a thermometer, the Royal Alphabet with a cut to each
/// letter); the side notes footnotes. Project Gutenberg's page numbers
/// are left out.
final class _Punch extends GutenbergText {
  new(this.issues) : super(const {});

  /// Each issue's eBook number and body.
  final List<(String, XmlElement)> issues;

  /// The images the work fetches: their names and their eBooks.
  final List<(String, String)> images = [];

  String _book = '';

  void write(String dir) {
    final textDir = Directory('$dir/text')..createSync(recursive: true);
    for (final old in textDir.listSync().whereType<File>()) {
      old.deleteSync();
    }
    for (final (n, (book, body)) in issues.indexed) {
      _book = book;
      final out = StringBuffer();
      var started = false;
      for (final node in body.childElements) {
        if (node.getAttribute('id') == 'pg-end-separator') break;
        final text = node.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (!started) {
          // (The issue starts at its date, after the masthead.)
          if (node.localName == 'h2' &&
              RegExp(r'^[A-Z]+ \d+, 1841\.$').hasMatch(text)) {
            started = true;
            final date = text.replaceFirst('.', '');
            out
              ..writeln('[#issue-${n + 1}.issue.columns,column-count=2]')
              ..writeln('== ${_capitalized(date)}')
              ..writeln();
          }
          continue;
        }
        _block(node, out);
      }
      File('$dir/text/issue-${n + 1}.adoc').writeAsStringSync(
        '${'$out'.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n')}\n',
      );
    }
    stdout.writeln('${issues.length} issues; ${images.length} images');
  }

  /// "JULY 17, 1841" as "July 17, 1841".
  static String _capitalized(String text) => text.replaceAllMapped(
    RegExp('([A-Z])([A-Z]+)'),
    (m) => '${m[1]}${m[2]!.toLowerCase()}',
  );

  void _block(XmlElement node, StringBuffer out) {
    final classes = classesOf(node);
    switch (node.localName) {
      case 'h2':
        out
          ..writeln()
          ..writeln('=== ${_title(node)}')
          ..writeln();
      case 'h3' || 'h4' || 'h5':
        out
          ..writeln()
          ..writeln('[discrete]')
          ..writeln('==== ${_title(node)}')
          ..writeln();
      case 'hr':
        // (A rule between pieces; not after a heading, nor twice.)
        final last = '$out'.trimRight().split('\n').last;
        if (last.startsWith('==') || last == "'''") return;
        out
          ..writeln()
          ..writeln("'''")
          ..writeln();
      case 'p':
        final align = node.getAttribute('style') ?? '';
        out.writeln();
        if (align.contains('right')) out.writeln('[.signature]');
        if (align.contains('center')) out.writeln('[.text-center]');
        out
          ..writeln(lineStart(_paragraph(node)))
          ..writeln();
      case 'div' when classes.contains('poem'):
        _poem(node, out);
      case 'div'
          when classes.contains('figcenter') ||
              classes.contains('figleft') ||
              classes.contains('dropcap'):
        _figure(node, out, initial: classes.contains('dropcap'));
      case 'table':
        _table(node, out);
      case 'ol' || 'ul':
        out.writeln();
        for (final li in node.childElements.where((e) => e.localName == 'li')) {
          final text = [
            for (final p in li.childElements.where((e) => e.localName == 'p'))
              _paragraph(p),
          ];
          out.writeln(
            '${node.localName == 'ol' ? '.' : '*'} '
            '${text.isEmpty ? _paragraph(li) : text.join('\n+\n')}',
          );
        }
        out.writeln();
      case 'div' when classes.contains('pg_body_wrapper'):
        break;
      case 'div':
        for (final child in node.childElements) {
          _block(child, out);
        }
      default:
        break;
    }
  }

  String _title(XmlElement heading) =>
      inline(heading).trim().replaceAll(RegExp(r'\s*\+\n\s*'), ' ');

  /// A paragraph's text: its side notes (a raised number and the note
  /// after it) footnotes.
  String _paragraph(XmlElement p) {
    final out = StringBuffer();
    final children = p.children.toList();
    for (var i = 0; i < children.length; i++) {
      final next = i + 1 < children.length ? children[i + 1] : null;
      switch (children[i]) {
        case XmlElement(localName: 'sup') && final sup
            when next is XmlElement && classesOf(next).contains('sidenote'):
          final number = RegExp.escape(sup.innerText.trim());
          final note = inline(next)
              .trim()
              .replaceFirst(RegExp('^$number\\.\\s*'), '');
          out.write('footnote:[$note]');
          i++;
        case XmlText(:final text):
          out.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
        case final XmlElement e:
          out.write(inlineNode(e));
      }
    }
    return '$out'.trim().replaceAll(RegExp(r' *\+\n *'), ' +\n');
  }

  @override
  List<String> spanRoles(XmlElement element) => [
    for (final role in classesOf(element))
      if (const {'sc', 'hide', 'emph'}.contains(role)) role,
  ];

  @override
  String span(XmlElement element) {
    if (classesOf(element).contains('pagenum')) return '';
    return super.span(element);
  }

  /// A poem: its stanzas, its lines set in by their indent classes.
  void _poem(XmlElement poem, StringBuffer out) {
    final stanzas = <String>[];
    for (final stanza in poem.childElements) {
      final lines = <String>[];
      for (final p in stanza.childElements.where((e) => e.localName == 'p')) {
        final indent = classesOf(p)
            .where((c) => RegExp(r'^i\d$').hasMatch(c))
            .firstOrNull;
        final ems = indent == null ? 0 : int.parse(indent.substring(1)) ~/ 2;
        lines.add('${' ' * ems}${_paragraph(p)}');
      }
      if (lines.isNotEmpty) stanzas.add(lines.join('\n'));
    }
    if (stanzas.isEmpty) return;
    out
      ..writeln()
      ..writeln('[verse]')
      ..writeln('____')
      ..writeln(stanzas.join('\n\n'))
      ..writeln('____')
      ..writeln();
  }

  /// An image's macro: as wide as Project Gutenberg sets it.
  String _image(XmlElement img, {bool block = true, bool initial = false}) {
    final src = img.getAttribute('src')!.split('/').last;
    if (!images.any((i) => i.$1 == src)) images.add((src, _book));
    final alt = attributeValue(img.getAttribute('alt') ?? '');
    final width = RegExp(r'width:\s*(\d+)%')
        .firstMatch(img.getAttribute('style') ?? '')
        ?.group(1);
    if (!block) {
      final height = img.getAttribute('height');
      return 'image:$src[$alt${height == null ? '' : ',height=$height'}]';
    }
    if (initial) {
      return 'image::$src[$alt,float=left,pdfwidth=40%,role=initial]';
    }
    return switch (width) {
      '100' => 'image::$src[$alt,role=cut,align=center]',
      '25' => 'image::$src[$alt,pdfwidth=55%,align=center]',
      _ => 'image::$src[$alt,align=center]',
    };
  }

  @override
  String inlineNode(XmlElement element) => element.localName == 'img'
      ? _image(element, block: false)
      : super.inlineNode(element);

  /// A figure: its image, its caption (the paragraphs after it) its
  /// title; a pictorial initial floated left.
  void _figure(XmlElement figure, StringBuffer out, {required bool initial}) {
    final img = figure.descendantElements.firstWhere(
      (e) => e.localName == 'img',
    );
    final caption = [
      for (final p in figure.childElements.where((e) => e.localName == 'p'))
        _paragraph(p).replaceAll(' +\n', ' '),
    ].join(' ');
    out.writeln();
    if (caption.isNotEmpty) out.writeln('.$caption');
    out
      ..writeln(_image(img, initial: initial))
      ..writeln();
  }

  void _table(XmlElement table, StringBuffer out) {
    final allRows = [
      for (final tr in table.descendantElements.where(
        (e) => e.localName == 'tr',
      ))
        [
          for (final td in tr.childElements.where((e) => e.localName == 'td'))
            td,
        ],
    ];
    // (Each cell's row span, no further than the table (one says nine
    // where eight are left), and without the rows that hold no cell of
    // their own, which a table can't have.)
    final rowspans = <XmlElement, int>{
      for (final (r, row) in allRows.indexed)
        for (final td in row)
          td: math.min(
            int.tryParse(td.getAttribute('rowspan') ?? '') ?? 1,
            allRows.length - r,
          ),
    };
    for (final (e, row) in allRows.indexed) {
      if (row.isNotEmpty) continue;
      for (final (r, above) in allRows.take(e).indexed) {
        for (final td in above) {
          if (r + rowspans[td]! > e) rowspans[td] = rowspans[td]! - 1;
        }
      }
    }
    final rows = [
      for (final row in allRows)
        if (row.isNotEmpty) row,
    ];
    final columns = rows.fold(0, (n, row) {
      final width = row.fold(
        0,
        (w, td) => w + (int.tryParse(td.getAttribute('colspan') ?? '') ?? 1),
      );
      return math.max(n, width);
    });
    if (columns == 0) return;
    out
      ..writeln()
      ..writeln('[%noheader,cols="$columns*",frame=none,grid=none]')
      ..writeln('|===');
    // (Each column's cells still spanning down from rows above.)
    final spanning = List.filled(columns, 0);
    for (final row in rows) {
      var column = 0;
      void skipSpanned() {
        while (column < columns && spanning[column] > 0) {
          spanning[column]--;
          column++;
        }
      }

      for (final td in row) {
        skipSpanned();
        final colspan = int.tryParse(td.getAttribute('colspan') ?? '') ?? 1;
        final rowspan = rowspans[td]!;
        final span = [
          if (colspan > 1) '$colspan',
          if (rowspan > 1) '.$rowspan',
        ].join();
        final spec = span.isEmpty ? '' : '$span+';
        for (var c = column; c < math.min(column + colspan, columns); c++) {
          spanning[c] = rowspan - 1;
        }
        column += colspan;
        final img = td.descendantElements
            .where((e) => e.localName == 'img')
            .firstOrNull;
        if (img != null) {
          out.writeln('${spec}a|${_image(img)}');
          continue;
        }
        final align = (td.getAttribute('style') ?? '').contains('right')
            ? '>'
            : '';
        final text = _paragraph(td)
            .replaceAll('|', '&#124;')
            .replaceAll(' +\n', ' ');
        out.writeln('$spec$align|$text');
      }
      // (A row of fewer cells than the table's columns: empty ones after.)
      while (column < columns) {
        skipSpanned();
        if (column >= columns) break;
        out.writeln('|');
        column++;
      }
      out.writeln();
    }
    out
      ..writeln('|===')
      ..writeln();
  }
}
