/// Kashida: a justified line of Arabic stretched inside its words, by
/// tatweel (U+0640 ARABIC TATWEEL) drawn between two joined letters, before
/// its spaces are.
///
/// Each word is lengthened at one place, the first of its places in this
/// ranking (the last of them where it has several of one rank), Microsoft's
/// for Arabic justification (as the W3C's "Arabic & Persian Layout
/// Requirements" describe it too):
///
/// 1. after a tatweel the text has;
/// 2. after an initial or medial Seen or Sad;
/// 3. before a final Teh Marbuta, Heh or Dal;
/// 4. before a final Alef, Tah, Lam, Kaf or Gaf;
/// 5. before a medial Beh followed by a final Reh, Yeh or Alef Maqsura;
/// 6. before a final Waw, Ain, Qaf or Feh;
/// 7. before any other final letter.
///
/// Never between Lam and Alef, which are written as one letterform.
///
/// The line's extra width goes to the words of the first rank, each up to
/// a limit, then to the next rank's, and so on; what is left widens the
/// spaces. The tatweel is drawn as one glyph, or as several overlapping to
/// fill a longer stretch exactly; it stands for no text, so the line reads
/// as it is written.
library;

import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_unicode/plain_unicode.dart' show JoiningType, joiningType;

/// A line's run of text the kashida may stretch: its `glyphs` in visual
/// order, set in `style`, `rightToLeft` or not.
typedef KashidaRun = ({
  List<ShapedGlyph> glyphs,
  TextStyle style,
  bool rightToLeft,
});

const int _tatweel = 0x0640;

Set<int> _set(List<(int, int)> ranges) => {
  for (final (first, last) in ranges)
    for (var c = first; c <= last; c++) c,
};

final Set<int> _seenSad = _set(const [
  (0x0633, 0x0636),
  (0x069a, 0x069e),
  (0x06fa, 0x06fa),
  (0x075c, 0x075c),
  (0x076d, 0x076d),
  (0x0770, 0x0770),
  (0x077d, 0x077e),
]);

final Set<int> _hehDal = _set(const [
  (0x0629, 0x0629),
  (0x062f, 0x0630),
  (0x0647, 0x0647),
  (0x0688, 0x0690),
  (0x06c0, 0x06c3),
  (0x06d5, 0x06d5),
  (0x06ee, 0x06ee),
]);

final Set<int> _alefTahLamKafGaf = _set(const [
  (0x0622, 0x0623),
  (0x0625, 0x0625),
  (0x0627, 0x0627),
  (0x0637, 0x0638),
  (0x0643, 0x0644),
  (0x0671, 0x0673),
  (0x0675, 0x0675),
  (0x069f, 0x069f),
  (0x06a9, 0x06b8),
]);

final Set<int> _rehYeh = _set(const [
  (0x0626, 0x0626),
  (0x0631, 0x0632),
  (0x0649, 0x064a),
  (0x0691, 0x0699),
  (0x06cc, 0x06cc),
  (0x06ce, 0x06ce),
  (0x06d0, 0x06d3),
  (0x06ef, 0x06ef),
]);

final Set<int> _beh = _set(const [
  (0x0626, 0x0626),
  (0x0628, 0x0628),
  (0x062a, 0x062b),
  (0x0646, 0x0646),
  (0x064a, 0x064a),
  (0x066e, 0x066e),
  (0x0679, 0x0680),
  (0x06b9, 0x06bd),
  (0x06cc, 0x06cc),
  (0x06ce, 0x06ce),
  (0x06d0, 0x06d1),
]);

final Set<int> _wawAinQafFeh = _set(const [
  (0x0624, 0x0624),
  (0x0639, 0x063a),
  (0x0641, 0x0642),
  (0x0648, 0x0648),
  (0x066f, 0x066f),
  (0x06a0, 0x06a8),
  (0x06c4, 0x06cb),
  (0x06cf, 0x06cf),
]);

final Set<int> _lam = _set(const [(0x0644, 0x0644), (0x06b5, 0x06b8)]);

final Set<int> _alef = _set(const [
  (0x0622, 0x0623),
  (0x0625, 0x0625),
  (0x0627, 0x0627),
  (0x0671, 0x0673),
  (0x0675, 0x0675),
]);

/// A letter's glyph and the marks on it, in logical order: [start] to
/// [end] in the reversed glyphs.
final class _Unit {
  new(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  late final List<int> _letters = [
    for (final c in text.runes)
      if (joiningType(c) != JoiningType.transparent) c,
  ];

  int? get first => _letters.firstOrNull;
  int? get last => _letters.lastOrNull;

  /// Joined to the letter before it.
  bool get joinsBefore => switch (first) {
    final c? => switch (joiningType(c)) {
      .rightJoining || .dualJoining || .joinCausing => true,
      _ => false,
    },
    null => false,
  };

  /// Joined to the letter after it.
  bool get joinsAfter => switch (last) {
    final c? => switch (joiningType(c)) {
      .leftJoining || .dualJoining || .joinCausing => true,
      _ => false,
    },
    null => false,
  };

  bool get isSpace => text.contains(' ');
}

/// A place to lengthen: in run `run`, before the glyphs of logical unit
/// `unit`, with its `rank` (and its text's `size`).
typedef _Point = ({int run, _Unit unit, int rank, double size});

/// The units of [glyphs] (a right-to-left run's, in visual order) in
/// logical order: each glyph that advances with the marks after it.
List<_Unit> _units(List<ShapedGlyph> glyphs) {
  final logical = glyphs.reversed.toList();
  final units = <_Unit>[];
  var i = 0;
  while (i < logical.length) {
    final start = i;
    final text = StringBuffer(logical[i].text);
    i++;
    while (i < logical.length && logical[i].advance == 0) {
      text.write(logical[i].text);
      i++;
    }
    units.add(_Unit(start, i, text.toString()));
  }
  return units;
}

/// The rank of the place between [units] `k` and `k + 1` (joined), or
/// null where the ranking has none.
int? _rank(List<_Unit> units, int k) {
  final before = units[k];
  final after = units[k + 1];
  bool isFinal(int i) => !units[i].joinsAfter || i + 1 == units.length;
  // (Never inside Lam-Alef, one letterform however a font draws it.)
  if (_lam.contains(before.last) && _alef.contains(after.first)) return null;
  if (before.last == _tatweel) return 1;
  if (_seenSad.contains(before.last)) return 2;
  if (isFinal(k + 1)) {
    final letter = after.first;
    if (_hehDal.contains(letter)) return 3;
    if (_alefTahLamKafGaf.contains(letter)) return 4;
    if (_wawAinQafFeh.contains(letter)) return 6;
  }
  if (_beh.contains(after.first) &&
      k + 2 < units.length &&
      after.joinsAfter &&
      units[k + 2].joinsBefore &&
      isFinal(k + 2) &&
      _rehYeh.contains(units[k + 2].first)) {
    return 5;
  }
  if (isFinal(k + 1)) return 7;
  return null;
}

/// Each word's place to lengthen in [glyphs] (a right-to-left run's), in
/// logical order.
List<(_Unit, int)> _places(List<ShapedGlyph> glyphs) {
  final logical = glyphs.reversed.toList();
  final units = _units(glyphs);
  final places = <(_Unit, int)>[];
  (_Unit, int)? best;
  for (var k = 0; k < units.length; k++) {
    if (units[k].isSpace) {
      if (best != null) places.add(best);
      best = null;
      continue;
    }
    if (k + 1 >= units.length || units[k + 1].isSpace) continue;
    if (!units[k].joinsAfter || !units[k + 1].joinsBefore) continue;
    // (Not where the letters are set off the line, as a Nastaliq word's
    // cascade is.)
    if (logical[units[k].start].yOffset != 0 ||
        logical[units[k + 1].start].yOffset != 0) {
      continue;
    }
    final rank = _rank(units, k);
    if (rank == null) continue;
    if (best == null || rank <= best.$2) best = (units[k + 1], rank);
  }
  if (best != null) places.add(best);
  return places;
}

/// The tatweel of [style]'s font: its glyph id and advance (in 1000ths of
/// the em), or null where it has none.
(int, double)? _tatweelOf(TextStyle style) {
  final glyphs = style.shape('ـ', rightToLeft: true);
  if (glyphs.length != 1) return null;
  final glyph = glyphs.single;
  if (glyph.id == 0 || glyph.advance <= 0) return null;
  return (glyph.id, glyph.advance);
}

/// Tatweels [width] wide (1000ths of the em), of glyph [id] [advance]
/// wide: one, centered on the stretch, where it is wider than the
/// stretch; else as many as cover it, overlapping evenly, the last ending
/// where the stretch does.
List<ShapedGlyph> _tatweels(int id, double advance, double width) {
  if (width <= advance) {
    return [
      ShapedGlyph.positioned(id, '', width, xOffset: (width - advance) / 2),
    ];
  }
  final count = (width / advance).ceil();
  final step = (width - advance) / (count - 1);
  return [
    for (var i = 0; i < count; i++)
      ShapedGlyph.positioned(id, '', i < count - 1 ? step : advance),
  ];
}

/// [runs] (a line's; null for what isn't text) lengthened by kashida to
/// take up to [extra] points more, each word at most [limit] em: each
/// run's glyphs with their tatweels (null where it has none), and the
/// width they took.
(List<List<ShapedGlyph>?>, double) kashida(
  List<KashidaRun?> runs,
  double extra,
  double limit,
) {
  final result = List<List<ShapedGlyph>?>.filled(runs.length, null);
  if (extra <= 0 || limit <= 0) return (result, 0);
  final points = <_Point>[];
  final tatweels = <int, (int, double)>{};
  for (final (i, run) in runs.indexed) {
    if (run == null || !run.rightToLeft) continue;
    final tatweel = _tatweelOf(run.style);
    if (tatweel == null) continue;
    final places = _places(run.glyphs);
    if (places.isEmpty) continue;
    tatweels[i] = tatweel;
    for (final (unit, rank) in places) {
      points.add((run: i, unit: unit, rank: rank, size: run.style.size));
    }
  }
  if (points.isEmpty) return (result, 0);
  // The ranks in turn, each word up to the limit, until the extra is used.
  final widths = <_Point, double>{};
  var left = extra;
  for (var rank = 1; rank <= 7 && left > 1e-6; rank++) {
    final ranked = [
      for (final p in points)
        if (p.rank == rank) p,
    ];
    if (ranked.isEmpty) continue;
    // (Water filling: an equal share, a word's limit where that is less.)
    final sorted = [...ranked]
      ..sort((a, b) => (a.size * limit).compareTo(b.size * limit));
    var remaining = sorted.length;
    for (final p in sorted) {
      final share = left / remaining;
      final width = share < p.size * limit ? share : p.size * limit;
      widths[p] = width;
      left -= width;
      remaining--;
    }
  }
  var taken = 0.0;
  for (final (i, run) in runs.indexed) {
    if (run == null) continue;
    final runPoints = [
      for (final p in points)
        if (p.run == i && (widths[p] ?? 0) > 0) p,
    ];
    if (runPoints.isEmpty) continue;
    final (id, advance) = tatweels[i]!;
    final style = run.style;
    final logical = run.glyphs.reversed.toList();
    // (Before the unit, in logical order: after it, reversed.)
    final at = {for (final p in runPoints) p.unit.start: widths[p]!};
    final out = <ShapedGlyph>[];
    for (var g = 0; g < logical.length; g++) {
      if (at[g] case final width?) {
        // (Logically before glyph g: the tatweels reversed after it.)
        out.addAll(
          _tatweels(
            id,
            advance,
            width * 1000 / style.size / (style.horizontalScaling / 100) -
                style.characterSpacing * 1000 / style.size,
          ).reversed,
        );
      }
      out.add(logical[g]);
    }
    final glyphs = out.reversed.toList();
    taken += style.widthOf(glyphs) - style.widthOf(run.glyphs);
    result[i] = glyphs;
  }
  return (result, taken);
}
