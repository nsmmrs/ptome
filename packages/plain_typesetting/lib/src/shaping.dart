/// Text shaped by a font's OpenType layout tables in full: the scripts
/// whose letters change with their neighbours (Arabic's joining forms)
/// or carry marks the font places (Arabic's and Hebrew's vowels and
/// cantillation), and right-to-left runs, put in visual order. The
/// features and their order are HarfBuzz's for those scripts (its
/// Arabic shaper's and its default one's).
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// The OpenType script tag of [codePoint]'s script, where its shaping
/// differs from the default's (`arab`, `hebr`), else null.
String? _scriptOf(int codePoint) {
  if ((codePoint >= 0x0600 && codePoint <= 0x06ff) ||
      (codePoint >= 0x0750 && codePoint <= 0x077f) ||
      (codePoint >= 0x0870 && codePoint <= 0x08ff) ||
      (codePoint >= 0xfb50 && codePoint <= 0xfdff) ||
      (codePoint >= 0xfe70 && codePoint <= 0xfeff) ||
      (codePoint >= 0x10ec0 && codePoint <= 0x10eff) ||
      (codePoint >= 0x1ee00 && codePoint <= 0x1eeff)) {
    return 'arab';
  }
  if ((codePoint >= 0x0590 && codePoint <= 0x05ff) ||
      (codePoint >= 0xfb1d && codePoint <= 0xfb4f)) {
    return 'hebr';
  }
  return null;
}

/// Whether [text] has characters of a script that needs the font's
/// layout tables in full (Arabic, Hebrew).
bool needsComplexShaping(String text) {
  for (final unit in text.codeUnits) {
    if (unit >= 0x0590 && unit <= 0x08ff) return true;
    if (unit >= 0xfb1d && unit <= 0xfeff) return true;
  }
  return false;
}

/// Whether [codePoint] is a default ignorable that takes no room and
/// shows nothing (joiners, directional marks and controls).
bool _hidden(int codePoint) =>
    codePoint == 0x200b ||
    (codePoint >= 0x200c && codePoint <= 0x200f) ||
    (codePoint >= 0x202a && codePoint <= 0x202e) ||
    (codePoint >= 0x2060 && codePoint <= 0x2064) ||
    (codePoint >= 0x2066 && codePoint <= 0x2069) ||
    codePoint == 0xfeff ||
    codePoint == 0x061c ||
    codePoint == 0x034f;

/// The mask bits of the features that apply to some glyphs only.
abstract final class _Mask {
  static const int global = 1;
  static const int isol = 2;
  static const int fina = 4;
  static const int medi = 8;
  static const int init = 16;
  static const int liga = 32;
  static const int kern = 64;
}

/// The layouts of the fonts shaped so far.
final Expando<OpenTypeLayout> _layouts = Expando();

/// [text] in [shaper]'s font as HarfBuzz shapes it: the characters'
/// glyphs (mirrored in a right-to-left run), Arabic letters in their
/// joining forms, the GSUB features in the script's stages, the GPOS
/// features, marks without advances, attached glyphs offset from their
/// pen positions; [rightToLeft], the glyphs reversed into visual order.
List<ShapedGlyph> shapeComplex(
  OpenTypeShaper shaper,
  String text, {
  required bool kerning,
  required bool ligatures,
  required Set<String> features,
  required bool rightToLeft,
}) {
  final font = shaper.font;
  final layout = _layouts[font] ??= OpenTypeLayout(font);
  final runes = text.runes.toList();
  if (runes.isEmpty) return const [];
  var script = 'DFLT';
  for (final rune in runes) {
    if (_scriptOf(rune) case final found?) {
      script = found;
      break;
    }
  }
  final arabic = script == 'arab';
  // The glyphs, each its character's (mirrored where right to left).
  final run = <LayoutGlyph>[
    for (final (i, rune) in runes.indexed)
      LayoutGlyph(
        font.glyphFor(rightToLeft ? bidiMirror(rune) : rune),
        i,
        mask:
            _Mask.global |
            (ligatures ? _Mask.liga : 0) |
            (kerning ? _Mask.kern : 0),
      ),
  ];
  _reorderMarks(runes, run, arabic: arabic);
  final codes = _compose(font, runes, run);
  if (arabic) _joiningForms(codes, run);
  // The GSUB stages, each its features' lookups in order of index.
  List<(int, int)> stage(
    List<(String, int)> stageFeatures, {
    bool gpos = false,
  }) {
    final lookups = <int, int>{};
    for (final (feature, mask) in stageFeatures) {
      for (final index in layout.lookupsFor(
        feature,
        script: script,
        positioning: gpos,
      )) {
        lookups[index] = (lookups[index] ?? 0) | mask;
      }
    }
    return [
      for (final index in lookups.keys.toList()..sort())
        (index, lookups[index]!),
    ];
  }

  final extra = [for (final f in features) (f, _Mask.global)];
  final direction = rightToLeft
      ? [('rtla', _Mask.global), ('rtlm', _Mask.global)]
      : [('ltra', _Mask.global), ('ltrm', _Mask.global)];
  final stages = <List<(int, int)>>[
    stage([('rvrn', _Mask.global)]),
    stage([...direction, ...extra]),
    if (arabic) ...[
      stage([('stch', _Mask.global)]),
      stage([('ccmp', _Mask.global), ('locl', _Mask.global)]),
      stage([('isol', _Mask.isol)]),
      stage([('fina', _Mask.fina)]),
      stage([('fin2', _Mask.fina)]),
      stage([('fin3', _Mask.fina)]),
      stage([('medi', _Mask.medi)]),
      stage([('med2', _Mask.medi)]),
      stage([('init', _Mask.init)]),
      stage([('rlig', _Mask.global)]),
      stage([('rclt', _Mask.global), ('calt', _Mask.global)]),
      stage([
        ('mset', _Mask.global),
        ('liga', _Mask.liga),
        ('clig', _Mask.liga),
      ]),
    ] else
      stage([
        ('ccmp', _Mask.global),
        ('locl', _Mask.global),
        ('rlig', _Mask.global),
        ('rclt', _Mask.global),
        ('calt', _Mask.global),
        ('liga', _Mask.liga),
        ('clig', _Mask.liga),
      ]),
  ];
  for (final lookups in stages) {
    layout.substitute(run, lookups);
  }
  // Positioning: the advances, the GPOS features, marks without advances.
  for (final g in run) {
    g.xAdvance = font.advance(g.glyph);
  }
  layout.position(
    run,
    stage([
      ('abvm', _Mask.global),
      ('blwm', _Mask.global),
      ('mark', _Mask.global),
      ('mkmk', _Mask.global),
      ('curs', _Mask.global),
      ('dist', _Mask.global),
      ('kern', _Mask.kern),
    ], gpos: true),
    rightToLeft: rightToLeft,
    zeroMarks: true,
  );
  // The text of each glyph: its characters, up to the next glyph's (a
  // ligature's all of its components').
  final starts = {for (final g in run) g.cluster}.toList()..sort();
  String textOf(int cluster) {
    final next = starts.firstWhere((c) => c > cluster, orElse: () => -1);
    return String.fromCharCodes(
      runes.sublist(cluster, next < 0 ? runes.length : next),
    );
  }

  final seen = <int>{};
  final glyphs = <ShapedGlyph>[
    for (final g in run)
      if (!_hidden(runes[g.cluster]))
        ShapedGlyph.positioned(
          g.glyph,
          // (A cluster's text with its first glyph; the others none.)
          seen.add(g.cluster) ? textOf(g.cluster) : '',
          shaper.scale(g.xAdvance),
          xOffset: shaper.scale(g.xOffset),
          yOffset: shaper.scale(g.yOffset),
        ),
  ];
  return rightToLeft ? glyphs.reversed.toList() : glyphs;
}

/// Each Arabic letter's joining form (`isol`, `fina`, `medi`, `init`)
/// from its Joining_Type and its neighbours' (transparent marks passed
/// over), as its mask: [codes], the character of each glyph of [run].
void _joiningForms(List<int> codes, List<LayoutGlyph> run) {
  // (A join-causing character, tatweel, joins as a dual-joining letter
  // does and takes its forms, as HarfBuzz has it.)
  JoiningType type(int i) => switch (joiningType(codes[i])) {
    JoiningType.joinCausing => JoiningType.dualJoining,
    final t => t,
  };
  bool joinsBefore(JoiningType t) =>
      t == JoiningType.rightJoining ||
      t == JoiningType.dualJoining ||
      t == JoiningType.joinCausing;
  bool joinsAfter(JoiningType t) =>
      t == JoiningType.leftJoining ||
      t == JoiningType.dualJoining ||
      t == JoiningType.joinCausing;
  int neighbour(int i, int step) {
    for (var k = i + step; k >= 0 && k < codes.length; k += step) {
      if (type(k) != JoiningType.transparent) return k;
    }
    return -1;
  }

  for (var i = 0; i < codes.length; i++) {
    final t = type(i);
    if (t != JoiningType.rightJoining &&
        t != JoiningType.dualJoining &&
        t != JoiningType.leftJoining) {
      continue;
    }
    final before = neighbour(i, -1);
    final after = neighbour(i, 1);
    final prev = before >= 0 && joinsBefore(t) && joinsAfter(type(before));
    final next = after >= 0 && joinsAfter(t) && joinsBefore(type(after));
    final form = prev && next
        ? _Mask.medi
        : prev
        ? _Mask.fina
        : next
        ? _Mask.init
        : _Mask.isol;
    run[i].mask |= form;
  }
}

/// HarfBuzz's modified combining class of [codePoint]: Unicode's, but
/// Hebrew's points (10 to 26) in the order of the SBL Hebrew manual and
/// Arabic's shadda (33) before the other vowels.
int _modifiedClass(int codePoint) {
  final ccc = canonicalCombiningClass(codePoint);
  return switch (ccc) {
    10 => 22, // sheva
    11 => 15, // hataf segol
    12 => 16, // hataf patah
    13 => 17, // hataf qamats
    14 => 23, // hiriq
    15 => 18, // tsere
    16 => 19, // segol
    17 => 20, // patah
    18 => 21, // qamats
    19 => 14, // holam
    20 => 24, // qubuts
    21 => 12, // dagesh
    22 => 25, // meteg
    23 => 13, // rafe
    24 => 10, // shin dot
    25 => 11, // sin dot
    26 => 26, // point varika
    27 => 28, // fathatan
    28 => 29, // dammatan
    29 => 30, // kasratan
    30 => 31, // fatha
    31 => 32, // damma
    32 => 33, // kasra
    33 => 27, // shadda
    34 => 34, // sukun
    35 => 35, // superscript alef
    _ => ccc,
  };
}

/// Arabic's modifier combining marks (hamza above and below and the
/// like), which go first among the marks of their class.
const Set<int> _modifierMarks = {
  0x0654, 0x0655, 0x0658, 0x06dc, 0x06e3, 0x06e7, 0x06e8, 0x08ca, //
  0x08cb, 0x08cd, 0x08ce, 0x08cf, 0x08d3, 0x08f3,
};

/// Each run of marks in [run] in canonical order (by the modified
/// classes, stably), and, in Arabic, its modifier combining marks of
/// classes 220 and 230 moved to its start (HarfBuzz's normalization and
/// its Arabic shaper's `reorder_marks`).
void _reorderMarks(
  List<int> runes,
  List<LayoutGlyph> run, {
  required bool arabic,
}) {
  int classOf(LayoutGlyph g) => _modifiedClass(runes[g.cluster]);
  var i = 0;
  while (i < run.length) {
    if (classOf(run[i]) == 0) {
      i++;
      continue;
    }
    var end = i;
    while (end < run.length && classOf(run[end]) != 0) {
      end++;
    }
    if (end - i > 1) {
      final marks = run.sublist(i, end);
      // (Stable: a merge sort keeps equal classes in order.)
      final sorted = [...marks.indexed]
        ..sort((a, b) {
          final c = classOf(a.$2) - classOf(b.$2);
          return c != 0 ? c : a.$1 - b.$1;
        });
      var ordered = [for (final (_, g) in sorted) g];
      if (arabic) {
        for (final cc in const [220, 230]) {
          final moving = [
            for (final g in ordered)
              if (classOf(g) == cc && _modifierMarks.contains(runes[g.cluster]))
                g,
          ];
          if (moving.isEmpty) continue;
          ordered = [...moving, ...ordered.where((g) => !moving.contains(g))];
        }
      }
      run.setRange(i, end, ordered);
    }
    i = end;
  }
}

/// The canonical compositions of Arabic letters and marks (UnicodeData's
/// decompositions of U+0622 to U+0626 and U+06C0, U+06C2, U+06D3; none is
/// a composition exclusion).
const Map<(int, int), int> _compositions = {
  (0x0627, 0x0653): 0x0622,
  (0x0627, 0x0654): 0x0623,
  (0x0648, 0x0654): 0x0624,
  (0x0627, 0x0655): 0x0625,
  (0x064a, 0x0654): 0x0626,
  (0x06d5, 0x0654): 0x06c0,
  (0x06c1, 0x0654): 0x06c2,
  (0x06d2, 0x0654): 0x06d3,
};

/// Each letter composed with a mark after it where Unicode composes them
/// canonically and the font has the composed character (HarfBuzz's
/// normalization: alef and madda above as alef with madda), the mark not
/// blocked by one of its class or higher before it. The character of
/// each glyph after.
List<int> _compose(OpenTypeFont font, List<int> runes, List<LayoutGlyph> run) {
  final current = [for (final g in run) runes[g.cluster]];
  var i = 0;
  while (i < run.length) {
    if (canonicalCombiningClass(current[i]) != 0) {
      i++;
      continue;
    }
    var blocking = -1;
    var j = i + 1;
    while (j < run.length) {
      final ccc = canonicalCombiningClass(current[j]);
      if (ccc == 0) break;
      final composed = _compositions[(current[i], current[j])];
      if (composed != null && ccc > blocking) {
        final glyph = font.glyphFor(composed);
        if (glyph != 0) {
          run[i].glyph = glyph;
          current[i] = composed;
          run.removeAt(j);
          current.removeAt(j);
          continue;
        }
      }
      if (ccc > blocking) blocking = ccc;
      j++;
    }
    i = j;
  }
  return current;
}
