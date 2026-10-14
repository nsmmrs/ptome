/// East Asian line composition, from the W3C's "Requirements for Japanese
/// Text Layout" (JLREQ) and "Requirements for Chinese Text Layout"
/// (CLREQ):
///
/// - Punctuation squeezed: of two full-width punctuation marks in a row,
///   one set half wide (its blank half dropped, by the font's own `halt`
///   metrics): a closing mark (a closing bracket, a comma, a full stop)
///   before an opening or another closing one, the second of two opening
///   ones (JLREQ 3.1.4, CLREQ 3.1.6; OpenType's `chws`, for fonts that
///   lack the feature).
/// - A quarter em between a Han or kana character and a Latin letter or
///   digit beside it (JLREQ 3.2.2; CLREQ's "mixed text" spacing).
/// - Justification between characters: a line of text written without
///   spaces (Han, kana, Thai, Lao, Khmer, Myanmar) stretched by equal
///   space between its characters, as between its words (JLREQ 3.8).
///
/// Line-start and line-end prohibitions (kinsoku) are UAX #14's, which
/// keeps closing marks, small kana and the prolonged sound mark from a
/// line's start and opening marks from its end.
library;

import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/shaping.dart' show shapeInLanguage;
import 'package:plain_unicode/plain_unicode.dart'
    show GeneralCategory, generalCategory, isMark, lineBreakOffsets, scriptOf;

const Set<String> _cjk = {'Hani', 'Hira', 'Kana', 'Bopo'};
const Set<String> _spaceless = {..._cjk, 'Thai', 'Laoo', 'Khmr', 'Mymr'};

/// Full-width opening punctuation: brackets and quotation marks.
bool _isOpening(int c) => switch (c) {
  0x3008 || 0x300a || 0x300c || 0x300e || 0x3010 || 0x3014 => true,
  0x3016 || 0x3018 || 0x301a || 0x301d || 0xff08 || 0xff3b => true,
  0xff5b || 0xff5f => true,
  _ => false,
};

/// Full-width closing punctuation: brackets, quotation marks, commas and
/// full stops.
bool _isClosing(int c) => switch (c) {
  0x3001 || 0x3002 || 0x3009 || 0x300b || 0x300d || 0x300f => true,
  0x3011 || 0x3015 || 0x3017 || 0x3019 || 0x301b || 0x301e => true,
  0x301f || 0xff09 || 0xff0c || 0xff0e || 0xff3d || 0xff5d => true,
  0xff60 => true,
  _ => false,
};

bool _isPunctuation(int c) => _isOpening(c) || _isClosing(c);

/// Whether [c] is of a script written without spaces between words, or
/// full-width punctuation.
bool isSpaceless(int c) =>
    _spaceless.contains(scriptOf(c)) ||
    _isPunctuation(c) ||
    (c >= 0x3000 && c <= 0x303f) ||
    (c >= 0xff01 && c <= 0xff60);

/// Whether [c] is a Han, kana or bopomofo character.
bool isCjk(int c) => _cjk.contains(scriptOf(c));

/// Whether [c] is a letter or digit set with a quarter em beside Han or
/// kana: Latin, Greek or Cyrillic, or a digit.
bool isWestern(int c) =>
    generalCategory(c) == GeneralCategory.decimalNumber ||
    switch (scriptOf(c)) {
      'Latn' || 'Grek' || 'Cyrl' => !isMark(c),
      _ => false,
    };

/// Whether a quarter em goes between [before] and [after].
bool cjkWesternBoundary(int before, int after) =>
    (isCjk(before) && isWestern(after)) || (isWestern(before) && isCjk(after));

/// The first code point a glyph stands for, or null for none.
int? _first(ShapedGlyph glyph) =>
    glyph.text.isEmpty ? null : glyph.text.runes.first;

/// The last code point a glyph stands for, or null for none.
int? _last(ShapedGlyph glyph) =>
    glyph.text.isEmpty ? null : glyph.text.runes.last;

/// Whether glyph [i] of [glyphs] starts a character of its own (not a
/// mark, nor a glyph standing for no text).
bool _starts(List<ShapedGlyph> glyphs, int i) {
  final c = _first(glyphs[i]);
  return c != null && !isMark(c) && glyphs[i].advance != 0;
}

final Expando<Map<(int, String?), ShapedGlyph?>> _halfWidths = Expando();

/// [glyph] (of punctuation [c]) set half wide by [style]'s font's `halt`
/// (in the text's language, its own form's), or null where the font has
/// no half-width form for it.
ShapedGlyph? _half(TextStyle style, ShapedGlyph glyph, int c) {
  final font = style.font;
  if (font is! OpenTypeTextFont) return null;
  final cache = _halfWidths[font] ??= {};
  final half = cache.putIfAbsent((c, style.language), () {
    // (Shaped in full, as text with Han or kana is: punctuation alone
    // would take the simple path, without the positioning `halt` is.)
    List<ShapedGlyph> shape(Set<String> features) => shapeInLanguage(
      font.font,
      String.fromCharCode(c),
      language: style.language ?? '',
      kerning: style.kerning,
      ligatures: style.ligatures,
      features: features,
    );
    final full = shape(style.features);
    final halt = shape({...style.features, 'halt'});
    if (full.length != 1 || halt.length != 1) return null;
    if (halt.single.advance >= full.single.advance) return null;
    return halt.single;
  });
  if (half == null || half.id != glyph.id) return null;
  return glyph.copyWith(
    advance: half.advance,
    xOffset: glyph.xOffset + half.xOffset,
  );
}

/// How full-width punctuation is set, by region (JLREQ; CLREQ 2.1.2,
/// 6.3.2): the conventions differ by region more than by script.
enum PunctuationStyle {
  /// Japanese (JLREQ): marks in the corner, two in a row squeezed to an
  /// em and a half.
  japanese,

  /// Mainland China (`zh`, `zh-Hans`, `zh-CN`, `zh-SG`): marks in the
  /// corner, two in a row squeezed to an em and a half, a mark ending a
  /// line set half wide (GB/T 15834-2011 5.1.10).
  mainland,

  /// Hong Kong (`zh-HK`, `zh-MO`, `yue`): pause and stop marks centered
  /// and whole; brackets squeezed.
  hongKong,

  /// Taiwan (`zh-TW`, `zh-Hant`): marks centered, none squeezed.
  taiwan;

  /// The style of [language] (BCP 47): Japanese's but for Chinese.
  static PunctuationStyle of(String? language) {
    final subtags = (language ?? '').toLowerCase().split(RegExp('[-_]'));
    final primary = subtags.first;
    if (primary == 'yue') return hongKong;
    if (primary != 'zh' && primary != 'cmn') return japanese;
    if (subtags.contains('hk') || subtags.contains('mo')) return hongKong;
    if (subtags.contains('tw')) return taiwan;
    if (subtags.contains('hant')) return taiwan;
    return mainland;
  }
}

/// Whether [c] is a bracket or a quotation mark (not a pause or stop).
bool _isBracket(int c) =>
    _isPunctuation(c) && !const {0x3001, 0x3002, 0xff0c, 0xff0e}.contains(c);

/// [glyphs] (a left-to-right run's, in [style]) with their punctuation
/// squeezed as the text's region has it ([PunctuationStyle]) and a
/// quarter em between Han or kana and Latin letters or digits.
List<ShapedGlyph> eastAsianSpacing(List<ShapedGlyph> glyphs, TextStyle style) {
  if (!glyphs.any((g) => g.text.runes.any(isSpaceless))) return glyphs;
  final punctuation = PunctuationStyle.of(style.language);
  final out = [...glyphs];
  const quarter = 250.0;
  int? previousStart;
  for (var i = 0; i < out.length; i++) {
    if (!_starts(out, i)) continue;
    final p = previousStart;
    previousStart = i;
    if (p == null) continue;
    final a = _last(out[p])!;
    final b = _first(out[i])!;
    // Punctuation squeezed (Hong Kong's brackets alone, none in Taiwan).
    final squeezes = switch (punctuation) {
      PunctuationStyle.taiwan => false,
      PunctuationStyle.hongKong => _isBracket(a) && _isBracket(b),
      _ => true,
    };
    if (squeezes && _isClosing(a) && _isPunctuation(b)) {
      if (_half(style, out[p], a) case final half?) out[p] = half;
    } else if (squeezes && _isOpening(a) && _isOpening(b)) {
      if (_half(style, out[i], b) case final half?) out[i] = half;
    }
    // A quarter em between Han or kana and Latin, after the glyphs
    // before (their last, a mark's base's or the mark's).
    if (cjkWesternBoundary(a, b)) {
      final g = out[i - 1];
      out[i - 1] = g.copyWith(kerning: g.kerning + quarter);
    }
  }
  return out;
}

/// [glyphs] (a line's last run, in [style]) with a full-width mark ending
/// the line set half wide where the text's region does so (mainland
/// China: GB/T 15834-2011 5.1.10, CLREQ 6.3.2.3).
List<ShapedGlyph> eastAsianLineEnd(List<ShapedGlyph> glyphs, TextStyle style) {
  if (PunctuationStyle.of(style.language) != PunctuationStyle.mainland) {
    return glyphs;
  }
  for (var i = glyphs.length - 1; i >= 0; i--) {
    if (!_starts(glyphs, i)) continue;
    final c = _first(glyphs[i])!;
    if (!_isClosing(c)) return glyphs;
    final half = _half(style, glyphs[i], c);
    if (half == null) return glyphs;
    return [...glyphs]..[i] = half;
  }
  return glyphs;
}

/// The places in [glyphs] (a left-to-right run's) a justified line
/// stretches between characters written without spaces: the indexes of
/// the glyphs the space goes after. Between any two Han or kana
/// characters or full-width punctuation; in Thai, Lao, Khmer and Myanmar
/// between words alone (where the line may break: its dictionaries'
/// boundaries).
List<int> interCharacterGaps(List<ShapedGlyph> glyphs) {
  final text = glyphs.map((g) => g.text).join();
  final offsets = lineBreakOffsets(text);
  final words = {for (var i = 0; i < offsets.length; i++) offsets.offsetAt(i)};
  final gaps = <int>[];
  int? previousStart;
  var offset = 0;
  for (var i = 0; i < glyphs.length; i++) {
    final at = offset;
    offset += glyphs[i].text.length;
    if (!_starts(glyphs, i)) continue;
    final p = previousStart;
    previousStart = i;
    if (p == null) continue;
    final a = _last(glyphs[p])!;
    final b = _first(glyphs[i])!;
    if (!isSpaceless(a) || !isSpaceless(b)) continue;
    final ideographic =
        (isCjk(a) || _isFullWidth(a)) && (isCjk(b) || _isFullWidth(b));
    if (ideographic || words.contains(at)) gaps.add(i - 1);
  }
  return gaps;
}

bool _isFullWidth(int c) =>
    _isPunctuation(c) ||
    (c >= 0x3000 && c <= 0x303f) ||
    (c >= 0xff01 && c <= 0xff60);

/// [glyphs] with [extra] (1000ths of the em) after each of [gaps].
List<ShapedGlyph> widenGaps(
  List<ShapedGlyph> glyphs,
  List<int> gaps,
  double extra,
) {
  if (gaps.isEmpty || extra == 0) return glyphs;
  final out = [...glyphs];
  for (final i in gaps) {
    final g = out[i];
    out[i] = g.copyWith(kerning: g.kerning + extra);
  }
  return out;
}
