/// The properties text shaping reads (Unicode 18.0.0): a code point's
/// General_Category, Script, Indic_Syllabic_Category,
/// Indic_Positional_Category, Vertical_Orientation and
/// Default_Ignorable_Code_Point, and canonical decomposition and
/// composition (Hangul syllables by their algorithm).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_unicode/src/properties_data.g.dart' as data;
import 'package:plain_unicode/src/properties_data.g.dart'
    show
        GeneralCategory,
        IndicPositionalCategory,
        IndicSyllabicCategory,
        VerticalOrientation;

export 'package:plain_unicode/src/properties_data.g.dart'
    show
        GeneralCategory,
        IndicPositionalCategory,
        IndicSyllabicCategory,
        VerticalOrientation,
        propertiesUnicodeVersion;

final class _Table {
  new()
    : stage1 = _words(data.stage1),
      stage2 = _words(data.stage2),
      stage3 = _words(data.stage3);

  final Uint16List stage1;
  final Uint16List stage2;
  final Uint16List stage3;

  int operator [](int c) => c < 0 || c > 0x10ffff
      ? data.palette[0]
      : data.palette[stage3[stage2[stage1[c >> 11] + (c >> 5 & 63)] +
            (c & 31)]];

  static Uint16List _words(String encoded) {
    final bytes = base64.decode(encoded);
    final words = Uint16List(bytes.length ~/ 2);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < words.length; i++) {
      words[i] = view.getUint16(i * 2, Endian.little);
    }
    return words;
  }
}

final _Table _table = _Table();

/// [codePoint]'s General_Category.
GeneralCategory generalCategory(int codePoint) =>
    GeneralCategory.values[_table[codePoint] & 0x1f];

/// [codePoint]'s Script, as its ISO 15924 code (`Latn`, `Deva`; `Zyyy`
/// for Common, `Zinh` for Inherited, `Zzzz` for Unknown).
String scriptOf(int codePoint) =>
    data.scriptCodes[_table[codePoint] >> 5 & 0xff];

/// [codePoint]'s Indic_Syllabic_Category.
IndicSyllabicCategory indicSyllabicCategory(int codePoint) =>
    IndicSyllabicCategory.values[_table[codePoint] >> 13 & 0x3f];

/// [codePoint]'s Indic_Positional_Category.
IndicPositionalCategory indicPositionalCategory(int codePoint) =>
    IndicPositionalCategory.values[_table[codePoint] >> 19 & 0xf];

/// [codePoint]'s Vertical_Orientation (UAX #50).
VerticalOrientation verticalOrientation(int codePoint) =>
    VerticalOrientation.values[_table[codePoint] >> 23 & 0x3];

/// Whether [codePoint] is a Default_Ignorable_Code_Point (shown as
/// nothing where a font has no glyph for it).
bool isDefaultIgnorable(int codePoint) => _table[codePoint] >> 25 & 1 == 1;

/// Whether [codePoint] is an emoji character (Emoji, UTS #51): one with
/// an emoji presentation, by default or after U+FE0F.
bool isEmoji(int codePoint) => _table[codePoint] >> 26 & 1 == 1;

/// Whether [codePoint] is shown as an emoji by default
/// (Emoji_Presentation): 😀, not ❤ (which needs U+FE0F).
bool isEmojiPresentation(int codePoint) => _table[codePoint] >> 27 & 1 == 1;

/// Whether [codePoint] is an emoji modifier (Emoji_Modifier): the five
/// skin tones.
bool isEmojiModifier(int codePoint) => _table[codePoint] >> 28 & 1 == 1;

/// Whether an emoji modifier after [codePoint] changes it
/// (Emoji_Modifier_Base): 👍, not 😀.
bool isEmojiModifierBase(int codePoint) => _table[codePoint] >> 29 & 1 == 1;

/// Whether [codePoint] is Extended_Pictographic: an emoji or a symbol of
/// its kind, assigned or reserved for one.
bool isExtendedPictographic(int codePoint) => _table[codePoint] >> 30 & 1 == 1;

/// Whether [codePoint] is a mark (General_Category Mn, Mc or Me).
bool isMark(int codePoint) => switch (generalCategory(codePoint)) {
  GeneralCategory.nonspacingMark ||
  GeneralCategory.spacingMark ||
  GeneralCategory.enclosingMark => true,
  _ => false,
};

// Hangul syllables (The Unicode Standard, 3.12).
const int _sBase = 0xac00;
const int _lBase = 0x1100;
const int _vBase = 0x1161;
const int _tBase = 0x11a7;
const int _lCount = 19;
const int _vCount = 21;
const int _tCount = 28;
const int _nCount = _vCount * _tCount;
const int _sCount = _lCount * _nCount;

final class _Decompositions {
  new() {
    final bytes = base64.decode(data.decompositions);
    final view = ByteData.sublistView(bytes);
    final excluded = data.compositionExclusions.toSet();
    for (var i = 0; i < bytes.length; i += 12) {
      final c = view.getUint32(i, Endian.little);
      final a = view.getUint32(i + 4, Endian.little);
      final b = view.getUint32(i + 8, Endian.little);
      decompositions[c] = (a, b == 0 ? null : b);
      if (b != 0 && !excluded.contains(c)) compositions[(a, b)] = c;
    }
  }

  final Map<int, (int, int?)> decompositions = {};
  final Map<(int, int), int> compositions = {};
}

final _Decompositions _decompositions = _Decompositions();

/// [codePoint]'s canonical decomposition, one step of it (its first
/// code point and, if it has two, its second), or null where it has
/// none; a Hangul syllable as its leading and vowel jamo, or its LV
/// syllable and trailing jamo.
(int, int?)? canonicalDecomposition(int codePoint) {
  final s = codePoint - _sBase;
  if (s >= 0 && s < _sCount) {
    final t = s % _tCount;
    if (t != 0) return (codePoint - t, _tBase + t);
    return (_lBase + s ~/ _nCount, _vBase + (s % _nCount) ~/ _tCount);
  }
  return _decompositions.decompositions[codePoint];
}

/// The primary composite [first] and [second] compose to canonically,
/// or null (excluded compositions are none; Hangul jamo by the
/// algorithm).
int? canonicalComposition(int first, int second) {
  final l = first - _lBase;
  final v = second - _vBase;
  if (l >= 0 && l < _lCount && v >= 0 && v < _vCount) {
    return _sBase + (l * _vCount + v) * _tCount;
  }
  final s = first - _sBase;
  final t = second - _tBase;
  if (s >= 0 && s < _sCount && s % _tCount == 0 && t > 0 && t < _tCount) {
    return first + t;
  }
  return _decompositions.compositions[(first, second)];
}
