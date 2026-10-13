/// Units in HTML (ADR-0020), for the HTML5 and EPUB 3 converters: a unit's
/// mark is a span with the unit's ID and what it is (`class="unit"`,
/// `data-scheme`, `data-level`, `data-unit`), around its label; a note's
/// caller and its unit's entry are spans of their stream; a unit that is
/// blocks is a `div` around them.
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/inline.dart';

/// [value] escaped for an attribute in double quotes.
String _attr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');

/// The `data-` attributes for [names] that [attributes] has.
String _data(Map<String, String> attributes, List<String> names) => [
  for (final name in names)
    if (attributes[name] case final value?) ' data-$name="${_attr(value)}"',
].join();

/// A unit's mark: `<span id="v-exo-34-6" class="unit" data-scheme="bible"
/// data-level="verse" data-unit="Exod 34:6"><sup>6</sup></span>`; a
/// unit's end, `class="unit-end"`.
String htmlUnitMark(Inline node) {
  final id = node.id == null ? '' : ' id="${_attr(node.id!)}"';
  final kind = node.type == 'end' ? 'unit-end' : 'unit';
  final data = _data(node.attributes, const ['scheme', 'level', 'unit']);
  return '<span$id class="$kind"$data>${node.text ?? ''}</span>';
}

/// A note's caller (`class="note-call"`) or its unit's entry
/// (`class="note-entry"` and the entry's role), with its stream.
String htmlNote(Inline node) {
  final kind = node.type == 'entry' ? 'note-entry' : 'note-call';
  final role = node.role;
  final data = _data(node.attributes, const ['stream']);
  return '<span class="$kind${role == null ? '' : ' ${_attr(role)}'}"$data>'
      '${node.text ?? ''}</span>';
}

/// A unit that is blocks, around their [content].
String htmlUnitBlock(AbstractBlock node, String content) {
  final id = node.id == null ? '' : ' id="${_attr(node.id!)}"';
  final role = node.role;
  final data = _data(node.attributes, const ['scheme', 'level', 'unit']);
  return '<div$id class="unit${role == null ? '' : ' ${_attr(role)}'}"$data>\n'
      '$content\n'
      '</div>';
}

/// The note streams `:note-asides:` sets beside the text, not with the
/// footnotes: `sn` or `sn, tn`.
Set<String> htmlNoteAsides(Document document) => {
  for (final name in (document.attr('note-asides') ?? '').split(
    RegExp(r'[\s,]+'),
  ))
    if (name.isNotEmpty) name,
};

/// The stream [footnote] is set beside the text in, if any.
String? htmlAsideStream(Document document, Footnote footnote) =>
    switch (footnote.stream) {
      final stream? when htmlNoteAsides(document).contains(stream) => stream,
      _ => null,
    };

/// A footnote of a stream set beside the text, at its call: a span (a
/// footnote's text is inline) with the footnote's ID, which the call links
/// to.
String htmlNoteAside(Footnote footnote, String text) =>
    '<span class="note-aside" id="_footnotedef_${_attr(footnote.index)}" '
    'data-stream="${_attr(footnote.stream ?? '')}" role="note">$text</span>';

/// The style of a units document in HTML: a note stream's entries (the
/// cross-references) in a column on the left of the text and the notes
/// set beside it (`:note-asides:`) in one on the right, on a wide screen;
/// on a narrow one, the entries in a line of their own and each note
/// opened under its line when its call is followed.
String htmlUnitsStyle({required bool asides}) {
  final out = StringBuffer(
    '<style>'
    '.note-entry{display:block;font-size:.8125rem;line-height:1.4;'
    'color:rgba(0,0,0,.6)}'
    '.note-entry>br,.note-entry>.entry-heading{display:none}'
    // (The unit's number is the entry's, there.)
    '.unit:has(+.note-entry){font-size:0}',
  );
  if (asides) {
    out.write(
      '.note-aside{display:none;font-size:.8125rem;line-height:1.45;'
      'color:rgba(0,0,0,.75)}'
      '.note-aside:target{display:block;margin:.5em 0;padding:.5em .75em;'
      'border-left:2px solid #dddddf;background:#f8f8f7}',
    );
  }
  final margin = asides ? 20.9375 : 0.9375;
  out.write(
    '@media screen and (min-width:75em){'
    '#header,#content,#footnotes,#footer{'
    // (The text as wide as before: 60.625em between the paddings.)
    'max-width:${60.625 + 10.9375 + margin}em;'
    'padding-left:10.9375em;padding-right:${margin}em}'
    '.note-entry{float:left;clear:left;width:8.5rem;margin-left:-10rem;'
    'text-align:right}'
    '.note-entry>br,.note-entry>.entry-heading{display:revert}'
    '.unit:has(+.note-entry){font-size:inherit}'
    '.note-entry>.entry-heading{font-weight:bold}',
  );
  if (asides) {
    out.write(
      '.note-aside{display:block;float:right;clear:right;width:18rem;'
      'margin:0 -20rem .5em 0}'
      '.note-aside:target{margin:0 -20rem .5em 0;padding:0 0 0 .5em}',
    );
  }
  out.write('}</style>');
  return out.toString();
}

/// The style of a units document in EPUB: as on a narrow screen in HTML,
/// a note stream's entries each in a line of its own (the unit's number
/// theirs).
const String epubUnitsStyle =
    '.note-entry { display: block; font-size: 0.8125em; line-height: 1.4; '
    'color: #666; }\n'
    '.note-entry > br, .note-entry > .entry-heading { display: none; }\n'
    '.unit:has(+ .note-entry) { font-size: 0; }\n';
