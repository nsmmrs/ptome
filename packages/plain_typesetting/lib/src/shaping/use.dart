/// The Universal Shaping Engine (HarfBuzz 14.6's `hb-ot-shaper-use.cc`),
/// for the scripts that have no shaper of their own (Sinhala, Tibetan,
/// Mongolian, N'Ko, Javanese, Balinese, ... and the Indic scripts under
/// their third script tags): syllables found by its grammar, the
/// features in Microsoft's groups, repha and pre-base glyphs reordered,
/// the joining scripts' forms set as the Arabic shaper sets them.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/arabic.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_typesetting/src/shaping/syllabic.dart';
import 'package:plain_typesetting/src/shaping/use_data.g.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// The USE categories (HarfBuzz's machine's numbers).
abstract final class _U {
  static const int o = 0;
  static const int b = 1;
  static const int n = 4;
  static const int gb = 5;
  static const int cgj = 6;
  static const int sub = 11;
  static const int h = 12;
  static const int hn = 13;
  static const int zwnj = 14;
  static const int r = 18;
  static const int cs = 43;
  static const int iS = 44;
  static const int sk = 48;
  static const int g = 49;
  static const int j = 50;
  static const int sb = 51;
  static const int se = 52;
  static const int hvm = 53;
  static const int hm = 54;
  static const int hr = 55;
  static const int rk = 56;
  static const int fAbv = 24;
  static const int fBlw = 25;
  static const int fPst = 26;
  static const int mAbv = 27;
  static const int mBlw = 28;
  static const int mPst = 29;
  static const int mPre = 30;
  static const int cmAbv = 31;
  static const int cmBlw = 32;
  static const int vAbv = 33;
  static const int vBlw = 34;
  static const int vPst = 35;
  static const int vPre = 22;
  static const int vmAbv = 37;
  static const int vmBlw = 38;
  static const int vmPst = 39;
  static const int vmPre = 23;
  static const int smAbv = 41;
  static const int smBlw = 42;
  static const int fmAbv = 45;
  static const int fmBlw = 46;
  static const int fmPst = 47;
}

/// The syllable types.
abstract final class _Syllable {
  static const int viramaTerminated = 0;
  static const int sakotTerminated = 1;
  static const int standard = 2;
  static const int numberJoinerTerminated = 3;
  static const int numeral = 4;
  static const int symbol = 5;
  static const int hieroglyph = 6;
  static const int broken = 7;
  static const int non = 8;
}

/// The USE grammar (HarfBuzz's `hb-ot-shaper-use-machine.rl`).
final SyllableGrammar _grammar = () {
  Pattern s(List<int> cats) => sym(cats);
  Pattern star(int c) => s([c]).star;
  Pattern opt(int c) => s([c]).opt;
  Pattern plus(int c) => s([c]) & s([c]).star;
  final h = s([_U.h, _U.hvm, _U.iS, _U.sk]);
  final consonantModifiers =
      star(_U.cmAbv) &
      star(_U.cmBlw) &
      (((h & s([_U.b])) | s([_U.sub])) & star(_U.cmAbv) & star(_U.cmBlw)).star;
  final medialConsonants =
      opt(_U.mPre) & opt(_U.mAbv) & opt(_U.mBlw) & opt(_U.mPst);
  final dependentVowels =
      (star(_U.vPre) & star(_U.vAbv) & star(_U.vBlw) & star(_U.vPst)) |
      s([_U.h]);
  final vowelModifiers =
      opt(_U.hvm) &
      star(_U.vmPre) &
      star(_U.vmAbv) &
      star(_U.vmBlw) &
      star(_U.vmPst);
  final finalConsonants = star(_U.fAbv) & star(_U.fBlw) & star(_U.fPst);
  final finalModifiers = (star(_U.fmAbv) & star(_U.fmBlw)) | opt(_U.fmPst);
  final complexSyllableStart = s([_U.r, _U.cs]).opt & s([_U.b, _U.gb]);
  final complexSyllableMiddle =
      consonantModifiers &
      medialConsonants &
      dependentVowels &
      vowelModifiers &
      (s([_U.sk]) & s([_U.b])).star;
  final complexSyllableTail =
      complexSyllableMiddle & finalConsonants & finalModifiers;
  final numberJoinerTerminatedTail = (s([_U.hn]) & s([_U.n])).star & s([_U.hn]);
  final numeralTail = (s([_U.hn]) & s([_U.n])) & (s([_U.hn]) & s([_U.n])).star;
  final symbolTail = (plus(_U.smAbv) & star(_U.smBlw)) | plus(_U.smBlw);
  final viramaTerminatedTail = consonantModifiers & s([_U.iS, _U.rk]);
  final viramaTerminated = complexSyllableStart & viramaTerminatedTail;
  final sakotTerminatedTail = complexSyllableMiddle & s([_U.sk]);
  final sakotTerminated = complexSyllableStart & sakotTerminatedTail;
  final standard = complexSyllableStart & complexSyllableTail;
  final tail =
      complexSyllableTail |
      sakotTerminatedTail |
      symbolTail |
      viramaTerminatedTail;
  final broken = opt(_U.r) & (tail | numberJoinerTerminatedTail | numeralTail);
  final numberJoinerTerminated = s([_U.n]) & numberJoinerTerminatedTail;
  final numeral = s([_U.n]) & numeralTail.opt;
  final symbol = s([_U.o, _U.gb, _U.sb]) & tail.opt;
  final glyphGroup = s([_U.g]) & opt(_U.hr) & opt(_U.hm) & star(_U.se);
  final hieroglyph =
      star(_U.sb) &
      glyphGroup &
      (s([_U.j]) & star(_U.sb) & glyphGroup.opt).star;
  final zwnj = opt(_U.zwnj);
  return SyllableGrammar([
    (viramaTerminated & zwnj, _Syllable.viramaTerminated),
    (sakotTerminated & zwnj, _Syllable.sakotTerminated),
    (standard & zwnj, _Syllable.standard),
    (numberJoinerTerminated & zwnj, _Syllable.numberJoinerTerminated),
    (numeral & zwnj, _Syllable.numeral),
    (symbol & zwnj, _Syllable.symbol),
    (hieroglyph & zwnj, _Syllable.hieroglyph),
    (s([_U.fmPst]), _Syllable.non),
    (broken & zwnj, _Syllable.broken),
    (anyGlyph, _Syllable.non),
  ]);
}();

/// The scripts whose letters join (HarfBuzz's `has_arabic_joining`).
const Set<String> _joiningScripts = {
  'Adlm', 'Arab', 'Chrs', 'Rohg', 'Mand', 'Mani', 'Mong', 'Nkoo', 'Ougr', //
  'Phag', 'Phlp', 'Sogd', 'Syrc',
};

const List<String> _basicFeatures = [
  'rkrf',
  'abvf',
  'blwf',
  'half',
  'pstf',
  'vatu',
  'cjct',
];

/// The topographical features, in the order of the joining forms.
const List<String> _topographical = ['isol', 'init', 'medi', 'fina'];

const List<String> _otherFeatures = ['abvs', 'blws', 'haln', 'pres', 'psts'];

/// The categories after a base: a repha moves before the first of them.
const Set<int> _postBase = {
  _U.fAbv, _U.fBlw, _U.fPst, _U.fmAbv, _U.fmBlw, _U.fmPst, _U.mAbv, //
  _U.mBlw, _U.mPst, _U.mPre, _U.vAbv, _U.vBlw, _U.vPst, _U.vPre,
  _U.vmAbv, _U.vmBlw, _U.vmPst, _U.vmPre,
};

/// The Universal Shaping Engine.
final class UseShaper extends Shaper {
  /// A USE shaper.
  new();

  String _script = '';
  int _rphfMask = 0;
  bool _joining = false;
  final List<int> _arabicMasks = List.filled(8, 0);
  final List<int> _topographicalMasks = List.filled(4, 0);
  int _globalMask = 0;

  @override
  void collectFeatures(PlanBuilder builder, String script) {
    _script = script;
    builder
      ..addGsubPause(_setupSyllables)
      ..enableFeature('locl', flags: FeatureFlags.perSyllable)
      ..enableFeature('ccmp', flags: FeatureFlags.perSyllable)
      ..enableFeature('nukt', flags: FeatureFlags.perSyllable)
      ..enableFeature(
        'akhn',
        flags: FeatureFlags.manualZwj | FeatureFlags.perSyllable,
      )
      ..addGsubPause(_clearSubstituted)
      ..addFeature(
        'rphf',
        flags: FeatureFlags.manualZwj | FeatureFlags.perSyllable,
      )
      ..addGsubPause(_recordRphf)
      ..addGsubPause(_clearSubstituted)
      ..enableFeature(
        'pref',
        flags: FeatureFlags.manualZwj | FeatureFlags.perSyllable,
      )
      ..addGsubPause(_recordPref);
    for (final tag in _basicFeatures) {
      builder.enableFeature(
        tag,
        flags: FeatureFlags.manualZwj | FeatureFlags.perSyllable,
      );
    }
    builder
      ..addGsubPause(_reorder)
      ..addGsubPause();
    _topographical.forEach(builder.addFeature);
    builder.addGsubPause();
    for (final tag in _otherFeatures) {
      builder.enableFeature(tag, flags: FeatureFlags.manualZwj);
    }
  }

  @override
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {
    _rphfMask = plan.oneMaskOf('rphf');
    _joining = _joiningScripts.contains(_script);
    _globalMask = plan.globalMask;
    for (final (i, feature) in arabicFeatures.indexed) {
      _arabicMasks[i] = plan.oneMaskOf(feature);
    }
    for (final (i, tag) in _topographical.indexed) {
      _topographicalMasks[i] = plan.oneMaskOf(tag);
    }
  }

  @override
  void preprocessText(ShapeContext context) =>
      insertVowelConstraintCircles(context.glyphs, context.script);

  @override
  NormalizationMode get normalization =>
      NormalizationMode.composedDiacriticsNoShortCircuit;

  @override
  int? compose(int a, int b) => isMark(a) ? null : unicodeCompose(a, b);

  @override
  ZeroWidthMarks get zeroWidthMarks => ZeroWidthMarks.byGdefEarly;

  @override
  bool get fallbackPosition => false;

  @override
  void setupMasks(ShapeContext context) {
    final glyphs = context.glyphs;
    if (_joining) {
      for (final (i, action) in joiningActions(glyphs, _script).indexed) {
        glyphs[i].mask |= _arabicMasks[action];
      }
    }
    for (final g in glyphs) {
      g.category = rangeValue(
        useCategoryRanges,
        g.char,
        useCategoryRangesDefault,
      );
    }
  }

  void _setupSyllables(ShapeState state) {
    final glyphs = state.glyphs;
    _grammar.findSyllables(
      glyphs,
      (g) => g.category,
      broken: _Syllable.broken,
      keep: (i) {
        final g = glyphs[i];
        if (g.category == _U.cgj) return false;
        if (g.category == _U.zwnj) {
          for (var k = i + 1; k < glyphs.length; k++) {
            if (glyphs[k].category != _U.cgj) {
              return !isUnicodeMark(glyphs[k]);
            }
          }
        }
        return true;
      },
    );
    // The repha's mask.
    if (_rphfMask != 0) {
      for (final (start, end) in syllables(glyphs)) {
        final limit = glyphs[start].category == _U.r
            ? 1
            : (end - start < 3 ? end - start : 3);
        for (var i = start; i < start + limit; i++) {
          glyphs[i].mask |= _rphfMask;
        }
      }
    }
    _setupTopographicalMasks(glyphs);
  }

  void _setupTopographicalMasks(List<LayoutGlyph> glyphs) {
    if (_joining) return;
    final masks = [
      for (final m in _topographicalMasks)
        if (m == _globalMask) 0 else m,
    ];
    final all = masks.fold(0, (a, b) => a | b);
    if (all == 0) return;
    final others = ~all;
    const isol = 0;
    const init = 1;
    const medi = 2;
    const fina = 3;
    const none = 4;
    var lastStart = 0;
    var lastForm = none;
    for (final (start, end) in syllables(glyphs)) {
      switch (glyphs[start].syllable & 0x0f) {
        case _Syllable.hieroglyph || _Syllable.non:
          lastForm = none;
        default:
          final join = lastForm == fina || lastForm == isol;
          if (join) {
            lastForm = lastForm == fina ? medi : init;
            for (var i = lastStart; i < start; i++) {
              glyphs[i].mask = (glyphs[i].mask & others) | masks[lastForm];
            }
          }
          lastForm = join ? fina : isol;
          for (var i = start; i < end; i++) {
            glyphs[i].mask = (glyphs[i].mask & others) | masks[lastForm];
          }
      }
      lastStart = start;
    }
  }

  static void _clearSubstituted(ShapeState state) {
    for (final g in state.glyphs) {
      g.props &= ~GlyphProps.substituted;
    }
  }

  void _recordRphf(ShapeState state) {
    if (_rphfMask == 0) return;
    final glyphs = state.glyphs;
    for (final (start, end) in syllables(glyphs)) {
      // A substituted repha is a repha.
      for (var i = start; i < end && glyphs[i].mask & _rphfMask != 0; i++) {
        if (glyphs[i].isSubstituted) {
          glyphs[i].category = _U.r;
          break;
        }
      }
    }
  }

  static void _recordPref(ShapeState state) {
    final glyphs = state.glyphs;
    for (final (start, end) in syllables(glyphs)) {
      // A substituted pre-base form behaves as a pre-base vowel.
      for (var i = start; i < end; i++) {
        if (glyphs[i].isSubstituted) {
          glyphs[i].category = _U.vPre;
          break;
        }
      }
    }
  }

  static bool _isHalant(LayoutGlyph g) =>
      (g.category == _U.h || g.category == _U.hvm || g.category == _U.iS) &&
      !g.isLigated;

  void _reorder(ShapeState state) {
    final glyphs = state.glyphs;
    insertDottedCircles(
      glyphs,
      state.glyphFor,
      broken: _Syllable.broken,
      category: _U.b,
      repha: _U.r,
    );
    for (final (start, end) in syllables(glyphs).toList()) {
      _reorderSyllable(glyphs, start, end);
    }
  }

  static void _reorderSyllable(List<LayoutGlyph> info, int start, int end) {
    switch (info[start].syllable & 0x0f) {
      case _Syllable.viramaTerminated ||
          _Syllable.sakotTerminated ||
          _Syllable.standard ||
          _Syllable.symbol ||
          _Syllable.broken:
        break;
      default:
        return;
    }
    // Move a repha forward, before the first post-base glyph.
    if (info[start].category == _U.r && end - start > 1) {
      for (var i = start + 1; i < end; i++) {
        final postBase =
            _postBase.contains(info[i].category) || _isHalant(info[i]);
        if (postBase || i == end - 1) {
          final to = postBase ? i - 1 : i;
          mergeClusters(info, start, to + 1);
          final reph = info.removeAt(start);
          info.insert(to, reph);
          break;
        }
      }
    }
    // Move pre-base glyphs back.
    var j = start;
    for (var i = start; i < end; i++) {
      final c = info[i].category;
      if (_isHalant(info[i])) {
        j = i + 1;
      } else if ((c == _U.vPre || c == _U.vmPre) &&
          info[i].ligatureComponent == 0 &&
          j < i) {
        mergeClusters(info, j, i + 1);
        final t = info.removeAt(i);
        info.insert(j, t);
      }
    }
  }
}
