/// The Arabic shaper (HarfBuzz 14.6's `hb-ot-shaper-arabic.cc`), for
/// Arabic and Syriac, whose joining it also does for the Universal
/// Shaping Engine's joining scripts (Mongolian, N'Ko, ...): each letter's
/// form from its joining type and its neighbours', by HarfBuzz's state
/// machine (with Syriac's Alaph and Dalath-Rish forms), then the features
/// in the specification's order with pauses between.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// No joining action (the actions 0 to 6 index [arabicFeatures]).
const int _none = 7;

/// The joining features, in the order of the actions.
const List<String> arabicFeatures = [
  'isol',
  'fina',
  'fin2',
  'fin3',
  'medi',
  'med2',
  'init',
];

// The state machine's columns.
const int _jtU = 0;
const int _jtL = 1;
const int _jtR = 2;
const int _jtD = 3;
const int _jgAlaph = 4;
const int _jgDalathRish = 5;
const int _jtT = 6;

/// HarfBuzz's state table: for each state and column, the action for the
/// previous letter, the action for this one (indices of [arabicFeatures],
/// 7 none), and the next state.
const List<List<(int, int, int)>> _states = [
  // State 0: prev was U, not willing to join.
  [(7, 7, 0), (7, 0, 2), (7, 0, 1), (7, 0, 2), (7, 0, 1), (7, 0, 6)],
  // State 1: prev was R or ISOL/ALAPH, not willing to join.
  [(7, 7, 0), (7, 0, 2), (7, 0, 1), (7, 0, 2), (7, 2, 5), (7, 0, 6)],
  // State 2: prev was D/L in ISOL form, willing to join.
  [(7, 7, 0), (7, 0, 2), (6, 1, 1), (6, 1, 3), (6, 1, 4), (6, 1, 6)],
  // State 3: prev was D in FINA form, willing to join.
  [(7, 7, 0), (7, 0, 2), (4, 1, 1), (4, 1, 3), (4, 1, 4), (4, 1, 6)],
  // State 4: prev was FINA ALAPH, not willing to join.
  [(7, 7, 0), (7, 0, 2), (5, 0, 1), (5, 0, 2), (5, 2, 5), (5, 0, 6)],
  // State 5: prev was FIN2/FIN3 ALAPH, not willing to join.
  [(7, 7, 0), (7, 0, 2), (0, 0, 1), (0, 0, 2), (0, 2, 5), (0, 0, 6)],
  // State 6: prev was DALATH/RISH, not willing to join.
  [(7, 7, 0), (7, 0, 2), (7, 0, 1), (7, 0, 2), (7, 3, 5), (7, 0, 6)],
];

/// [code]'s column of the state machine (a join-causing character as a
/// dual-joining one; Syriac's Alaph and Dalath-Rish groups apart).
int _joiningColumn(int code) {
  if (code == 0x0710) return _jgAlaph;
  if (code == 0x0715 || code == 0x0716 || code == 0x072a || code == 0x072f) {
    return _jgDalathRish;
  }
  return switch (joiningType(code)) {
    JoiningType.nonJoining => _jtU,
    JoiningType.leftJoining => _jtL,
    JoiningType.rightJoining => _jtR,
    JoiningType.dualJoining || JoiningType.joinCausing => _jtD,
    JoiningType.transparent => _jtT,
  };
}

/// Each glyph's joining action (`isol` ... `init`, or none), by
/// HarfBuzz's `arabic_joining`; for Mongolian, a free variation selector
/// takes its base's.
List<int> joiningActions(List<LayoutGlyph> glyphs, String script) {
  final actions = List.filled(glyphs.length, _none);
  var prev = -1;
  var state = 0;
  for (var i = 0; i < glyphs.length; i++) {
    final column = _joiningColumn(glyphs[i].char);
    if (column == _jtT) continue;
    final (prevAction, currAction, next) = _states[state][column];
    if (prevAction != _none && prev >= 0) actions[prev] = prevAction;
    actions[i] = currAction;
    prev = i;
    state = next;
  }
  if (script == 'Mong') {
    for (var i = 1; i < glyphs.length; i++) {
      final c = glyphs[i].char;
      if ((c >= 0x180b && c <= 0x180d) || c == 0x180f) {
        actions[i] = actions[i - 1];
      }
    }
  }
  return actions;
}

/// Arabic's modifier combining marks (hamza above and below and the
/// like), which go first among the marks of their class.
const Set<int> _modifierMarks = {
  0x0654, 0x0655, 0x0658, 0x06dc, 0x06e3, 0x06e7, 0x06e8, 0x08ca, //
  0x08cb, 0x08cd, 0x08ce, 0x08cf, 0x08d3, 0x08f3,
};

/// The Arabic shaper.
final class ArabicShaper extends Shaper {
  /// An Arabic shaper.
  new();

  String _script = 'Arab';
  final List<int> _masks = List.filled(8, 0);

  @override
  void collectFeatures(PlanBuilder builder, String script) {
    _script = script;
    builder
      ..enableFeature('stch')
      ..addGsubPause()
      ..enableFeature('ccmp', flags: FeatureFlags.manualZwj)
      ..enableFeature('locl', flags: FeatureFlags.manualZwj)
      ..addGsubPause();
    for (final feature in arabicFeatures) {
      final syriac = feature.endsWith('2') || feature.endsWith('3');
      final hasFallback = script == 'Arab' && !syriac;
      builder
        ..addFeature(
          feature,
          flags:
              FeatureFlags.manualZwj |
              (hasFallback ? FeatureFlags.hasFallback : 0),
        )
        ..addGsubPause();
    }
    builder
      ..addGsubPause()
      ..enableFeature(
        'rlig',
        flags: FeatureFlags.manualZwj | FeatureFlags.hasFallback,
      );
    if (script == 'Arab') builder.addGsubPause();
    builder.enableFeature('calt', flags: FeatureFlags.manualZwj);
    if (!builder.hasFeature('rclt')) builder.addGsubPause();
    builder
      ..enableFeature('liga', flags: FeatureFlags.manualZwj)
      ..enableFeature('clig', flags: FeatureFlags.manualZwj)
      ..enableFeature('mset', flags: FeatureFlags.manualZwj);
  }

  @override
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {
    for (final (i, feature) in arabicFeatures.indexed) {
      _masks[i] = plan.oneMaskOf(feature);
    }
  }

  @override
  void setupMasks(ShapeContext context) {
    final glyphs = context.glyphs;
    for (final (i, action) in joiningActions(glyphs, _script).indexed) {
      glyphs[i].mask |= _masks[action];
    }
  }

  @override
  void reorderMarks(List<LayoutGlyph> glyphs, int start, int end) {
    var i = start;
    var s = start;
    for (final cc in const [220, 230]) {
      while (i < end && glyphs[i].combiningClass < cc) {
        i++;
      }
      if (i == end) break;
      if (glyphs[i].combiningClass > cc) continue;
      var j = i;
      while (j < end &&
          glyphs[j].combiningClass == cc &&
          _modifierMarks.contains(glyphs[j].char)) {
        j++;
      }
      if (i == j) continue;
      // Shift them to the start, renumbered so the sequence stays
      // sorted (22 and 26, below every Arabic class).
      final moving = glyphs.sublist(i, j);
      glyphs
        ..removeRange(i, j)
        ..insertAll(s, moving);
      final newStart = s + moving.length;
      for (; s < newStart; s++) {
        glyphs[s].combiningClass = cc == 220 ? 22 : 26;
      }
      i = j;
    }
  }
}
