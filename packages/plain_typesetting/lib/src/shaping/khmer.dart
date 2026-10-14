/// The Khmer shaper (HarfBuzz 14.6's `hb-ot-shaper-khmer.cc`): syllables
/// found by its grammar, a Coeng with Ro moved before its base as a
/// pre-base form, a left vowel moved to the start, the basic features
/// within the syllable, split vowels decomposed.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/indic_data.g.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_typesetting/src/shaping/syllabic.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// The Khmer categories (HarfBuzz's machine's numbers).
abstract final class _K {
  static const int c = 1;
  static const int v = 2;
  static const int h = 4;
  static const int zwnj = 5;
  static const int zwj = 6;
  static const int placeholder = 10;
  static const int dottedCircle = 11;
  static const int ra = 15;
  static const int vAbv = 20;
  static const int vBlw = 21;
  static const int vPre = 22;
  static const int vPst = 23;
  static const int robatic = 25;
  static const int xGroup = 26;
  static const int yGroup = 27;
}

const int _consonantSyllable = 0;
const int _brokenCluster = 1;
const int _nonKhmerCluster = 2;

/// The Khmer grammar (HarfBuzz's `hb-ot-shaper-khmer-machine.rl`).
final SyllableGrammar _grammar = () {
  Pattern s(List<int> cats) => sym(cats);
  final c = s([_K.c, _K.ra, _K.v]);
  final cn = c & (s([_K.zwj, _K.zwnj]).opt & s([_K.robatic])).opt;
  final joiner = s([_K.zwj, _K.zwnj]);
  final xgroup = (joiner.star & s([_K.xGroup])).star;
  final ygroup = s([_K.yGroup]).star;
  final matraGroup =
      s([_K.vPre]).opt &
      xgroup &
      s([_K.vBlw]).opt &
      xgroup &
      (joiner.opt & s([_K.vAbv])).opt &
      xgroup &
      s([_K.vPst]).opt;
  final syllableTail =
      xgroup & matraGroup & xgroup & (s([_K.h]) & c).opt & ygroup;
  final brokenCluster =
      s([_K.robatic]).opt & (s([_K.h]) & cn).star & (s([_K.h]) | syllableTail);
  final consonantSyllable =
      (cn | s([_K.placeholder, _K.dottedCircle])) & brokenCluster;
  return SyllableGrammar([
    (consonantSyllable, _consonantSyllable),
    (brokenCluster, _brokenCluster),
    (anyGlyph, _nonKhmerCluster),
  ]);
}();

const List<(String, int)> _features = [
  ('pref', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('blwf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('abvf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('pstf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('cfar', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('pres', FeatureFlags.globalManualJoiners),
  ('abvs', FeatureFlags.globalManualJoiners),
  ('blws', FeatureFlags.globalManualJoiners),
  ('psts', FeatureFlags.globalManualJoiners),
];

const int _pref = 0;
const int _blwf = 1;
const int _abvf = 2;
const int _pstf = 3;
const int _cfar = 4;
const int _basicFeatures = 5;

/// The Khmer shaper.
final class KhmerShaper extends Shaper {
  /// A Khmer shaper.
  new();

  final List<int> _masks = List.filled(_features.length, 0);

  @override
  void collectFeatures(PlanBuilder builder, String script) {
    builder
      ..addGsubPause(_setupSyllables)
      ..addGsubPause(_reorder)
      ..enableFeature('locl', flags: FeatureFlags.perSyllable)
      ..enableFeature('ccmp', flags: FeatureFlags.perSyllable);
    for (var i = 0; i < _basicFeatures; i++) {
      final (tag, flags) = _features[i];
      builder.addFeature(tag, flags: flags);
    }
    builder.addGsubPause();
    for (var i = _basicFeatures; i < _features.length; i++) {
      final (tag, flags) = _features[i];
      builder.addFeature(tag, flags: flags);
    }
  }

  @override
  void overrideFeatures(PlanBuilder builder) {
    builder
      ..enableFeature('clig')
      ..disableFeature('liga');
  }

  @override
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {
    for (final (i, (tag, flags)) in _features.indexed) {
      _masks[i] = flags & FeatureFlags.global != 0 ? 0 : plan.oneMaskOf(tag);
    }
  }

  @override
  NormalizationMode get normalization =>
      NormalizationMode.composedDiacriticsNoShortCircuit;

  @override
  (int, int)? decompose(int ab) => switch (ab) {
    0x17be || 0x17bf || 0x17c0 || 0x17c4 || 0x17c5 => (0x17c1, ab),
    _ => unicodeDecompose(ab),
  };

  @override
  int? compose(int a, int b) => isMark(a) ? null : unicodeCompose(a, b);

  @override
  ZeroWidthMarks get zeroWidthMarks => ZeroWidthMarks.none;

  @override
  bool get fallbackPosition => false;

  @override
  void setupMasks(ShapeContext context) {
    for (final g in context.glyphs) {
      g.category =
          rangeValue(indicCategoryRanges, g.char, indicCategoryRangesDefault) &
          0xff;
    }
  }

  void _setupSyllables(ShapeState state) {
    _grammar.findSyllables(
      state.glyphs,
      (g) => g.category,
      broken: _brokenCluster,
    );
  }

  void _reorder(ShapeState state) {
    final glyphs = state.glyphs;
    insertDottedCircles(
      glyphs,
      state.glyphFor,
      broken: _brokenCluster,
      category: _K.dottedCircle,
    );
    for (final (start, end) in syllables(glyphs).toList()) {
      switch (glyphs[start].syllable & 0x0f) {
        case _consonantSyllable || _brokenCluster:
          _reorderConsonantSyllable(glyphs, start, end);
      }
    }
  }

  void _reorderConsonantSyllable(List<LayoutGlyph> info, int start, int end) {
    final postBase = _masks[_blwf] | _masks[_abvf] | _masks[_pstf];
    for (var i = start + 1; i < end; i++) {
      info[i].mask |= postBase;
    }
    var coengs = 0;
    for (var i = start + 1; i < end; i++) {
      if (info[i].category == _K.h && coengs <= 2 && i + 1 < end) {
        coengs++;
        if (info[i + 1].category == _K.ra) {
          // Coeng and Ro: a pre-base form, moved to the start.
          info[i].mask |= _masks[_pref];
          info[i + 1].mask |= _masks[_pref];
          mergeClusters(info, start, i + 2);
          final coeng = info[i];
          final ro = info[i + 1];
          info
            ..removeRange(i, i + 2)
            ..insertAll(start, [coeng, ro]);
          if (_masks[_cfar] != 0) {
            for (var j = i + 2; j < end; j++) {
              info[j].mask |= _masks[_cfar];
            }
          }
          coengs = 2;
        }
      } else if (info[i].category == _K.vPre) {
        // A left vowel piece, moved to the start.
        mergeClusters(info, start, i + 1);
        final t = info.removeAt(i);
        info.insert(start, t);
      }
    }
  }
}
