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
library;

import 'dart:io';

// (The workspace's XML reader, plain_svg's.)
import 'package:plain_svg/src/xml.dart';

import 'showcase_text.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('usage: dart run tool/showcase_gutenberg.dart WORK HTML');
    exit(64);
  }
  final [work, html] = arguments;
  final body = readGutenberg(File(html).readAsStringSync());
  switch (work) {
    case 'burton':
      _Burton(body).write('test/showcase/burton');
    default:
      stderr.writeln('unknown work: $work');
      exit(64);
  }
}

/// The body of Project Gutenberg's HTML [html] as an XML tree: its void
/// elements closed, so that the XML reader reads it.
XmlElement readGutenberg(String html) {
  final start = html.indexOf('<body');
  final end = html.lastIndexOf('</body>');
  final body = html
      .substring(start, end + '</body>'.length)
      .replaceAllMapped(
        RegExp(r'<(br|hr|img|meta|link|input|col|wbr)\b([^>]*?)/?>'),
        (m) => '<${m[1]}${m[2]}/>',
      );
  return parseXml(body);
}

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
