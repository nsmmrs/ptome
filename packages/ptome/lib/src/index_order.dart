/// The order of an index's terms: Asciidoctor's (case-insensitive by the
/// characters, the default), one of the two systems of The Chicago Manual
/// of Style's indexing chapter, or the language's collation, chosen by the
/// `index-sort` attribute (`letter-by-letter`, `word-by-word`,
/// `collation`, `asciidoctor`).
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
///
/// A document in another language than English (its `lang`) has its
/// index in that language's order unless `index-sort` names another: the
/// Unicode Collation Algorithm with CLDR's tailoring (`ä` after `z` in
/// Swedish, Chinese by pinyin, by stroke in Traditional Chinese), headed
/// by the language's index characters (Chinese's pinyin letters or stroke
/// counts, Japanese's kana rows). Terms sort by their readings: a term's
/// ruby, or `sort-as` (`indexterm:[漢字,sort-as=かんじ]`, one per level
/// separated by commas).
library;

import 'package:plain_unicode/plain_unicode.dart' show CollationKey, Collator;
import 'package:ptome/src/document.dart';

/// How an index's terms are ordered.
sealed class IndexOrder {
  const new();

  /// Asciidoctor's (and asciidoctor-pdf's): case-insensitively in ASCII
  /// letters, then by the characters.
  static const IndexOrder asciidoctor = AsciidoctorOrder._();

  /// Chicago's letter-by-letter system.
  static const IndexOrder letterByLetter = ChicagoOrder._(wordByWord: false);

  /// Chicago's word-by-word system.
  static const IndexOrder wordByWord = ChicagoOrder._(wordByWord: true);

  /// The order [doc]'s `index-sort` attribute names; when none, its
  /// language's collation where its `lang` isn't English (unless
  /// [compat]: `asciidoctor-compat`), else Asciidoctor's.
  static IndexOrder of(Document doc, {bool compat = false}) {
    final lang = doc.attr('lang') ?? '';
    return switch (doc.attr('index-sort')) {
      'letter-by-letter' => letterByLetter,
      'word-by-word' => wordByWord,
      'collation' => CollatedOrder(Collator(lang.isEmpty ? 'und' : lang)),
      'asciidoctor' => asciidoctor,
      _ when !compat && lang.isNotEmpty && !_english.hasMatch(lang) =>
        CollatedOrder(Collator(lang)),
      _ => asciidoctor,
    };
  }

  static final RegExp _english = RegExp(r'^en(?:[-_]|$)', caseSensitive: false);

  /// The text a term sorts by: its [text], or its [reading] (ruby,
  /// `sort-as`) in the orders that read it.
  String sortText(String text, String reading) => reading;

  /// The letter [text] is listed under (`@` for a symbol or a numeral).
  String letterOf(String text);

  /// How [a] compares with [b] in this order, as [subentry] terms when
  /// they are under another.
  int compare(String a, String b, {bool subentry = false});

  /// How letter [a] compares with letter [b] (`@` first).
  int compareLetters(String a, String b) => compare(a, b);
}

/// Asciidoctor's order: case-insensitively in ASCII letters, then by the
/// characters; a term under its first letter in capitals.
final class AsciidoctorOrder extends IndexOrder {
  const new _();

  @override
  String sortText(String text, String reading) => text;

  @override
  String letterOf(String text) {
    final first = text.isEmpty ? '' : String.fromCharCode(text.runes.first);
    if (!RegExp(r'^\p{L}', unicode: true).hasMatch(first)) return '@';
    return first.toUpperCase();
  }

  @override
  int compare(String a, String b, {bool subentry = false}) {
    final folded = _asciiFold(a).compareTo(_asciiFold(b));
    return folded != 0 ? folded : a.compareTo(b);
  }

  static String _asciiFold(String text) =>
      text.replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());
}

/// A language's collation (UTS #10 with CLDR's tailoring), its terms
/// under the language's index characters.
final class CollatedOrder extends IndexOrder {
  /// The order of [collator].
  new(this.collator);

  /// The collation.
  final Collator collator;

  final Map<String, CollationKey> _keys = {};

  late final Map<String, int> _places = {
    for (final (i, label) in collator.indexLabels.indexed) label: i,
  };

  CollationKey _key(String text) =>
      _keys[text] ??= collator.sortKey(text.trim());

  @override
  String letterOf(String text) => collator.indexLabel(text.trim()) ?? '@';

  @override
  int compare(String a, String b, {bool subentry = false}) {
    final c = _key(a).compareTo(_key(b));
    return c != 0 ? c : a.compareTo(b);
  }

  @override
  int compareLetters(String a, String b) {
    if (a == b) return 0;
    if (a == '@') return -1;
    if (b == '@') return 1;
    final pa = _places[a];
    final pb = _places[b];
    if (pa != null && pb != null) return pa - pb;
    return compare(a, b);
  }
}

/// One of Chicago's systems: letter by letter, or word by word.
final class ChicagoOrder extends IndexOrder {
  const new _({required this.wordByWord});

  /// Whether a word ends at a space, hyphen or dash (else spaces and
  /// hyphens don't count).
  final bool wordByWord;

  /// The letter [text] is listed under (`@` for a symbol or a numeral):
  /// its first letter in capitals, without its diacritics (`É` under
  /// `E`).
  @override
  String letterOf(String text) {
    final first = text.isEmpty ? '' : String.fromCharCode(text.runes.first);
    if (!RegExp(r'^\p{L}', unicode: true).hasMatch(first)) return '@';
    return _fold(first).substring(0, 1).toUpperCase();
  }

  @override
  int compare(String a, String b, {bool subentry = false}) {
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
    if (wordByWord) {
      // (A word ends at a space, hyphen or dash, sorting before letters.)
      folded = folded.replaceAll(RegExp(r'[\s\-‐-―/]+'), '\u0001');
    }
    folded = folded.replaceAll(
      RegExp(
        wordByWord ? r'[^\p{L}\p{N}\u0001]' : r'[^\p{L}\p{N}]',
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
