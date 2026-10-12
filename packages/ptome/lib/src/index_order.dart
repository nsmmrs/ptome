/// The order of an index's terms: Asciidoctor's (case-insensitive by the
/// characters, the default), or one of the two systems of The Chicago
/// Manual of Style's indexing chapter, chosen by the `index-sort`
/// attribute (`letter-by-letter`, `word-by-word`).
///
/// In both of Chicago's systems a heading is alphabetized up to its first
/// comma or opening parenthesis (an inverted name, a qualifier), then by
/// what follows; punctuation and diacritics don't count (`Élan` with
/// `elan`); headings that begin with a symbol come first, then those that
/// begin with a numeral, in numerical order (2 before 10), then the
/// letters; and a subentry's opening article, preposition or conjunction
/// is passed over (`in poetry` with `poetry`). Letter by letter, spaces
/// and hyphens don't count either (`Newark` before `New York`); word by
/// word, a word ends at a space, hyphen or dash and sorts before a longer
/// one (`New York` before `Newark`).
library;

import 'package:ptome/src/document.dart';

/// How an index's terms are ordered.
enum IndexOrder {
  /// Asciidoctor's (and asciidoctor-pdf's): case-insensitively in ASCII
  /// letters, then by the characters.
  asciidoctor,

  /// Chicago's letter-by-letter system.
  letterByLetter,

  /// Chicago's word-by-word system.
  wordByWord;

  /// The order [doc]'s `index-sort` attribute names (Asciidoctor's when
  /// none).
  static IndexOrder of(Document doc) => switch (doc.attr('index-sort')) {
    'letter-by-letter' => letterByLetter,
    'word-by-word' => wordByWord,
    _ => asciidoctor,
  };

  /// The letter [text] is listed under (`@` for a symbol or a numeral):
  /// its first letter in capitals, without its diacritics in Chicago's
  /// systems (`É` under `E`).
  String letterOf(String text) {
    final first = text.isEmpty ? '' : String.fromCharCode(text.runes.first);
    if (!RegExp(r'^\p{L}', unicode: true).hasMatch(first)) return '@';
    if (this == asciidoctor) return first.toUpperCase();
    return _fold(first).substring(0, 1).toUpperCase();
  }

  /// How [a] compares with [b] in this order, as [subentry] terms when
  /// they are under another.
  int compare(String a, String b, {bool subentry = false}) {
    if (this == asciidoctor) {
      final folded = _asciiFold(a).compareTo(_asciiFold(b));
      return folded != 0 ? folded : a.compareTo(b);
    }
    final ka = _key(a, subentry: subentry);
    final kb = _key(b, subentry: subentry);
    for (var i = 0; i < ka.length && i < kb.length; i++) {
      final c = ka[i].compareTo(kb[i]);
      if (c != 0) return c;
    }
    final c = ka.length.compareTo(kb.length);
    return c != 0 ? c : a.compareTo(b);
  }

  /// The parts [text] sorts by: its class (a symbol, a numeral, a letter
  /// first), then its heading before the first comma or parenthesis, then
  /// the rest.
  List<String> _key(String text, {required bool subentry}) {
    var heading = text.trim();
    if (subentry) heading = heading.replaceFirst(_passedOver, '');
    final cut = heading.indexOf(RegExp('[,(]'));
    final (head, rest) = cut < 0
        ? (heading, '')
        : (heading.substring(0, cut), heading.substring(cut + 1));
    final first = _fold(head)
        .replaceAll(RegExp(r'^[\s\p{P}]+', unicode: true), '');
    final kind = first.isEmpty
        ? '0'
        : RegExp(r'^\p{L}', unicode: true).hasMatch(first)
        ? '2'
        : RegExp(r'^\d').hasMatch(first)
        ? '1'
        : '0';
    return [kind, _sortable(head), _sortable(rest)];
  }

  /// [text] folded and stripped as this system reads it, its numerals
  /// padded to sort by their values.
  String _sortable(String text) {
    var folded = _fold(text);
    if (this == wordByWord) {
      // (A word ends at a space, hyphen or dash, sorting before letters.)
      folded = folded.replaceAll(RegExp(r'[\s\-‐-―/]+'), '\u0001');
    }
    folded = folded.replaceAll(
      RegExp(
        this == wordByWord ? r'[^\p{L}\p{N}\u0001]' : r'[^\p{L}\p{N}]',
        unicode: true,
      ),
      '',
    );
    return folded
        .replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.padLeft(12, '0'))
        .replaceAll(RegExp('^\u0001+|\u0001+\$'), '');
  }

  static final RegExp _passedOver = RegExp(
    '^(?:(?:a|an|the|of|in|on|at|to|by|for|from|with|and|or|as|about|into|'
    r'versus|vs\.?)\s+)+',
    caseSensitive: false,
  );

  static String _asciiFold(String text) =>
      text.replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());

  /// [text] in lower case without the diacritics of Latin letters.
  static String _fold(String text) {
    final out = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      out.write(_latin[rune] ?? String.fromCharCode(rune));
    }
    return '$out';
  }

  /// The Latin letters with diacritics (and ligatures), by their bases.
  static final Map<int, String> _latin = () {
    const table = {
      'a': 'àáâãäåāăą',
      'c': 'çćĉċč',
      'd': 'ďđð',
      'e': 'èéêëēĕėęě',
      'g': 'ĝğġģ',
      'h': 'ĥħ',
      'i': 'ìíîïĩīĭįı',
      'j': 'ĵ',
      'k': 'ķ',
      'l': 'ĺļľŀł',
      'n': 'ñńņňŉ',
      'o': 'òóôõöøōŏő',
      'r': 'ŕŗř',
      's': 'śŝşšſ',
      't': 'ţťŧ',
      'u': 'ùúûüũūŭůűų',
      'w': 'ŵ',
      'y': 'ýÿŷ',
      'z': 'źżž',
      'ae': 'æ',
      'oe': 'œ',
      'ss': 'ß',
      'th': 'þ',
    };
    return {
      for (final MapEntry(key: base, value: letters) in table.entries)
        for (final rune in letters.runes) rune: base,
    };
  }();
}
