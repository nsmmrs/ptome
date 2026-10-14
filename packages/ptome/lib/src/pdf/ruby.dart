/// Ruby in the PDF (furigana, zhuyin): a base with its reading, as the
/// W3C's "Requirements for Japanese Text Layout" (JLREQ 3.3) and "Chinese
/// Layout" (CLREQ, Bopomofo) have it.
///
/// A reading is half the base's size and rests on the base's ascender.
/// A reading shorter than its base is spread over it, a kana reading's
/// characters a gap apart and half a gap from each end, but no more than a
/// reading character's width from them (JIS X 4051; JLREQ 3.3.5, 3.3.6);
/// a reading longer than its base hangs over the characters beside it
/// where they are kana, a mark's blank half or a dot (up to a reading
/// character's width, never over a Han character: JLREQ 3.3.8), the rest
/// of its length made up by spreading the base's characters, half a gap
/// at each end (3.3.6). At a line's start or end the reading reaches no
/// further than the line (3.3.9: the engine gives it back the room).
/// Bopomofo (zhuyin) in horizontal text stands in a column at the right
/// of its character, three tenths of its size, the column half its width,
/// centered on it, a tone mark at the right of the last symbol's top, the
/// neutral tone above the symbols (CLREQ).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:ptome/src/pdf/fonts.dart';

/// A ruby annotation in a line of text: [pairs] of base and reading,
/// laid out in the text's face and size when the line is ([at]).
final class InlineRuby implements Graphic {
  /// Ruby of [pairs] (one for group ruby, one a character for mono
  /// ruby), copied as [base].
  new(this.pairs, {required this.base});

  /// Each part of the base and its reading.
  final List<(String, String)> pairs;

  /// The base, the text a reader copies.
  final String base;

  final Map<(FontFace, double, double, double, bool), RubyBox> _boxes = {};

  /// The ruby laid out in [face] at [size] points, its reading allowed to
  /// hang [before] and [after] points over the characters beside it
  /// ([rubyOverhang]); Bopomofo in a column at its right where [zhuyin].
  RubyBox at(
    FontFace face,
    double size, {
    double before = 0,
    double after = 0,
    bool zhuyin = false,
  }) => _boxes[(face, size, before, after, zhuyin)] ??= RubyBox._(
    this,
    face,
    size,
    before: before,
    after: after,
    zhuyin: zhuyin,
  );

  @override
  double get intrinsicWidth => 0;

  @override
  double get intrinsicHeight => 0;

  @override
  void paint(Canvas canvas, Rect rect) {}
}

/// Whether [c] is a Han character, kana or Bopomofo (a reading of them is
/// spread over a longer base, a base of them spread under a longer one).
bool _isCjk(int c) =>
    (c >= 0x3040 && c <= 0x30FF) ||
    (c >= 0x3100 && c <= 0x312F) ||
    (c >= 0x31A0 && c <= 0x31FF) ||
    (c >= 0x3400 && c <= 0x9FFF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFF66 && c <= 0xFF9F) ||
    (c >= 0x20000 && c <= 0x3FFFF);

/// The tone marks of Bopomofo set at the right of the last symbol
/// (CLREQ): Mandarin's second, third and fourth tones, the Taiwanese
/// dialects' and the checked tones.
const Set<int> _tones = {
  0x02CA, 0x02C7, 0x02CB, 0x02EA, 0x02EB, 0x31B4, 0x31B5, 0x31B6, 0x31B7, //
};

/// Mandarin's neutral tone, set above the symbols.
const int _neutralTone = 0x02D9;

/// Whether [reading] is Bopomofo (its symbols and tone marks).
bool isBopomofo(String reading) =>
    reading.isNotEmpty &&
    reading.runes.every(
      (c) =>
          (c >= 0x3105 && c <= 0x312F) ||
          (c >= 0x31A0 && c <= 0x31BF) ||
          _tones.contains(c) ||
          c == _neutralTone,
    );

/// Closing brackets (JLREQ's cl-02), full stops (cl-06) and commas
/// (cl-07): a reading may hang over their blank half after them.
const Set<int> _closing = {
  0x3001, 0x3002, 0xFF0C, 0xFF0E, 0x300D, 0x300F, 0xFF09, 0x3015, 0xFF3D, //
  0xFF5D, 0x3009, 0x300B, 0x3011, 0x3019, 0x3017, 0x2019, 0x201D, 0xFF60,
  0x00BB, 0x301F,
};

/// Opening brackets (cl-01): a reading may hang over their blank half
/// before them.
const Set<int> _opening = {
  0x300C, 0x300E, 0xFF08, 0x3014, 0xFF3B, 0xFF5B, 0x3008, 0x300A, 0x3010, //
  0x3018, 0x3016, 0x2018, 0x201C, 0xFF5F, 0x00AB, 0x301D,
};

/// How far a reading may hang over [c], the character beside its base
/// ([before] it, or after it), in a text of [size] points (JLREQ 3.3.8):
/// a reading character's width (half [size]) over kana, the prolonged
/// sound mark, small kana, dots and the inseparable marks, and over the
/// blank half of a closing bracket, full stop or comma before it or of an
/// opening bracket after it; nothing over a Han character or anything
/// else.
double rubyOverhang(int? c, {required bool before, required double size}) {
  if (c == null) return 0;
  final em = size / 2;
  // (Hiragana, katakana, the prolonged sound mark, small kana and the
  // middle dot; half-width katakana.)
  if ((c >= 0x3041 && c <= 0x30FF) ||
      (c >= 0x31F0 && c <= 0x31FF) ||
      (c >= 0xFF66 && c <= 0xFF9F)) {
    return em;
  }
  // (Dots, cl-05; inseparable marks, cl-08.)
  const dots = {0xFF1A, 0xFF1B, 0x2014, 0x2025, 0x2026, 0x3033, 0x3034, 0x3035};
  if (dots.contains(c)) return em;
  if (before ? _closing.contains(c) : _opening.contains(c)) return em;
  return 0;
}

/// Ruby laid out: its [width] in the line, how far its reading reaches
/// before its start ([startOverhang]) and after its end ([endOverhang])
/// over the characters beside it, how far it reaches above the baseline
/// ([ascent]) and below ([descent]).
final class RubyBox {
  new _(
    this.ruby,
    this.face,
    this.size, {
    required double before,
    required double after,
    required bool zhuyin,
  }) {
    final readingSize = size / 2;
    _readingBaseline = face.ascenderAt(size) + face.descenderAt(readingSize);
    var ascent = face.ascenderAt(size);
    var descent = face.descenderAt(size);
    var x = 0.0;
    final pairs = ruby.pairs;
    for (final (k, (base, reading)) in pairs.indexed) {
      if (zhuyin && isBopomofo(reading)) {
        final (width, top, bottom) = _zhuyin(base, reading, x);
        ascent = math.max(ascent, top);
        descent = math.max(descent, -bottom);
        x += width;
        continue;
      }
      ascent = math.max(
        ascent,
        _readingBaseline + face.ascenderAt(readingSize),
      );
      final baseWidth = face.widthOf(base, size);
      final readingWidth = face.widthOf(reading, readingSize);
      final readingChars = [
        for (final c in reading.runes) String.fromCharCode(c),
      ];
      if (readingWidth <= baseWidth) {
        // The base solid, the reading spread over it (a kana reading of
        // more than one character), else centered.
        _text(base, size, x, 0);
        if (readingChars.length > 1 && reading.runes.every(_isCjk)) {
          final n = readingChars.length;
          var gap = (baseWidth - readingWidth) / n;
          var lead = gap / 2;
          if (lead > readingSize) {
            lead = readingSize;
            gap = (baseWidth - readingWidth - 2 * lead) / (n - 1);
          }
          var at = x + lead;
          for (final c in readingChars) {
            _text(c, readingSize, at, _readingBaseline);
            at += face.widthOf(c, readingSize) + gap;
          }
        } else {
          _text(
            reading,
            readingSize,
            x + (baseWidth - readingWidth) / 2,
            _readingBaseline,
          );
        }
        x += baseWidth;
        continue;
      }
      // The reading solid, hanging over what is beside the ruby as far as
      // it may (half its excess each side at most), the rest of its
      // length made up between the base's characters, half as much at
      // each end.
      final excess = readingWidth - baseWidth;
      final hangBefore = k == 0 ? math.min(excess / 2, before) : 0.0;
      final hangAfter = k == pairs.length - 1
          ? math.min(excess / 2, after)
          : 0.0;
      final spread = excess - hangBefore - hangAfter;
      if (k == 0) startOverhang = hangBefore;
      if (k == pairs.length - 1) endOverhang = hangAfter;
      final baseChars = [for (final c in base.runes) String.fromCharCode(c)];
      if (baseChars.length == 1 || !base.runes.every(_isCjk)) {
        _text(base, size, x + spread / 2, 0);
      } else {
        final gap = spread / baseChars.length;
        var at = x + gap / 2;
        for (final c in baseChars) {
          _text(c, size, at, 0);
          at += face.widthOf(c, size) + gap;
        }
      }
      _text(reading, readingSize, x - hangBefore, _readingBaseline);
      x += baseWidth + spread;
    }
    width = x;
    this.ascent = ascent;
    this.descent = descent;
  }

  /// The ruby.
  final InlineRuby ruby;

  /// The face it is set in.
  final FontFace face;

  /// The base's size.
  final double size;

  /// What is drawn: each piece of text, its size, where it starts and its
  /// baseline above the ruby's.
  final List<(String, double, double, double)> _pieces = [];

  /// The width.
  late final double width;

  /// How far the reading reaches before the start, over what is beside it.
  double startOverhang = 0;

  /// How far the reading reaches after the end, over what is beside it.
  double endOverhang = 0;

  /// How far it reaches above the baseline.
  late final double ascent;

  /// How far it reaches below the baseline.
  late final double descent;

  /// How far above the baseline the readings' baseline is.
  late final double _readingBaseline;

  /// What is drawn: each piece of text, its size, where it starts and its
  /// baseline above the ruby's.
  @visibleForTesting
  List<(String, double, double, double)> get pieces =>
      List.unmodifiable(_pieces);

  void _text(String text, double size, double x, double y) =>
      _pieces.add((text, size, x, y));

  /// [base] with its Bopomofo [reading] in a column at its right, from
  /// [x]: its width, and how far the column reaches above and below the
  /// baseline (CLREQ: the symbols three tenths of the base's size, the
  /// column half its width, centered on the character; a tone mark at the
  /// right of the last symbol, half of it above that symbol's top; the
  /// neutral tone above them, a tenth of the size high).
  (double, double, double) _zhuyin(String base, String reading, double x) {
    final baseWidth = face.widthOf(base, size);
    _text(base, size, x, 0);
    final symbolSize = size * 0.3;
    final symbols = [
      for (final c in reading.runes)
        if (!_tones.contains(c) && c != _neutralTone) String.fromCharCode(c),
    ];
    final tone = [
      for (final c in reading.runes)
        if (_tones.contains(c)) String.fromCharCode(c),
    ].firstOrNull;
    final neutral = reading.runes.contains(_neutralTone);
    final neutralHeight = neutral ? size * 0.1 : 0.0;
    final height = neutralHeight + symbols.length * symbolSize;
    // (Centered on the character's em box.)
    final middle = (face.ascenderAt(size) - face.descenderAt(size)) / 2;
    final top = middle + height / 2;
    final column = x + baseWidth;
    // (A glyph whose em box's top is at [boxTop], its baseline.)
    double baselineIn(double boxTop) =>
        boxTop - symbolSize + face.descenderAt(symbolSize);
    double centered(String c) =>
        column + (symbolSize - face.widthOf(c, symbolSize)) / 2;
    if (neutral) {
      final dot = String.fromCharCode(_neutralTone);
      _text(
        dot,
        symbolSize,
        centered(dot),
        baselineIn(top + (symbolSize - neutralHeight) / 2),
      );
    }
    var boxTop = top - neutralHeight;
    for (final symbol in symbols) {
      _text(symbol, symbolSize, centered(symbol), baselineIn(boxTop));
      boxTop -= symbolSize;
    }
    if (tone != null) {
      // (Its middle at the top of the last symbol.)
      final lastTop = boxTop + symbolSize;
      _text(
        tone,
        symbolSize,
        column + symbolSize,
        baselineIn(lastTop + symbolSize / 2),
      );
    }
    return (baseWidth + size / 2, top, top - height);
  }

  /// Draws the ruby with its baseline at [baseline], starting at [left],
  /// copied as its base.
  void paintAt(Canvas canvas, double left, double baseline, {Color? color}) {
    canvas
      ..save()
      ..beginMarkedContent('Span', actualText: ruby.base);
    if (color != null) canvas.setFillColor(color);
    for (final (text, size, x, y) in _pieces) {
      final style = TextStyle(face.pdf, size);
      canvas.glyphs(style.shape(text), left + x, baseline + y, style, text: '');
    }
    canvas
      ..endMarkedContent()
      ..restore();
  }
}

/// Ruby drawn by the engine as an inline image, laid out ([box]), in
/// [color].
final class EngineRuby implements Graphic {
  /// [box] in [color].
  const new(this.box, this.color);

  /// The ruby laid out.
  final RubyBox box;

  /// The color, if not the text's default.
  final Color? color;

  @override
  double get intrinsicWidth => box.width;

  @override
  double get intrinsicHeight => box.ascent + box.descent;

  @override
  void paint(Canvas canvas, Rect rect) {
    box.paintAt(canvas, rect.left, rect.bottom + box.descent, color: color);
  }
}
