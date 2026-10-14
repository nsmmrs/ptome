/// The Myanmar shaper (HarfBuzz 14.6's `hb-ot-shaper-myanmar.cc`), for
/// fonts of the `mym2` script tag: syllables found by its grammar, kinzi,
/// the medial Ra and the left vowel reordered before the base, the basic
/// features one at a time within the syllable.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/indic_data.g.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_typesetting/src/shaping/syllabic.dart';

/// The Myanmar categories (HarfBuzz's machine's numbers).
abstract final class _M {
  static const int c = 1;
  static const int iv = 2;
  static const int db = 3;
  static const int h = 4;
  static const int zwnj = 5;
  static const int zwj = 6;
  static const int sm = 8;
  static const int gb = 10;
  static const int dottedCircle = 11;
  static const int a = 9;
  static const int ra = 15;
  static const int cs = 18;
  static const int smPst = 57;
  static const int vAbv = 20;
  static const int vBlw = 21;
  static const int vPre = 22;
  static const int vPst = 23;
  static const int as = 32;
  static const int mh = 35;
  static const int mr = 36;
  static const int mw = 37;
  static const int my = 38;
  static const int pt = 39;
  static const int vs = 40;
  static const int ml = 41;
}

// Positions (as the Indic shaper numbers them).
const int _preM = 2;
const int _preC = 3;
const int _baseC = 4;
const int _afterMain = 5;
const int _beforeSub = 7;
const int _belowC = 8;
const int _afterSub = 9;

const int _consonantSyllable = 0;
const int _brokenCluster = 1;
const int _nonMyanmarCluster = 2;

/// The Myanmar grammar (HarfBuzz's `hb-ot-shaper-myanmar-machine.rl`).
final SyllableGrammar _grammar = () {
  Pattern s(List<int> cats) => sym(cats);
  Pattern star(int c) => s([c]).star;
  Pattern opt(int c) => s([c]).opt;
  final j = s([_M.zwj, _M.zwnj]);
  final k = s([_M.ra]) & s([_M.as]) & s([_M.h]);
  final sm = s([_M.sm, _M.smPst]);
  final c = s([_M.c, _M.ra]);
  final mediaGroup =
      opt(_M.my) &
      opt(_M.as) &
      opt(_M.mr) &
      (((s([_M.mw]) & opt(_M.mh) & opt(_M.ml)) |
                  (s([_M.mh]) & opt(_M.ml)) |
                  s([_M.ml])) &
              opt(_M.as))
          .opt;
  final mainVowelGroup =
      (s([_M.vPre]) & opt(_M.vs)).star &
      star(_M.vAbv) &
      star(_M.vBlw) &
      star(_M.a) &
      (s([_M.db]) & opt(_M.as)).opt;
  final postVowelGroup =
      s([_M.vPst]) &
      opt(_M.mh) &
      opt(_M.ml) &
      star(_M.as) &
      star(_M.vAbv) &
      star(_M.a) &
      (s([_M.db]) & opt(_M.as)).opt;
  final toneGroup = sm | (s([_M.pt]) & star(_M.a) & opt(_M.db) & opt(_M.as));
  final complexSyllableTail =
      star(_M.as) &
      mediaGroup &
      mainVowelGroup &
      postVowelGroup.star &
      toneGroup.star &
      j.opt;
  final syllableTail =
      (s([_M.h]) & (c | s([_M.iv])) & opt(_M.vs)).star &
      (s([_M.h]) | complexSyllableTail);
  final consonantSyllable =
      (k | s([_M.cs])).opt &
      (c | s([_M.iv, _M.gb, _M.dottedCircle])) &
      opt(_M.vs) &
      syllableTail;
  final brokenCluster = k.opt & opt(_M.vs) & syllableTail;
  return SyllableGrammar([
    (consonantSyllable, _consonantSyllable),
    (j | s([_M.smPst]), _nonMyanmarCluster),
    (brokenCluster, _brokenCluster),
    (anyGlyph, _nonMyanmarCluster),
  ]);
}();

/// The Myanmar shaper.
final class MyanmarShaper extends Shaper {
  /// A Myanmar shaper.
  new();

  @override
  void collectFeatures(PlanBuilder builder, String script) {
    builder
      ..addGsubPause(_setupSyllables)
      ..enableFeature('locl', flags: FeatureFlags.perSyllable)
      ..enableFeature('ccmp', flags: FeatureFlags.perSyllable)
      ..addGsubPause(_reorder);
    for (final tag in const ['rphf', 'pref', 'blwf', 'pstf']) {
      builder
        ..enableFeature(
          tag,
          flags: FeatureFlags.manualZwj | FeatureFlags.perSyllable,
        )
        ..addGsubPause();
    }
    builder.addGsubPause();
    for (final tag in const ['pres', 'abvs', 'blws', 'psts']) {
      builder.enableFeature(tag, flags: FeatureFlags.manualZwj);
    }
  }

  @override
  NormalizationMode get normalization =>
      NormalizationMode.composedDiacriticsNoShortCircuit;

  @override
  ZeroWidthMarks get zeroWidthMarks => ZeroWidthMarks.byGdefEarly;

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
      category: _M.dottedCircle,
    );
    for (final (start, end) in syllables(glyphs).toList()) {
      switch (glyphs[start].syllable & 0x0f) {
        case _consonantSyllable || _brokenCluster:
          _reorderConsonantSyllable(glyphs, start, end);
      }
    }
  }

  static bool _isConsonant(LayoutGlyph g) =>
      !g.isLigated &&
      const {
        _M.c,
        _M.cs,
        _M.ra,
        _M.iv,
        _M.gb,
        _M.dottedCircle,
      }.contains(g.category);

  static void _reorderConsonantSyllable(
    List<LayoutGlyph> info,
    int start,
    int end,
  ) {
    var base = end;
    var hasReph = false;
    var limit = start;
    if (start + 3 <= end &&
        info[start].category == _M.ra &&
        info[start + 1].category == _M.as &&
        info[start + 2].category == _M.h) {
      limit += 3;
      base = start;
      hasReph = true;
    }
    if (!hasReph) base = limit;
    for (var i = limit; i < end; i++) {
      if (_isConsonant(info[i])) {
        base = i;
        break;
      }
    }

    var i = start;
    for (; i < start + (hasReph ? 3 : 0); i++) {
      info[i].position = _afterMain;
    }
    for (; i < base; i++) {
      info[i].position = _preC;
    }
    if (i < end) {
      info[i].position = _baseC;
      i++;
    }
    var pos = _afterMain;
    for (; i < end; i++) {
      final c = info[i].category;
      if (c == _M.mr) {
        info[i].position = _preC;
      } else if (c == _M.vPre) {
        info[i].position = _preM;
      } else if (c == _M.vs) {
        info[i].position = info[i - 1].position;
      } else if (pos == _afterMain && c == _M.vBlw) {
        pos = _belowC;
        info[i].position = pos;
      } else if (pos == _belowC && c == _M.a) {
        info[i].position = _beforeSub;
      } else if (pos == _belowC && c == _M.vBlw) {
        info[i].position = pos;
      } else if (pos == _belowC && c != _M.a) {
        pos = _afterSub;
        info[i].position = pos;
      } else {
        info[i].position = pos;
      }
    }

    // A stable sort by position, the clusters of what moves merged.
    for (var k = start + 1; k < end; k++) {
      var j = k;
      while (j > start && info[j - 1].position > info[k].position) {
        j--;
      }
      if (j == k) continue;
      mergeClusters(info, j, k + 1);
      final t = info.removeAt(k);
      info.insert(j, t);
    }

    // A left-matra sequence flipped.
    var firstLeftMatra = end;
    var lastLeftMatra = end;
    for (var k = start; k < end; k++) {
      if (info[k].position == _preM) {
        if (firstLeftMatra == end) firstLeftMatra = k;
        lastLeftMatra = k;
      }
    }
    if (firstLeftMatra < lastLeftMatra) {
      _reverse(info, firstLeftMatra, lastLeftMatra + 1);
      var k = firstLeftMatra;
      for (var j = k; j <= lastLeftMatra; j++) {
        if (info[j].category == _M.vPre) {
          _reverse(info, k, j + 1);
          k = j + 1;
        }
      }
    }
  }

  static void _reverse(List<LayoutGlyph> glyphs, int start, int end) {
    final reversed = glyphs.sublist(start, end).reversed.toList();
    glyphs.setRange(start, end, reversed);
  }
}
