/// The index of a document for the HTML-based converters: the terms
/// (`(((...)))`, `((...))`, `indexterm:[]`, `indexterm2:[]`) found while
/// converting, each use given an anchor, rendered where the document has
/// an `[index]` section.
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/index_order.dart';
import 'package:ptome/src/inline.dart';
import 'package:ptome/src/section.dart';

/// A use of a term: its anchor in the text, the node it is in, and the
/// section it is in (null before the first section).
typedef IndexUse = ({String anchor, AbstractNode node, Section? section});

/// A term of the index, with its subterms.
final class IndexEntry {
  /// The term [markup] (converted inline markup), read as [text] and
  /// sorted by [reading], in the index of [_catalog].
  new(this.text, this.markup, [this._catalog, String? reading])
    : reading = reading ?? text;

  final IndexCatalog? _catalog;

  /// The term as plain text (for sorting).
  final String text;

  /// The term as converted inline markup.
  final String markup;

  /// What the term sorts by in the orders that read it: its ruby's
  /// reading or its `sort-as`, else its text.
  String reading;

  /// Where it is used, in document order.
  final List<IndexUse> uses = [];

  /// The term it refers to instead (`see`), if any.
  String? see;

  /// The terms it refers to as well (`see-also`).
  final List<String> seeAlso = [];

  final Map<String, IndexEntry> _subentries = {};

  /// The subterms, in index order.
  List<IndexEntry> get subentries => _sorted(
    _subentries.values,
    _catalog?.order ?? IndexOrder.asciidoctor,
    subentry: true,
  );
}

/// The terms of the index under one heading: a letter, or `@` for terms
/// that don't start with one.
typedef IndexLetter = ({String letter, List<IndexEntry> entries});

/// The index of a document, built while it is converted.
final class IndexCatalog {
  /// A catalog; with [always], terms are cataloged whether or not the
  /// document has an index section.
  new({this.always = false});

  /// Whether terms are cataloged whether or not the document has an index
  /// section.
  final bool always;

  final Map<String, IndexEntry> _entries = {};

  /// How its terms are ordered (`index-sort`).
  IndexOrder order = IndexOrder.asciidoctor;
  final Map<(Object, String, int), String> _anchors = {};
  final Map<(Object, String), int> _occurrences = {};
  int _sequence = 0;
  bool _active = false;

  /// Starts a conversion of [document]: terms are cataloged from now on
  /// when it has an `[index]` section and doesn't unset `index-html`;
  /// [compat] (`asciidoctor-compat`) leaves the language's order out.
  void begin(Document document, {bool compat = false}) {
    _occurrences.clear();
    order = IndexOrder.of(document, compat: compat);
    final unset =
        !document.attributeUnspecified('index-html') &&
        !document.hasAttr('index-html');
    _active = always || !unset && _hasIndexSection(document);
    // A title converted before now (a section's, for its id, while the
    // document was parsed) has no anchors for its terms: converted again,
    // its terms are cataloged.
    if (_active) _reconvertTitles(document);
  }

  static void _reconvertTitles(AbstractBlock block) {
    for (final child in block.blocks) {
      final source = child.sourceTitle;
      if (source != null &&
          (source.contains('((') || source.contains('indexterm'))) {
        child.title = source;
      }
      _reconvertTitles(child);
    }
  }

  /// Whether terms are being cataloged.
  bool get isActive => _active;

  static bool _hasIndexSection(AbstractBlock block) {
    for (final child in block.blocks) {
      if (child is Section) {
        if (child.sectname == 'index') return true;
        if (_hasIndexSection(child)) return true;
      }
    }
    return false;
  }

  /// Catalogs the term of [node] (converted to [terms], one per level,
  /// up to three) and returns the anchor of this use; null when terms
  /// aren't being cataloged.
  String? add(Inline node, List<String> terms) {
    if (!_active || terms.isEmpty) return null;
    // Passthroughs in a term are placeholders until the text around the
    // term is restored; the index, elsewhere, leaves them out.
    final markup = [
      for (final level in terms)
        level.replaceAll(RegExp('\u0096\\d+\u0097'), ''),
    ];
    final key = markup.join('\u0000');
    final parent = node.parent ?? node;
    final nth = _occurrences.update(
      (parent, key),
      (n) => n + 1,
      ifAbsent: () => 0,
    );
    final existing = _anchors[(parent, key, nth)];
    if (existing != null) return existing;
    final anchor = '_indexterm_${++_sequence}';
    _anchors[(parent, key, nth)] = anchor;
    final sortAs = node.attr('sort-as')?.split(',');
    var entries = _entries;
    IndexEntry? entry;
    for (final (i, level) in markup.take(3).indexed) {
      final text = _plain(level);
      final given = sortAs != null && i < sortAs.length ? sortAs[i].trim() : '';
      final reading = given.isNotEmpty ? given : _reading(level);
      entry = entries[text] ??= IndexEntry(text, level, this, reading);
      if (given.isNotEmpty) entry.reading = given;
      entries = entry._subentries;
    }
    entry!.uses.add((anchor: anchor, node: parent, section: _sectionOf(node)));
    if (node.attr('see') case final see?) {
      entry.see ??= see;
    } else {
      for (final term in node.seeAlso ?? const <String>[]) {
        if (!entry.seeAlso.contains(term)) entry.seeAlso.add(term);
      }
    }
    return anchor;
  }

  static Section? _sectionOf(AbstractNode node) {
    AbstractNode? current = node.parent;
    while (current != null) {
      if (current is Section) return current;
      current = current.parent;
    }
    return null;
  }

  /// The primary term named [text], if any.
  IndexEntry? primary(String text) => _entries[text];

  /// The terms (top level), in index order.
  List<IndexEntry> get entries => _sorted(_entries.values, order);

  /// The terms by letter, in index order.
  List<IndexLetter> get letters {
    final byLetter = <String, List<IndexEntry>>{};
    for (final entry in _entries.values) {
      final letter = order.letterOf(order.sortText(entry.text, entry.reading));
      (byLetter[letter] ??= []).add(entry);
    }
    final keys = byLetter.keys.toList()..sort(order.compareLetters);
    return [
      for (final key in keys)
        (letter: key, entries: _sorted(byLetter[key]!, order)),
    ];
  }
}

/// What [markup] reads as: its ruby by the readings (`<rt>`), as plain
/// text.
String _reading(String markup) => _plain(
  markup.replaceAllMapped(
    RegExp('<ruby>(.*?)</ruby>'),
    (m) =>
        [for (final rt in RegExp('<rt>(.*?)</rt>').allMatches(m[1]!)) rt[1]!]
            .join(),
  ),
);

/// [markup] without its tags and with its character references resolved.
String _plain(String markup) => markup
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#8217;', '’')
    .replaceAll('&amp;', '&')
    .trim();

List<IndexEntry> _sorted(
  Iterable<IndexEntry> entries,
  IndexOrder order, {
  bool subentry = false,
}) => entries.toList()
  ..sort((a, b) {
    final c = order.compare(
      order.sortText(a.text, a.reading),
      order.sortText(b.text, b.reading),
      subentry: subentry,
    );
    return c != 0 ? c : a.text.compareTo(b.text);
  });

/// The index of [catalog] as HTML, for an `[index]` section at [level]:
/// a heading per letter, then the terms, each with a link to every
/// section it is used in (labeled by [label]) and its see and see-also
/// references. With [epub], marked up with the EPUB Indexes vocabulary
/// (`epub:type="index-entry"`...), as an EPUB's reading systems read it.
/// Without [headings], one list, no letter above each group
/// (`index-category-headings`). [see] and [seeAlso] are the words that
/// refer to another term (`index-see-label`, `index-see-also-label`).
String indexHtml(
  IndexCatalog catalog, {
  required int level,
  required String Function(Section? section) label,
  String Function(IndexUse use)? href,
  bool epub = false,
  bool headings = true,
  String see = 'see',
  String seeAlso = 'see also',
}) {
  final hrefOf = href ?? (use) => '#${use.anchor}';
  String type(String value) => epub ? ' epub:type="$value"' : '';
  final ids = <IndexEntry, String>{};
  var next = 0;
  void name(Iterable<IndexEntry> entries) {
    for (final entry in entries) {
      ids[entry] = '_index_entry_${++next}';
      name(entry.subentries);
    }
  }

  final letters = catalog.letters;
  for (final letter in letters) {
    name(letter.entries);
  }
  String reference(String term) => switch (catalog.primary(_plain(term))) {
    final IndexEntry entry => '<a href="#${ids[entry]}">$term</a>',
    null => term,
  };
  String xref(String term, String kind) =>
      switch (catalog.primary(_plain(term))) {
        final IndexEntry entry =>
          '<a${type('index-xref-$kind')} href="#${ids[entry]}">$term</a>',
        null => term,
      };
  String related(String term) => epub ? xref(term, 'related') : reference(term);
  final heading = 'h${(level + 2).clamp(2, 6)}';
  final out = StringBuffer('<div class="index"${type('index')}>\n');
  void write(List<IndexEntry> entries) {
    out.write('<ul class="index-terms"${type('index-entry-list')}>\n');
    for (final entry in entries) {
      out.write(
        '<li id="${ids[entry]}"${type('index-entry')}>'
        '<span class="index-term"${type('index-term')}>'
        '${_balanced(entry.markup) ? entry.markup : _escape(entry.text)}</span>',
      );
      String locator(IndexUse use) =>
          '<a${type('index-locator')} href="${hrefOf(use)}">'
          '${label(use.section)}</a>';
      // One link per section, to the term's first use there.
      final sections = <Section?>{};
      final links = [
        for (final use in entry.uses)
          if (sections.add(use.section)) locator(use),
      ];
      if (entry.see case final target?) {
        out.write(
          ', <em>$see</em> ${epub ? xref(target, 'preferred') : reference(target)}',
        );
      } else {
        if (links.isNotEmpty) out.write(': ${links.join(', ')}');
        if (entry.seeAlso.isNotEmpty) {
          out.write(
            '; <em>$seeAlso</em> '
            '${[for (final term in entry.seeAlso) related(term)].join(', ')}',
          );
        }
      }
      if (entry.subentries.isNotEmpty) {
        out.write('\n');
        write(entry.subentries);
      }
      out.write('</li>\n');
    }
    out.write('</ul>\n');
  }

  if (headings) {
    for (final letter in letters) {
      out.write(
        '<div class="index-letter"${type('index-group')}>\n'
        '<$heading>${letter.letter}</$heading>\n',
      );
      write(letter.entries);
      out.write('</div>\n');
    }
  } else if (letters.isNotEmpty) {
    write(catalog.entries);
  }
  out.write('</div>');
  return out.toString();
}

/// Whether [document]'s index has a heading per letter (unless
/// `index-category-headings!`).
bool indexHasCategoryHeadings(Document document) =>
    document.attributeUnspecified('index-category-headings') ||
    document.hasAttr('index-category-headings');

/// The label of a link to a use of a term in [section] of [document]:
/// the section's title as plain text, or the document's title before the
/// first section.
String indexUseLabel(Section? section, Document document) {
  final title = section?.title ?? document.doctitle();
  final text = title == null ? '' : _plainLabel(title);
  return text.isEmpty ? 'top' : text;
}

/// [markup] without its tags (its character references kept, as HTML).
String _plainLabel(String markup) =>
    markup.replaceAll(RegExp('<[^>]*>'), '').trim();

/// Whether the tags of [markup] pair up (a term cut from text whose
/// emphasis marks don't pair, say, may leave one open).
bool _balanced(String markup) {
  const voids = {'br', 'img', 'wbr', 'hr', 'input', 'meta', 'link'};
  final open = <String>[];
  for (final m in RegExp(
    r'<(/?)([A-Za-z][\w-]*)[^>]*?(/?)>',
  ).allMatches(markup)) {
    final name = m[2]!.toLowerCase();
    if (m[3] == '/' || voids.contains(name)) continue;
    if (m[1] == '/') {
      if (open.isEmpty || open.removeLast() != name) return false;
    } else {
      open.add(name);
    }
  }
  return open.isEmpty;
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
