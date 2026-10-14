/// Ruby (`ruby:漢字[かんじ]`, Ptome's syntax), as each format writes it.
library;

import 'package:ptome/src/inline.dart';

/// The option after the readings that makes mono readings jukugo ruby
/// (JLREQ 3.3.7): `ruby:鬼門[き もん,jukugo]`.
final RegExp _jukugo = RegExp(r'\s*,\s*jukugo\s*$');

/// The readings of a ruby [node], its options left out.
String _reading(Inline node) =>
    (node.attributes['reading'] ?? '').replaceFirst(_jukugo, '');

/// Whether a ruby [node]'s mono readings are a compound's (jukugo ruby,
/// `,jukugo` after them): set as one where a character has three or more
/// reading characters, each on its own character otherwise.
bool rubyJukugo(Inline node) =>
    _jukugo.hasMatch(node.attributes['reading'] ?? '');

/// The base of a ruby [node] and each part of it with its reading: one a
/// character where the readings, separated by spaces, are as many as the
/// base's characters (mono ruby); else the whole base with the whole
/// reading (group ruby).
List<(String, String)> rubyPairs(Inline node) {
  final base = node.text ?? '';
  final reading = _reading(node);
  final readings = reading.split(' ').where((r) => r.isNotEmpty).toList();
  final characters = [for (final c in base.runes) String.fromCharCode(c)];
  if (readings.length > 1 && readings.length == characters.length) {
    return [for (final (i, c) in characters.indexed) (c, readings[i])];
  }
  return [(base, reading)];
}

/// Whether [reading] is Bopomofo, symbols and tone marks (zhuyin).
bool _bopomofo(String reading) =>
    reading.isNotEmpty &&
    reading.runes.every(
      (c) =>
          (c >= 0x3105 && c <= 0x312F) ||
          (c >= 0x31A0 && c <= 0x31BF) ||
          const {0x02C7, 0x02CA, 0x02CB, 0x02D9, 0x02EA, 0x02EB}.contains(c),
    );

/// HTML's `<ruby>`: each part's base, then its reading in `<rt>`, between
/// `<rp>` parentheses for readers without ruby; Bopomofo at the right of
/// its characters (CSS's `ruby-position: inter-character`, as CLREQ sets
/// zhuyin).
String rubyHtml(Inline node) {
  final pairs = rubyPairs(node);
  final zhuyin = pairs.every((pair) => _bopomofo(pair.$2));
  return [
    if (zhuyin) '<ruby style="ruby-position: inter-character">' else '<ruby>',
    for (final (base, reading) in pairs)
      '$base<rp>(</rp><rt>$reading</rt><rp>)</rp>',
    '</ruby>',
  ].join();
}

/// Ruby as text: the base, its reading after it in parentheses.
String rubyText(Inline node) => '${node.text ?? ''}(${_reading(node)})';

/// Warichu in HTML: its text in full-width parentheses, half the size, in
/// a `<span class="warichu">` (two lines within the line is CSS's to do,
/// which it can't yet).
String warichuHtml(Inline node) =>
    '<span class="warichu">（${node.text ?? ''}）</span>';

/// Warichu as text: in full-width parentheses.
String warichuText(Inline node) => '（${node.text ?? ''}）';
