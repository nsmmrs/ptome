/// The Thai and Hangul shapers (HarfBuzz 14.6's `hb-ot-shaper-thai.cc`
/// and `hb-ot-shaper-hangul.cc`): Thai's and Lao's SARA AM decomposed,
/// its nikhahit moved before the above-base marks; Hangul's jamo composed
/// into the syllable a font has, or given their `ljmo`, `vjmo` and `tjmo`
/// forms, a tone mark moved before its syllable.
///
/// (Thai's fallback for fonts without Thai tables, by its presentation
/// forms in the private use area, is left out: fonts that set Thai have
/// the tables.)
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_typesetting/src/shaping/syllabic.dart';

/// The Thai shaper (Thai and Lao).
final class ThaiShaper extends Shaper {
  /// A Thai shaper.
  new();

  @override
  bool get fallbackPosition => false;

  static bool _isSaraAm(int u) => u & ~0x80 == 0x0e33;

  static bool _isAboveBaseMark(int u) {
    final c = u & ~0x80;
    return (c >= 0x0e34 && c <= 0x0e37) ||
        (c >= 0x0e47 && c <= 0x0e4e) ||
        c == 0x0e31 ||
        c == 0x0e3b;
  }

  @override
  void preprocessText(ShapeContext context) {
    final glyphs = context.glyphs;
    final out = <LayoutGlyph>[];
    for (final g in glyphs) {
      final u = g.char;
      if (!_isSaraAm(u)) {
        out.add(g);
        continue;
      }
      // SARA AM: NIKHAHIT and SARA AA, the NIKHAHIT moved back over the
      // above-base marks before it.
      final nikhahit = LayoutGlyph(0, g.cluster, mask: g.mask)
        ..char = u - 0x0e33 + 0x0e4d;
      setUnicodeProps(nikhahit);
      out.add(nikhahit);
      g.char = u - 1;
      setUnicodeProps(g);
      out.add(g);
      final end = out.length;
      var start = end - 2;
      while (start > 0 && _isAboveBaseMark(out[start - 1].char)) {
        start--;
      }
      if (start + 2 < end) {
        mergeClusters(out, start, end);
        final t = out.removeAt(end - 2);
        out.insert(start, t);
      }
      if (start > 0) mergeClusters(out, start - 1, end);
    }
    glyphs
      ..clear()
      ..addAll(out);
  }
}

// Hangul.
const int _lBase = 0x1100;
const int _vBase = 0x1161;
const int _tBase = 0x11a7;
const int _lCount = 19;
const int _vCount = 21;
const int _tCount = 28;
const int _sBase = 0xac00;
const int _nCount = _vCount * _tCount;
const int _sCount = _lCount * _nCount;

bool _isCombiningL(int u) => u >= _lBase && u < _lBase + _lCount;
bool _isCombiningV(int u) => u >= _vBase && u < _vBase + _vCount;
bool _isCombiningT(int u) => u > _tBase && u < _tBase + _tCount;
bool _isCombinedS(int u) => u >= _sBase && u < _sBase + _sCount;
bool _isL(int u) =>
    (u >= 0x1100 && u <= 0x115f) || (u >= 0xa960 && u <= 0xa97c);
bool _isV(int u) =>
    (u >= 0x1160 && u <= 0x11a7) || (u >= 0xd7b0 && u <= 0xd7c6);
bool _isT(int u) =>
    (u >= 0x11a8 && u <= 0x11ff) || (u >= 0xd7cb && u <= 0xd7fb);
bool _isTone(int u) => u == 0x302e || u == 0x302f;

/// The Hangul shaper.
final class HangulShaper extends Shaper {
  /// A Hangul shaper.
  new();

  static const List<String> _features = ['ljmo', 'vjmo', 'tjmo'];
  final List<int> _masks = List.filled(4, 0);
  int _caltMask = 0;
  late OpenTypeFont _font;

  @override
  void collectFeatures(PlanBuilder builder, String script) {
    _features.forEach(builder.addFeature);
  }

  @override
  void overrideFeatures(PlanBuilder builder) => builder.addFeature('calt');

  @override
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {
    _font = layout.font;
    for (final (i, tag) in _features.indexed) {
      _masks[i + 1] = plan.oneMaskOf(tag);
    }
    _caltMask = plan.oneMaskOf('calt');
  }

  @override
  NormalizationMode get normalization => NormalizationMode.none;

  @override
  ZeroWidthMarks get zeroWidthMarks => ZeroWidthMarks.none;

  bool _zeroWidth(int u) {
    final glyph = _font.glyphFor(u);
    return glyph != 0 && _font.advance(glyph) == 0;
  }

  LayoutGlyph _glyph(LayoutGlyph from, int char, {int feature = 0}) =>
      LayoutGlyph(0, from.cluster, mask: from.mask)
        ..char = char
        ..category = feature
        ..apply(setUnicodeProps);

  @override
  void preprocessText(ShapeContext context) {
    final input = context.glyphs;
    bool has(int u) => context.glyphFor(u) != 0;
    final out = <LayoutGlyph>[];
    var start = 0;
    var end = 0;
    var i = 0;
    while (i < input.length) {
      final g = input[i];
      final u = g.char;
      g.category = 0;
      if (_isTone(u)) {
        if (start < end && end == out.length) {
          out.add(g);
          i++;
          if (!_zeroWidth(u)) {
            mergeClusters(out, start, end + 1);
            final tone = out.removeAt(end);
            out.insert(start, tone);
          }
        } else if (has(0x25cc)) {
          final circle = _glyph(g, 0x25cc);
          if (!_zeroWidth(u)) {
            out.addAll([g, circle]);
          } else {
            out.addAll([circle, g]);
          }
          i++;
        } else {
          out.add(g);
          i++;
        }
        start = end = out.length;
        continue;
      }
      start = out.length;
      if (_isL(u) && i + 1 < input.length) {
        final l = u;
        final v = input[i + 1].char;
        if (_isV(v)) {
          var t = 0;
          var tIndex = 0;
          if (i + 2 < input.length) {
            t = input[i + 2].char;
            if (_isT(t)) {
              tIndex = t - _tBase;
            } else {
              t = 0;
            }
          }
          if (_isCombiningL(l) &&
              _isCombiningV(v) &&
              (t == 0 || _isCombiningT(t))) {
            final s =
                _sBase +
                (l - _lBase) * _nCount +
                (v - _vBase) * _tCount +
                tIndex;
            if (has(s)) {
              out.add(_glyph(g, s));
              i += t != 0 ? 3 : 2;
              end = start + 1;
              continue;
            }
          }
          out
            ..add(g..category = 1)
            ..add(input[i + 1]..category = 2);
          i += 2;
          if (t != 0) {
            out.add(input[i]..category = 3);
            i++;
            end = start + 3;
          } else {
            end = start + 2;
          }
          mergeClusters(out, start, end);
          continue;
        }
      } else if (_isCombinedS(u)) {
        final s = u;
        final hasGlyph = has(s);
        final lIndex = (s - _sBase) ~/ _nCount;
        final nIndex = (s - _sBase) % _nCount;
        final vIndex = nIndex ~/ _tCount;
        final tIndex = nIndex % _tCount;
        if (tIndex == 0 &&
            i + 1 < input.length &&
            _isCombiningT(input[i + 1].char)) {
          final newS = s + input[i + 1].char - _tBase;
          if (has(newS)) {
            out.add(_glyph(g, newS));
            i += 2;
            end = start + 1;
            continue;
          }
        }
        if (!hasGlyph ||
            (tIndex == 0 && i + 1 < input.length && _isT(input[i + 1].char))) {
          final decomposed = [
            _lBase + lIndex,
            _vBase + vIndex,
            if (tIndex != 0) _tBase + tIndex,
          ];
          if (decomposed.every(has)) {
            final pieces = [
              for (final (k, c) in decomposed.indexed)
                _glyph(g, c, feature: k + 1),
            ];
            out.addAll(pieces);
            i++;
            var length = pieces.length;
            if (hasGlyph && tIndex == 0) {
              // (The trailing jamo after the decomposed syllable.)
              out.add(input[i]..category = 3);
              i++;
              length++;
            }
            end = start + length;
            mergeClusters(out, start, end);
            continue;
          }
        }
        if (hasGlyph) end = start + 1;
      }
      out.add(g);
      i++;
    }
    input
      ..clear()
      ..addAll(out);
  }

  @override
  void setupMasks(ShapeContext context) {
    for (final g in context.glyphs) {
      g.mask |= _masks[g.category];
      final u = g.char;
      if (_isL(u) || _isV(u) || _isT(u)) g.mask &= ~_caltMask;
    }
  }
}

extension on LayoutGlyph {
  void apply(void Function(LayoutGlyph) f) => f(this);
}
