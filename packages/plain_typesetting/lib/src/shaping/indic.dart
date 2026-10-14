/// The Indic shaper (HarfBuzz 14.6's `hb-ot-shaper-indic.cc`), for
/// Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada
/// and Malayalam under their old (`deva`) and second (`dev2`) script
/// tags: syllables found by HarfBuzz's grammar, the base consonant, the
/// pre-base matras, reph and pre-base forms reordered before and after
/// the basic features, each feature applied within its syllable.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/indic_data.g.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_typesetting/src/shaping/syllabic.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// The Indic categories (HarfBuzz's `I_Cat`, its machine's numbers).
abstract final class _Cat {
  static const int c = 1;
  static const int v = 2;
  static const int n = 3;
  static const int h = 4;
  static const int zwnj = 5;
  static const int zwj = 6;
  static const int m = 7;
  static const int sm = 8;
  static const int a = 9;
  static const int placeholder = 10;
  static const int dottedCircle = 11;
  static const int rs = 12;
  static const int mPst = 13;
  static const int repha = 14;
  static const int ra = 15;
  static const int cm = 16;
  static const int symbol = 17;
  static const int cs = 18;
  static const int smPst = 57;
}

/// The visual positions in a syllable, left to right.
abstract final class _Pos {
  static const int start = 0;
  static const int raToBecomeReph = 1;
  static const int preM = 2;
  static const int preC = 3;
  static const int baseC = 4;
  static const int afterMain = 5;
  static const int belowC = 8;
  static const int postC = 11;
  static const int afterPost = 12;
  static const int smvd = 13;
  static const int end = 14;
}

/// The syllable types.
abstract final class _Syllable {
  static const int consonant = 0;
  static const int vowel = 1;
  static const int standalone = 2;
  static const int symbol = 3;
  static const int broken = 4;
  static const int nonIndic = 5;
}

/// [codePoint]'s Indic category (low byte) and position (high byte).
int _categories(int codePoint) =>
    rangeValue(indicCategoryRanges, codePoint, indicCategoryRangesDefault);

/// The Indic grammar (HarfBuzz's `hb-ot-shaper-indic-machine.rl`).
final SyllableGrammar _grammar = () {
  Pattern s(List<int> cats) => sym(cats);
  final c = s([_Cat.c, _Cat.ra]);
  final n =
      (s([_Cat.zwnj]).opt & s([_Cat.rs])).opt &
      (s([_Cat.n]) & s([_Cat.n]).opt).opt;
  final z = s([_Cat.zwj, _Cat.zwnj]);
  final reph = (s([_Cat.ra]) & s([_Cat.h])) | s([_Cat.repha]);
  final sm = s([_Cat.sm, _Cat.smPst]);
  final cn = c & s([_Cat.zwj]).opt & n.opt;
  final symbol = s([_Cat.symbol]) & s([_Cat.n]).opt;
  final matraGroup =
      z.star &
      (s([_Cat.m]) | (sm.opt & s([_Cat.mPst]))) &
      s([_Cat.n]).opt &
      s([_Cat.h]).opt;
  final syllableTail =
      (z.opt & sm & sm.opt & s([_Cat.zwnj]).opt).opt & s([_Cat.a]).star;
  final halantGroup =
      z.opt & s([_Cat.h]) & (s([_Cat.zwj]) & s([_Cat.n]).opt).opt;
  final finalHalantGroup = halantGroup | (s([_Cat.h]) & s([_Cat.zwnj]));
  final medialGroup = s([_Cat.cm]).opt;
  final halantOrMatraGroup = finalHalantGroup | matraGroup.star;
  final complexSyllableTail =
      (halantGroup & cn).star & medialGroup & halantOrMatraGroup & syllableTail;
  final consonantSyllable =
      s([_Cat.repha, _Cat.cs]).opt & cn & complexSyllableTail;
  final vowelSyllable =
      reph.opt & s([_Cat.v]) & n.opt & (s([_Cat.zwj]) | complexSyllableTail);
  final standaloneCluster =
      ((s([_Cat.repha, _Cat.cs]).opt & s([_Cat.placeholder])) |
          (reph.opt & s([_Cat.dottedCircle]))) &
      n.opt &
      complexSyllableTail;
  final symbolCluster = symbol & syllableTail;
  final brokenCluster = reph.opt & n.opt & complexSyllableTail;
  return SyllableGrammar([
    (consonantSyllable, _Syllable.consonant),
    (vowelSyllable, _Syllable.vowel),
    (standaloneCluster, _Syllable.standalone),
    (symbolCluster, _Syllable.symbol),
    (s([_Cat.smPst]), _Syllable.nonIndic),
    (brokenCluster, _Syllable.broken),
    (anyGlyph, _Syllable.nonIndic),
  ]);
}();

enum _RephPosition { afterMain, beforeSub, afterSub, beforePost, afterPost }

enum _RephMode { implicit, explicit, logicalRepha }

enum _BlwfMode { preAndPost, postOnly }

typedef _Config = ({
  bool hasOldSpec,
  int virama,
  _RephPosition rephPosition,
  _RephMode rephMode,
  _BlwfMode blwfMode,
});

const Map<String, _Config> _configs = {
  'Deva': (
    hasOldSpec: true,
    virama: 0x094d,
    rephPosition: _RephPosition.beforePost,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.preAndPost,
  ),
  'Beng': (
    hasOldSpec: true,
    virama: 0x09cd,
    rephPosition: _RephPosition.afterSub,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.preAndPost,
  ),
  'Guru': (
    hasOldSpec: true,
    virama: 0x0a4d,
    rephPosition: _RephPosition.beforeSub,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.preAndPost,
  ),
  'Gujr': (
    hasOldSpec: true,
    virama: 0x0acd,
    rephPosition: _RephPosition.beforePost,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.preAndPost,
  ),
  'Orya': (
    hasOldSpec: true,
    virama: 0x0b4d,
    rephPosition: _RephPosition.afterMain,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.preAndPost,
  ),
  'Taml': (
    hasOldSpec: true,
    virama: 0x0bcd,
    rephPosition: _RephPosition.afterPost,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.preAndPost,
  ),
  'Telu': (
    hasOldSpec: true,
    virama: 0x0c4d,
    rephPosition: _RephPosition.afterPost,
    rephMode: _RephMode.explicit,
    blwfMode: _BlwfMode.postOnly,
  ),
  'Knda': (
    hasOldSpec: true,
    virama: 0x0ccd,
    rephPosition: _RephPosition.afterPost,
    rephMode: _RephMode.implicit,
    blwfMode: _BlwfMode.postOnly,
  ),
  'Mlym': (
    hasOldSpec: true,
    virama: 0x0d4d,
    rephPosition: _RephPosition.afterMain,
    rephMode: _RephMode.logicalRepha,
    blwfMode: _BlwfMode.preAndPost,
  ),
};

const _Config _defaultConfig = (
  hasOldSpec: false,
  virama: 0,
  rephPosition: _RephPosition.beforePost,
  rephMode: _RephMode.implicit,
  blwfMode: _BlwfMode.preAndPost,
);

/// The features, in order, with how they apply.
const List<(String, int)> _features = [
  // Basic features, one at a time after the initial reordering.
  ('nukt', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('akhn', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('rphf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('rkrf', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('pref', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('blwf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('abvf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('half', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('pstf', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('vatu', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('cjct', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  // The others, all at once after the final reordering.
  ('init', FeatureFlags.manualJoiners | FeatureFlags.perSyllable),
  ('pres', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('abvs', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('blws', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('psts', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
  ('haln', FeatureFlags.globalManualJoiners | FeatureFlags.perSyllable),
];

const int _rphf = 2;
const int _pref = 4;
const int _blwf = 5;
const int _abvf = 6;
const int _half = 7;
const int _pstf = 8;
const int _init = 11;
const int _basicFeatures = 11;

/// The Indic shaper.
final class IndicShaper extends Shaper {
  /// An Indic shaper.
  new();

  String _script = 'Deva';
  _Config _config = _defaultConfig;
  bool _oldSpec = false;
  bool _zeroContext = false;
  late OpenTypeLayout _layout;
  final List<int> _masks = List.filled(_features.length, 0);
  final Map<String, List<LayoutLookup>> _wouldLookups = {};

  @override
  void collectFeatures(PlanBuilder builder, String script) {
    _script = script;
    builder
      ..addGsubPause(_setupSyllables)
      ..enableFeature('locl', flags: FeatureFlags.perSyllable)
      ..enableFeature('ccmp', flags: FeatureFlags.perSyllable)
      ..addGsubPause(_initialReordering);
    for (var i = 0; i < _basicFeatures; i++) {
      final (tag, flags) = _features[i];
      builder
        ..addFeature(tag, flags: flags)
        ..addGsubPause();
    }
    builder.addGsubPause(_finalReordering);
    for (var i = _basicFeatures; i < _features.length; i++) {
      final (tag, flags) = _features[i];
      builder.addFeature(tag, flags: flags);
    }
  }

  @override
  void overrideFeatures(PlanBuilder builder) {
    builder
      ..disableFeature('liga')
      ..addGsubPause();
  }

  @override
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {
    _layout = layout;
    _config = _configs[_script] ?? _defaultConfig;
    _oldSpec = _config.hasOldSpec && !(plan.gsubScript?.endsWith('2') ?? false);
    _zeroContext = !_oldSpec && _script != 'Mlym';
    for (final (i, (tag, flags)) in _features.indexed) {
      _masks[i] = flags & FeatureFlags.global != 0 ? 0 : plan.oneMaskOf(tag);
    }
    for (final tag in const ['rphf', 'pref', 'blwf', 'pstf', 'vatu']) {
      _wouldLookups[tag] = plan.stageLookups(tag);
    }
  }

  bool _would(String feature, List<int> glyphs) {
    for (final l in _wouldLookups[feature]!) {
      if (_layout.wouldSubstitute(l.index, glyphs, zeroContext: _zeroContext)) {
        return true;
      }
    }
    return false;
  }

  @override
  void preprocessText(ShapeContext context) =>
      insertVowelConstraintCircles(context.glyphs, context.script);

  @override
  NormalizationMode get normalization =>
      NormalizationMode.composedDiacriticsNoShortCircuit;

  @override
  (int, int)? decompose(int ab) => switch (ab) {
    0x0931 || 0x09dc || 0x09dd || 0x0b94 => null,
    _ => unicodeDecompose(ab),
  };

  @override
  int? compose(int a, int b) {
    if (isMark(a)) return null;
    if (a == 0x09af && b == 0x09bc) return 0x09df;
    return unicodeCompose(a, b);
  }

  @override
  ZeroWidthMarks get zeroWidthMarks => ZeroWidthMarks.none;

  @override
  bool get fallbackPosition => false;

  @override
  void setupMasks(ShapeContext context) {
    for (final g in context.glyphs) {
      final v = _categories(g.char);
      g
        ..category = v & 0xff
        ..position = v >> 8;
    }
  }

  void _setupSyllables(ShapeState state) {
    _grammar.findSyllables(
      state.glyphs,
      (g) => g.category,
      broken: _Syllable.broken,
    );
  }

  // Helpers on a glyph: none of them holds once it ligated.

  static bool _isOneOf(LayoutGlyph g, Set<int> categories) =>
      !g.isLigated && categories.contains(g.category);

  static const Set<int> _consonants = {
    _Cat.c,
    _Cat.cs,
    _Cat.ra,
    _Cat.cm,
    _Cat.v,
    _Cat.placeholder,
    _Cat.dottedCircle,
  };

  static const Set<int> _joiners = {_Cat.zwj, _Cat.zwnj};

  static bool _isConsonant(LayoutGlyph g) => _isOneOf(g, _consonants);

  static bool _isJoiner(LayoutGlyph g) => _isOneOf(g, _joiners);

  static bool _isHalant(LayoutGlyph g) => _isOneOf(g, const {_Cat.h});

  int _viramaGlyph = -1;

  int _virama(ShapeState state) {
    if (_viramaGlyph < 0) {
      _viramaGlyph = _config.virama == 0 ? 0 : state.glyphFor(_config.virama);
    }
    return _viramaGlyph;
  }

  void _initialReordering(ShapeState state) {
    final glyphs = state.glyphs;
    // The base consonants' positions, by what the font does with them.
    final virama = _virama(state);
    if (virama != 0) {
      for (final g in glyphs) {
        if (g.position != _Pos.baseC) continue;
        g.position = _consonantPosition(g.glyph, virama);
      }
    }
    insertDottedCircles(
      glyphs,
      state.glyphFor,
      broken: _Syllable.broken,
      category: _Cat.dottedCircle,
      repha: _Cat.repha,
      position: _Pos.end,
    );
    for (final (start, end) in syllables(glyphs).toList()) {
      switch (glyphs[start].syllable & 0x0f) {
        case _Syllable.vowel ||
            _Syllable.consonant ||
            _Syllable.broken ||
            _Syllable.standalone:
          _initialReorderingConsonantSyllable(glyphs, start, end);
      }
    }
  }

  int _consonantPosition(int consonant, int virama) {
    final glyphs = [virama, consonant, virama];
    bool would(String feature) =>
        _would(feature, glyphs.sublist(0, 2)) ||
        _would(feature, glyphs.sublist(1, 3));
    if (would('blwf') || would('vatu')) return _Pos.belowC;
    if (would('pstf')) return _Pos.postC;
    if (would('pref')) return _Pos.postC;
    return _Pos.baseC;
  }

  void _initialReorderingConsonantSyllable(
    List<LayoutGlyph> info,
    int start,
    int end,
  ) {
    // For compatibility with legacy usage in Kannada, Ra+H+ZWJ must
    // behave like Ra+ZWJ+H.
    if (_script == 'Knda' &&
        start + 3 <= end &&
        _isOneOf(info[start], const {_Cat.ra}) &&
        _isOneOf(info[start + 1], const {_Cat.h}) &&
        _isOneOf(info[start + 2], const {_Cat.zwj})) {
      mergeClusters(info, start + 1, start + 3);
      final t = info[start + 1];
      info[start + 1] = info[start + 2];
      info[start + 2] = t;
    }

    // 1. Find the base consonant.
    var base = end;
    var hasReph = false;
    {
      var limit = start;
      if (_masks[_rphf] != 0 &&
          start + 3 <= end &&
          ((_config.rephMode == _RephMode.implicit &&
                  !_isJoiner(info[start + 2])) ||
              (_config.rephMode == _RephMode.explicit &&
                  info[start + 2].category == _Cat.zwj))) {
        final glyphs = [
          info[start].glyph,
          info[start + 1].glyph,
          if (_config.rephMode == _RephMode.explicit) info[start + 2].glyph,
        ];
        if (_would('rphf', glyphs.sublist(0, 2)) ||
            (_config.rephMode == _RephMode.explicit &&
                _would('rphf', glyphs))) {
          limit += 2;
          while (limit < end && _isJoiner(info[limit])) {
            limit++;
          }
          base = start;
          hasReph = true;
        }
      } else if (_config.rephMode == _RephMode.logicalRepha &&
          info[start].category == _Cat.repha) {
        limit += 1;
        while (limit < end && _isJoiner(info[limit])) {
          limit++;
        }
        base = start;
        hasReph = true;
      }

      // Starting from the end of the syllable, move backwards.
      var i = end;
      var seenBelow = false;
      do {
        i--;
        if (_isConsonant(info[i])) {
          if (info[i].position != _Pos.belowC &&
              (info[i].position != _Pos.postC || seenBelow)) {
            base = i;
            break;
          }
          if (info[i].position == _Pos.belowC) seenBelow = true;
          base = i;
        } else if (start < i &&
            info[i].category == _Cat.zwj &&
            info[i - 1].category == _Cat.h) {
          // A ZWJ after a Halant stops the base search.
          break;
        }
      } while (i > limit);

      // No other consonant: the Ra is the base, not a reph.
      if (hasReph && base == start && limit - base <= 2) hasReph = false;
    }

    // Reorder characters.
    for (var i = start; i < base; i++) {
      if (info[i].position > _Pos.preC) {
        info[i].position = _Pos.preC;
      }
    }
    if (base < end) info[base].position = _Pos.baseC;
    if (hasReph) info[start].position = _Pos.raToBecomeReph;

    // Old-spec: the first post-base Halant moved after the last consonant.
    if (_oldSpec) {
      final disallowDoubleHalants = _script == 'Knda';
      for (var i = base + 1; i < end; i++) {
        if (info[i].category != _Cat.h) continue;
        var j = end - 1;
        for (; j > i; j--) {
          if (_isConsonant(info[j]) ||
              (disallowDoubleHalants && info[j].category == _Cat.h)) {
            break;
          }
        }
        if (info[j].category != _Cat.h && j > i) {
          final t = info.removeAt(i);
          info.insert(j, t);
        }
        break;
      }
    }

    // Misc marks attached to the previous character, to move with it.
    {
      var lastPos = _Pos.start;
      for (var i = start; i < end; i++) {
        final cat = info[i].category;
        if (cat == _Cat.zwj ||
            cat == _Cat.zwnj ||
            cat == _Cat.n ||
            cat == _Cat.rs ||
            cat == _Cat.cm ||
            cat == _Cat.h) {
          info[i].position = lastPos;
          if (cat == _Cat.h && info[i].position == _Pos.preM) {
            // A Halant doesn't move with a left Matra.
            for (var j = i; j > start; j--) {
              if (info[j - 1].position != _Pos.preM) {
                info[i].position = info[j - 1].position;
                break;
              }
            }
          }
        } else if (info[i].position != _Pos.smvd) {
          if (cat == _Cat.mPst &&
              i > start &&
              info[i - 1].category == _Cat.sm) {
            info[i - 1].position = info[i].position;
          }
          lastPos = info[i].position;
        }
      }
    }
    // Post-base consonants own what is before them since the last
    // consonant or matra.
    {
      var last = base;
      for (var i = base + 1; i < end; i++) {
        if (_isConsonant(info[i])) {
          for (var j = last + 1; j < i; j++) {
            if (info[j].position < _Pos.smvd) {
              info[j].position = info[i].position;
            }
          }
          last = i;
        } else if (info[i].category == _Cat.m ||
            info[i].category == _Cat.mPst) {
          last = i;
        }
      }
    }

    {
      // The original index of each glyph, for the clusters.
      final original = {for (var i = start; i < end; i++) info[i]: i - start};
      final sorted = info.sublist(start, end).indexed.toList()
        ..sort((a, b) {
          final d = a.$2.position - b.$2.position;
          return d != 0 ? d : a.$1 - b.$1;
        });
      info.setRange(start, end, [for (final (_, g) in sorted) g]);

      // Find base again; also flip a left-matra sequence.
      var firstLeftMatra = end;
      var lastLeftMatra = end;
      base = end;
      for (var i = start; i < end; i++) {
        if (info[i].position == _Pos.baseC) {
          base = i;
          break;
        } else if (info[i].position == _Pos.preM) {
          if (firstLeftMatra == end) firstLeftMatra = i;
          lastLeftMatra = i;
        }
      }
      if (firstLeftMatra < lastLeftMatra) {
        _reverse(info, firstLeftMatra, lastLeftMatra + 1);
        // Reverse back nuktas, etc.
        var i = firstLeftMatra;
        for (var j = i; j <= lastLeftMatra; j++) {
          if (info[j].category == _Cat.m || info[j].category == _Cat.mPst) {
            _reverse(info, i, j + 1);
            i = j + 1;
          }
        }
      }

      if (_oldSpec || end - start > 127) {
        mergeClusters(info, base, end);
      } else {
        final index = [for (var i = start; i < end; i++) original[info[i]]!];
        final done = List.filled(end - start, false);
        for (var i = base; i < end; i++) {
          if (done[i - start]) continue;
          var min = i;
          var max = i;
          var j = start + index[i - start];
          while (j != i) {
            if (j < min) min = j;
            if (j > max) max = j;
            final next = start + index[j - start];
            done[j - start] = true;
            j = next;
          }
          mergeClusters(info, base > min ? base : min, max + 1);
        }
      }
    }

    // Masks.
    for (
      var i = start;
      i < end && info[i].position == _Pos.raToBecomeReph;
      i++
    ) {
      info[i].mask |= _masks[_rphf];
    }
    var mask = _masks[_half];
    if (!_oldSpec && _config.blwfMode == _BlwfMode.preAndPost) {
      mask |= _masks[_blwf];
    }
    for (var i = start; i < base; i++) {
      info[i].mask |= mask;
    }
    mask = _masks[_blwf] | _masks[_abvf] | _masks[_pstf];
    for (var i = base + 1; i < end; i++) {
      info[i].mask |= mask;
    }

    if (_oldSpec && _script == 'Deva') {
      // Old-spec eyelash Ra.
      for (var i = start; i + 1 < base; i++) {
        if (info[i].category == _Cat.ra &&
            info[i + 1].category == _Cat.h &&
            (i + 2 == base || info[i + 2].category != _Cat.zwj)) {
          info[i].mask |= _masks[_blwf];
          info[i + 1].mask |= _masks[_blwf];
        }
      }
    }

    const prefLength = 2;
    if (_masks[_pref] != 0 && base + prefLength < end) {
      // A Halant,Ra sequence marked for pre-base reordering.
      for (var i = base + 1; i + prefLength - 1 < end; i++) {
        final glyphs = [for (var j = 0; j < prefLength; j++) info[i + j].glyph];
        if (_would('pref', glyphs)) {
          for (var j = 0; j < prefLength; j++) {
            info[i++].mask |= _masks[_pref];
          }
          break;
        }
      }
    }

    // ZWJ/ZWNJ effects: a ZWNJ disables HALF.
    for (var i = start + 1; i < end; i++) {
      if (!_isJoiner(info[i])) continue;
      final nonJoiner = info[i].category == _Cat.zwnj;
      var j = i;
      do {
        j--;
        if (nonJoiner) info[j].mask &= ~_masks[_half];
      } while (j > start && !_isConsonant(info[j]));
    }
  }

  static void _reverse(List<LayoutGlyph> glyphs, int start, int end) {
    final reversed = glyphs.sublist(start, end).reversed.toList();
    glyphs.setRange(start, end, reversed);
  }

  void _finalReordering(ShapeState state) {
    final glyphs = state.glyphs;
    for (final (start, end) in syllables(glyphs).toList()) {
      _finalReorderingSyllable(glyphs, start, end);
    }
  }

  void _finalReorderingSyllable(List<LayoutGlyph> info, int start, int end) {
    // A virama glyph that a ligature and multiplication made is a halant
    // again.
    final virama = _viramaGlyph;
    if (virama > 0) {
      for (var i = start; i < end; i++) {
        if (info[i].glyph == virama &&
            info[i].isLigated &&
            info[i].isMultiplied) {
          info[i]
            ..category = _Cat.h
            ..props &= ~(GlyphProps.ligated | GlyphProps.multiplied);
        }
      }
    }

    var tryPref = _masks[_pref] != 0;

    // Find base again.
    var base = start;
    for (; base < end; base++) {
      if (info[base].position >= _Pos.baseC) {
        if (tryPref && base + 1 < end) {
          for (var i = base + 1; i < end; i++) {
            if (info[i].mask & _masks[_pref] != 0) {
              if (!(info[i].isSubstituted &&
                  info[i].isLigated &&
                  !info[i].isMultiplied)) {
                // A 'pref' candidate that formed nothing.
                base = i;
                while (base < end && _isHalant(info[base])) {
                  base++;
                }
                if (base < end) info[base].position = _Pos.baseC;
                tryPref = false;
              }
              break;
            }
          }
          if (base == end) break;
        }
        // Malayalam: skip over unformed below- (but not post-) forms.
        if (_script == 'Mlym') {
          for (var i = base + 1; i < end; i++) {
            while (i < end && _isJoiner(info[i])) {
              i++;
            }
            if (i == end || !_isHalant(info[i])) break;
            i++;
            while (i < end && _isJoiner(info[i])) {
              i++;
            }
            if (i < end &&
                _isConsonant(info[i]) &&
                info[i].position == _Pos.belowC) {
              base = i;
              info[base].position = _Pos.baseC;
            }
          }
        }
        if (start < base && info[base].position > _Pos.baseC) {
          base--;
        }
        break;
      }
    }
    if (base == end &&
        start < base &&
        _isOneOf(info[base - 1], const {_Cat.zwj})) {
      base--;
    }
    if (base < end) {
      while (start < base && _isOneOf(info[base], const {_Cat.n, _Cat.h})) {
        base--;
      }
    }

    // Reorder matras.
    if (start + 1 < end && start < base) {
      var newPos = base == end ? base - 2 : base - 1;
      if (_script != 'Mlym' && _script != 'Taml') {
        while (true) {
          while (newPos > start &&
              !_isOneOf(info[newPos], const {_Cat.m, _Cat.mPst, _Cat.h})) {
            newPos--;
          }
          if (_isHalant(info[newPos]) && info[newPos].position != _Pos.preM) {
            if (newPos + 1 < end &&
                info[newPos + 1].category == _Cat.zwj &&
                newPos > start) {
              // A ZWJ after this halant: keep searching.
              newPos--;
              continue;
            }
          } else {
            newPos = start;
          }
          break;
        }
      }
      if (start < newPos && info[newPos].position != _Pos.preM) {
        for (var i = newPos; i > start; i--) {
          if (info[i - 1].position == _Pos.preM) {
            final oldPos = i - 1;
            if (oldPos < base && base <= newPos) base--;
            final t = info.removeAt(oldPos);
            info.insert(newPos, t);
            mergeClusters(info, newPos, end < base + 1 ? end : base + 1);
            newPos--;
          }
        }
      } else {
        for (var i = start; i < base; i++) {
          if (info[i].position == _Pos.preM) {
            mergeClusters(info, i, end < base + 1 ? end : base + 1);
            break;
          }
        }
      }
    }

    // Reorder reph.
    if (start + 1 < end &&
        info[start].position == _Pos.raToBecomeReph &&
        ((info[start].category == _Cat.repha) !=
            (info[start].isLigated && !info[start].isMultiplied))) {
      final rephPos = _config.rephPosition;
      int? newRephPos;
      int step2And5() {
        var p = start + 1;
        while (p < base && !_isHalant(info[p])) {
          p++;
        }
        if (p < base && _isHalant(info[p])) {
          if (p + 1 < base && _isJoiner(info[p + 1])) p++;
          return p;
        }
        return -1;
      }

      if (rephPos != _RephPosition.afterPost) {
        // 2.
        final p = step2And5();
        if (p >= 0) newRephPos = p;
        // 3.
        if (newRephPos == null && rephPos == _RephPosition.afterMain) {
          var q = base;
          while (q + 1 < end && info[q + 1].position <= _Pos.afterMain) {
            q++;
          }
          if (q < end) newRephPos = q;
        }
        // 4.
        if (newRephPos == null && rephPos == _RephPosition.afterSub) {
          var q = base;
          while (q + 1 < end &&
              !const {
                _Pos.postC,
                _Pos.afterPost,
                _Pos.smvd,
              }.contains(info[q + 1].position)) {
            q++;
          }
          if (q < end) newRephPos = q;
        }
      }
      // 5.
      if (newRephPos == null) {
        final p = step2And5();
        if (p >= 0) newRephPos = p;
      }
      // 6. The end of the syllable.
      if (newRephPos == null) {
        var q = end - 1;
        while (q > start && info[q].position == _Pos.smvd) {
          q--;
        }
        if (_isHalant(info[q])) {
          for (var i = base + 1; i < q; i++) {
            if (info[i].category == _Cat.m || info[i].category == _Cat.mPst) {
              q--;
            }
          }
        }
        newRephPos = q;
      }
      mergeClusters(info, start, newRephPos + 1);
      final reph = info.removeAt(start);
      info.insert(newRephPos, reph);
      if (start < base && base <= newRephPos) base--;
    }

    // Reorder pre-base-reordering consonants.
    if (tryPref && base + 1 < end) {
      for (var i = base + 1; i < end; i++) {
        if (info[i].mask & _masks[_pref] == 0) continue;
        if (info[i].isLigated && !info[i].isMultiplied) {
          var newPos = base;
          if (_script != 'Mlym' && _script != 'Taml') {
            while (newPos > start &&
                !_isOneOf(info[newPos - 1], const {
                  _Cat.m,
                  _Cat.mPst,
                  _Cat.h,
                })) {
              newPos--;
            }
          }
          if (newPos > start && _isHalant(info[newPos - 1])) {
            if (newPos < end && _isJoiner(info[newPos])) newPos++;
          }
          final oldPos = i;
          mergeClusters(info, newPos, oldPos + 1);
          final t = info.removeAt(oldPos);
          info.insert(newPos, t);
          if (newPos <= base && base < oldPos) base++;
        }
        break;
      }
    }

    // 'init' on a left matra at a word's start.
    if (info[start].position == _Pos.preM) {
      final previous = start == 0 ? -1 : info[start - 1].generalCategory;
      // (Format to nonspacing mark: a letter or mark before it.)
      if (previous < GeneralCategory.format.index ||
          previous > GeneralCategory.nonspacingMark.index) {
        info[start].mask |= _masks[_init];
      }
    }
  }
}
