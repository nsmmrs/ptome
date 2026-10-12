/// The Unicode Bidirectional Algorithm (UAX #9, Unicode 18.0.0): each
/// character's embedding level in its paragraph, and the visual order of
/// a line's characters; with the Bidi_Class, Bidi_Mirroring_Glyph and
/// Joining_Type properties it uses (and Arabic shaping does).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_unicode/src/bidi_data.g.dart' as data;

/// The Bidi_Class of a character.
enum BidiClass {
  /// Left-to-right.
  l,

  /// Right-to-left.
  r,

  /// Arabic letter (right-to-left).
  al,

  /// European number.
  en,

  /// European number separator.
  es,

  /// European number terminator.
  et,

  /// Arabic number.
  an,

  /// Common number separator.
  cs,

  /// Nonspacing mark.
  nsm,

  /// Boundary neutral.
  bn,

  /// Paragraph separator.
  b,

  /// Segment separator.
  s,

  /// Whitespace.
  ws,

  /// Other neutral.
  on,

  /// Left-to-right embedding.
  lre,

  /// Left-to-right override.
  lro,

  /// Right-to-left embedding.
  rle,

  /// Right-to-left override.
  rlo,

  /// Pop directional format.
  pdf,

  /// Left-to-right isolate.
  lri,

  /// Right-to-left isolate.
  rli,

  /// First strong isolate.
  fsi,

  /// Pop directional isolate.
  pdi,
}

/// How a character joins its neighbours in a cursive script (Arabic,
/// Syriac, N'Ko...): its Joining_Type.
enum JoiningType {
  /// Non-joining (U).
  nonJoining,

  /// Joins the character before it, on its right (R).
  rightJoining,

  /// Joins on both sides (D).
  dualJoining,

  /// Causes joining, joining nothing itself (C: tatweel, ZWJ).
  joinCausing,

  /// Joins the character after it, on its left (L).
  leftJoining,

  /// Transparent: the characters around it join across it (T: marks).
  transparent,
}

/// The direction text runs in.
enum TextDirection {
  /// Left to right.
  ltr,

  /// Right to left.
  rtl,
}

/// The bidirectional properties of every code point, decoded on first use.
final class _Properties {
  new()
    : palette = Uint16List.fromList(data.palette),
      stage1 = _words(data.stage1),
      stage2 = _words(data.stage2),
      stage3 = base64.decode(data.stage3);

  final Uint16List palette;
  final Uint16List stage1;
  final Uint16List stage2;
  final Uint8List stage3;

  @pragma('vm:prefer-inline')
  int operator [](int c) =>
      palette[stage3[stage2[stage1[c >> 11] + (c >> 5 & 63)] + (c & 31)]];

  static Uint16List _words(String encoded) {
    final bytes = base64.decode(encoded);
    final words = Uint16List(bytes.length >> 1);
    for (var i = 0; i < words.length; i++) {
      words[i] = bytes[2 * i] | bytes[2 * i + 1] << 8;
    }
    return words;
  }
}

final _Properties _properties = _Properties();

int _property(int codePoint) =>
    _properties[codePoint < 0
        ? 0
        : codePoint > 0x10ffff
        ? 0x10ffff
        : codePoint];

/// The Bidi_Class of [codePoint].
BidiClass bidiClass(int codePoint) =>
    BidiClass.values[_property(codePoint) & 0x1f];

/// The Joining_Type of [codePoint].
JoiningType joiningType(int codePoint) =>
    JoiningType.values[_property(codePoint) >> 5 & 7];

/// The Bidi_Mirroring_Glyph pairs, by code point.
final Map<int, int> _mirrors = {
  for (var i = 0; i < data.mirrors.length; i += 2)
    data.mirrors[i]: data.mirrors[i + 1],
};

/// The Bidi_Paired_Bracket pairs, by code point.
final Map<int, int> _bracketPairs = {
  for (var i = 0; i < data.brackets.length; i += 2)
    data.brackets[i]: data.brackets[i + 1],
};

/// The Canonical_Combining_Class of [codePoint]: 0 for a base character,
/// else the class its mark is ordered by (Unicode's canonical ordering).
int canonicalCombiningClass(int codePoint) {
  const ranges = data.combining;
  var lo = 0;
  var hi = ranges.length ~/ 3 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (codePoint < ranges[3 * mid]) {
      hi = mid - 1;
    } else if (codePoint > ranges[3 * mid + 1]) {
      lo = mid + 1;
    } else {
      return ranges[3 * mid + 2];
    }
  }
  return 0;
}

/// The character that mirrors [codePoint] in right-to-left text (`(` for
/// `)`, `«` for `»`: its Bidi_Mirroring_Glyph), or [codePoint] itself.
int bidiMirror(int codePoint) => _mirrors[codePoint] ?? codePoint;

/// The most explicit embedding levels nest (BD2).
const int _maxDepth = 125;

/// A text's paragraphs resolved by the Unicode Bidirectional Algorithm:
/// the embedding level of each of its code units, from which a line's
/// characters are put in visual order ([visualRuns]).
@immutable
final class BidiText {
  /// [text] resolved, each paragraph's base direction [direction], or,
  /// when null, its first strong character's (rules P2 and P3: left to
  /// right without one).
  factory(String text, {TextDirection? direction}) {
    final units = text.length;
    // The class of each code unit (a surrogate pair's both units the
    // character's, the second then treated as a boundary neutral).
    final classes = Uint8List(units);
    final codePoints = Int32List(units);
    for (var i = 0; i < units; i++) {
      var c = text.codeUnitAt(i);
      if (c >= 0xd800 && c < 0xdc00 && i + 1 < units) {
        final low = text.codeUnitAt(i + 1);
        if (low >= 0xdc00 && low < 0xe000) {
          c = 0x10000 + ((c - 0xd800) << 10) + (low - 0xdc00);
          classes[i] = bidiClass(c).index;
          codePoints[i] = c;
          i++;
          classes[i] = BidiClass.bn.index;
          codePoints[i] = -1;
          continue;
        }
      }
      classes[i] = bidiClass(c).index;
      codePoints[i] = c;
    }
    return BidiText.classes(
      classes,
      codePoints: codePoints,
      direction: direction,
    );
  }

  /// The resolution of a sequence of [classes] (`BidiClass` indices), as
  /// a text's ([codePoints]: each one's character, for bracket pairs;
  /// none, for the conformance test's class sequences).
  factory classes(
    Uint8List classes, {
    Int32List? codePoints,
    TextDirection? direction,
  }) {
    final levels = Uint8List(classes.length);
    final paragraphLevels = Uint8List(classes.length);
    final original = Uint8List.fromList(classes);
    // (Resolved in a copy: the caller's classes stay as they are.)
    final working = Uint8List.fromList(classes);
    var start = 0;
    while (start < working.length) {
      var end = start;
      while (end < working.length && working[end] != BidiClass.b.index) {
        end++;
      }
      if (end < working.length) end++; // the separator ends its paragraph
      final paragraph = _Paragraph(
        Uint8List.sublistView(working, start, end),
        codePoints == null
            ? null
            : Int32List.sublistView(codePoints, start, end),
        direction,
      );
      levels.setRange(start, end, paragraph.levels);
      paragraphLevels.fillRange(start, end, paragraph.level);
      start = end;
    }
    return BidiText._(levels, paragraphLevels, original);
  }

  const new _(this.levels, this._paragraphLevels, this._classes);

  /// The embedding level of each code unit (odd: right to left), before
  /// a line's whitespace at its end is set back to its paragraph's level
  /// ([visualRuns] does that, rule L1). Explicit formatting characters
  /// (and boundary neutrals) take the level of the character before them.
  final Uint8List levels;

  final Uint8List _paragraphLevels;

  /// The original class of each code unit.
  final Uint8List _classes;

  /// The level of the paragraph [offset] is in (0 left to right, 1 right
  /// to left).
  int paragraphLevel(int offset) => _paragraphLevels[offset];

  /// The direction of the paragraph [offset] is in.
  TextDirection paragraphDirection(int offset) =>
      _paragraphLevels[offset].isOdd ? TextDirection.rtl : TextDirection.ltr;

  /// The levels of the line from [start] to [end] (code units, within one
  /// paragraph), its trailing whitespace and its segment and paragraph
  /// separators set back to the paragraph's level (rule L1).
  Uint8List lineLevels(int start, int end) {
    final line = Uint8List.fromList(levels.sublist(start, end));
    if (line.isEmpty) return line;
    final base = _paragraphLevels[start];
    var trailing = true;
    for (var i = end - 1; i >= start; i--) {
      final c = BidiClass.values[_classes[i]];
      final whitespace = switch (c) {
        BidiClass.ws ||
        BidiClass.fsi ||
        BidiClass.lri ||
        BidiClass.rli ||
        BidiClass.pdi ||
        BidiClass.bn ||
        BidiClass.lre ||
        BidiClass.rle ||
        BidiClass.lro ||
        BidiClass.rlo ||
        BidiClass.pdf => true,
        _ => false,
      };
      if (c == BidiClass.s || c == BidiClass.b) {
        line[i - start] = base;
        trailing = true;
      } else if (trailing && whitespace) {
        line[i - start] = base;
      } else {
        trailing = false;
      }
    }
    // (Whitespace before a separator inside the line too.)
    for (var i = start; i < end; i++) {
      final c = BidiClass.values[_classes[i]];
      if (c != BidiClass.s && c != BidiClass.b) continue;
      for (var k = i - 1; k >= start; k--) {
        final before = BidiClass.values[_classes[k]];
        if (before == BidiClass.ws ||
            before == BidiClass.fsi ||
            before == BidiClass.lri ||
            before == BidiClass.rli ||
            before == BidiClass.pdi ||
            before == BidiClass.bn ||
            before == BidiClass.lre ||
            before == BidiClass.rle ||
            before == BidiClass.lro ||
            before == BidiClass.rlo ||
            before == BidiClass.pdf) {
          line[k - start] = base;
        } else {
          break;
        }
      }
    }
    return line;
  }

  /// The line from [start] to [end] (code units, within one paragraph) as
  /// runs of one level each, in visual order, left to right (rules L1 and
  /// L2): each its start and end in the text, and its level (odd: its
  /// characters go right to left).
  List<(int, int, int)> visualRuns(int start, int end) {
    final line = lineLevels(start, end);
    final runs = <(int, int, int)>[];
    var from = 0;
    for (var i = 1; i <= line.length; i++) {
      if (i == line.length || line[i] != line[from]) {
        runs.add((start + from, start + i, line[from]));
        from = i;
      }
    }
    return reorderRuns(runs);
  }

  /// The visual order of the characters from [start] to [end]: the index
  /// of each, left to right (rules L1 and L2; a right-to-left run's in
  /// reverse).
  List<int> visualOrder(int start, int end) => [
    for (final (from, to, level) in visualRuns(start, end))
      if (level.isOdd)
        for (var i = to - 1; i >= from; i--) i
      else
        for (var i = from; i < to; i++) i,
  ];
}

/// [runs] (each its start, end and level, in logical order) in visual
/// order (rule L2): from the highest level down to the lowest odd one,
/// each sequence of runs at that level or higher reversed.
List<(int, int, int)> reorderRuns(List<(int, int, int)> runs) {
  if (runs.isEmpty) return runs;
  var highest = 0;
  var lowestOdd = 255;
  for (final (_, _, level) in runs) {
    highest = math.max(highest, level);
    if (level.isOdd) lowestOdd = math.min(lowestOdd, level);
  }
  final order = [...runs];
  for (var level = highest; level >= lowestOdd; level--) {
    var i = 0;
    while (i < order.length) {
      if (order[i].$3 < level) {
        i++;
        continue;
      }
      var j = i;
      while (j < order.length && order[j].$3 >= level) {
        j++;
      }
      final reversed = order.sublist(i, j).reversed.toList();
      order.setRange(i, j, reversed);
      i = j;
    }
  }
  return order;
}

/// One paragraph resolved (rules P2 to I2).
final class _Paragraph {
  new(this.classes, this.codePoints, TextDirection? direction)
    : levels = Uint8List(classes.length),
      original = Uint8List.fromList(classes) {
    level = switch (direction) {
      TextDirection.ltr => 0,
      TextDirection.rtl => 1,
      null => _firstStrong(0, classes.length, isolate: false) ?? 0,
    };
    _matchIsolates();
    _explicit();
    _sequences();
    _resolveFormatting();
  }

  /// The resolved classes (`BidiClass` indices), changed as rules apply.
  final Uint8List classes;

  /// The original classes.
  final Uint8List original;

  final Int32List? codePoints;

  /// The resolved levels.
  final Uint8List levels;

  /// The paragraph embedding level.
  late final int level;

  /// The index of each isolate initiator's matching PDI, and of each
  /// PDI's initiator (-1: none; BD9).
  late final Int32List _matching = Int32List(classes.length)
    ..fillRange(0, classes.length, -1);

  static bool _isIsolateInitiator(int c) =>
      c == BidiClass.lri.index ||
      c == BidiClass.rli.index ||
      c == BidiClass.fsi.index;

  static bool _isRemovedByX9(int c) =>
      c == BidiClass.lre.index ||
      c == BidiClass.rle.index ||
      c == BidiClass.lro.index ||
      c == BidiClass.rlo.index ||
      c == BidiClass.pdf.index ||
      c == BidiClass.bn.index;

  /// The level the first strong character from [start] to [end] gives,
  /// characters between an isolate initiator and its matching PDI passed
  /// over (P2); with [isolate], stopping at an unmatched PDI. Null without
  /// one.
  int? _firstStrong(int start, int end, {required bool isolate}) {
    var depth = 0;
    for (var i = start; i < end; i++) {
      final c = original[i];
      if (_isIsolateInitiator(c)) {
        depth++;
      } else if (c == BidiClass.pdi.index) {
        if (depth > 0) {
          depth--;
        } else if (isolate) {
          return null;
        }
      } else if (depth == 0) {
        if (c == BidiClass.l.index) return 0;
        if (c == BidiClass.r.index || c == BidiClass.al.index) return 1;
      }
      if (c == BidiClass.b.index) break;
    }
    return null;
  }

  /// BD9: each isolate initiator's matching PDI.
  void _matchIsolates() {
    final stack = <int>[];
    for (var i = 0; i < original.length; i++) {
      final c = original[i];
      if (_isIsolateInitiator(c)) {
        stack.add(i);
      } else if (c == BidiClass.pdi.index && stack.isNotEmpty) {
        final opener = stack.removeLast();
        _matching[opener] = i;
        _matching[i] = opener;
      } else if (c == BidiClass.b.index) {
        stack.clear();
      }
    }
  }

  /// Rules X1 to X8: the explicit levels and directional overrides.
  void _explicit() {
    // The directional status stack: each entry's level, override (-1
    // none, else the class index) and isolate status.
    final stackLevel = <int>[level];
    final stackOverride = <int>[-1];
    final stackIsolate = <bool>[false];
    var overflowIsolates = 0;
    var overflowEmbeddings = 0;
    var validIsolates = 0;
    for (var i = 0; i < classes.length; i++) {
      final c = original[i];
      final top = stackLevel.last;
      switch (BidiClass.values[c]) {
        case BidiClass.rle ||
            BidiClass.lre ||
            BidiClass.rlo ||
            BidiClass.lro ||
            BidiClass.rli ||
            BidiClass.lri ||
            BidiClass.fsi:
          final isolate = _isIsolateInitiator(c);
          var rtl =
              c == BidiClass.rle.index ||
              c == BidiClass.rlo.index ||
              c == BidiClass.rli.index;
          if (c == BidiClass.fsi.index) {
            final end = _matching[i] < 0 ? classes.length : _matching[i];
            rtl = _firstStrong(i + 1, end, isolate: true) == 1;
          }
          if (isolate) {
            levels[i] = top;
            if (stackOverride.last >= 0) classes[i] = stackOverride.last;
          }
          final next = rtl ? (top + 1) | 1 : (top + 2) & ~1;
          if (next <= _maxDepth &&
              overflowIsolates == 0 &&
              overflowEmbeddings == 0) {
            if (isolate) validIsolates++;
            stackLevel.add(next);
            stackOverride.add(switch (BidiClass.values[c]) {
              BidiClass.rlo => BidiClass.r.index,
              BidiClass.lro => BidiClass.l.index,
              _ => -1,
            });
            stackIsolate.add(isolate);
            if (!isolate) levels[i] = next;
          } else {
            if (isolate) {
              overflowIsolates++;
            } else if (overflowIsolates == 0) {
              overflowEmbeddings++;
            }
            if (!isolate) levels[i] = top;
          }
        case BidiClass.pdi:
          if (overflowIsolates > 0) {
            overflowIsolates--;
          } else if (validIsolates > 0) {
            overflowEmbeddings = 0;
            while (!stackIsolate.last) {
              stackLevel.removeLast();
              stackOverride.removeLast();
              stackIsolate.removeLast();
            }
            stackLevel.removeLast();
            stackOverride.removeLast();
            stackIsolate.removeLast();
            validIsolates--;
          }
          levels[i] = stackLevel.last;
          if (stackOverride.last >= 0) classes[i] = stackOverride.last;
        case BidiClass.pdf:
          if (overflowIsolates > 0) {
            // nothing
          } else if (overflowEmbeddings > 0) {
            overflowEmbeddings--;
          } else if (!stackIsolate.last && stackLevel.length >= 2) {
            stackLevel.removeLast();
            stackOverride.removeLast();
            stackIsolate.removeLast();
          }
          levels[i] = stackLevel.last;
        case BidiClass.b:
          levels[i] = level;
        case BidiClass.bn:
          levels[i] = top;
        case _:
          levels[i] = top;
          if (stackOverride.last >= 0) classes[i] = stackOverride.last;
      }
    }
  }

  /// The levels the explicit rules (X1 to X8) give, which the boundaries
  /// of isolating run sequences compare (X10).
  late final Uint8List _explicitLevels;

  /// Rule X10: the isolating run sequences, each resolved (W1 to I2).
  void _sequences() {
    _explicitLevels = Uint8List.fromList(levels);
    // The level runs, characters removed by X9 left out.
    final runs = <List<int>>[];
    List<int>? current;
    var currentLevel = -1;
    for (var i = 0; i < classes.length; i++) {
      if (_isRemovedByX9(original[i])) continue;
      if (current == null || levels[i] != currentLevel) {
        current = [];
        runs.add(current);
        currentLevel = levels[i];
      }
      current.add(i);
    }
    // The sequences: a run starting with a PDI that matches an initiator
    // continues the sequence the initiator's run ends.
    final runOf = <int, int>{};
    for (final (r, run) in runs.indexed) {
      for (final i in run) {
        runOf[i] = r;
      }
    }
    final sequences = <List<int>>[];
    for (final run in runs) {
      final first = run.first;
      if (original[first] == BidiClass.pdi.index && _matching[first] >= 0) {
        continue; // continues another sequence
      }
      final sequence = <int>[...run];
      var last = run.last;
      while (_isIsolateInitiator(original[last]) && _matching[last] >= 0) {
        final pdi = _matching[last];
        final next = runs[runOf[pdi]!];
        sequence.addAll(next);
        last = next.last;
      }
      sequences.add(sequence);
    }
    sequences.forEach(_resolve);
  }

  /// The level of the first character before [index] not removed by X9,
  /// or the paragraph's.
  int _levelBefore(int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (!_isRemovedByX9(original[i])) return _explicitLevels[i];
    }
    return level;
  }

  /// The level of the first character after [index] not removed by X9,
  /// or the paragraph's.
  int _levelAfter(int index) {
    for (var i = index + 1; i < classes.length; i++) {
      if (!_isRemovedByX9(original[i])) return _explicitLevels[i];
    }
    return level;
  }

  /// Rules W1 to I2 over one isolating run sequence ([indices] in order).
  void _resolve(List<int> indices) {
    final n = indices.length;
    final runLevel = _explicitLevels[indices.first];
    final first = indices.first;
    final last = indices.last;
    // sos and eos (X10): the higher of the levels on each side.
    final sos = math.max(runLevel, _levelBefore(first)).isOdd
        ? BidiClass.r.index
        : BidiClass.l.index;
    // (After an isolate initiator, which ends a sequence unmatched, the
    // paragraph's level.)
    final eosLevel = _isIsolateInitiator(original[last])
        ? level
        : _levelAfter(last);
    final eos = math.max(runLevel, eosLevel).isOdd
        ? BidiClass.r.index
        : BidiClass.l.index;
    final types = Uint8List(n);
    for (var k = 0; k < n; k++) {
      types[k] = classes[indices[k]];
    }
    final l = BidiClass.l.index;
    final r = BidiClass.r.index;
    final al = BidiClass.al.index;
    final en = BidiClass.en.index;
    final es = BidiClass.es.index;
    final et = BidiClass.et.index;
    final an = BidiClass.an.index;
    final cs = BidiClass.cs.index;
    final nsm = BidiClass.nsm.index;
    final on = BidiClass.on.index;
    bool isIsolateControl(int c) =>
        c == BidiClass.lri.index ||
        c == BidiClass.rli.index ||
        c == BidiClass.fsi.index ||
        c == BidiClass.pdi.index;

    // W1: NSM takes the type of the character before it (ON after an
    // isolate initiator or PDI; sos at the start).
    for (var k = 0; k < n; k++) {
      if (types[k] != nsm) continue;
      if (k == 0) {
        types[k] = sos;
      } else {
        types[k] = isIsolateControl(types[k - 1]) ? on : types[k - 1];
      }
    }
    // W2: EN after AL (back to the first strong) is AN.
    var lastStrong = sos;
    for (var k = 0; k < n; k++) {
      final t = types[k];
      if (t == l || t == r || t == al) {
        lastStrong = t;
      } else if (t == en && lastStrong == al) {
        types[k] = an;
      }
    }
    // W3: AL is R.
    for (var k = 0; k < n; k++) {
      if (types[k] == al) types[k] = r;
    }
    // W4: a single ES between ENs is EN; a single CS between numbers of
    // the same type is that type.
    for (var k = 1; k < n - 1; k++) {
      final t = types[k];
      if (t == es && types[k - 1] == en && types[k + 1] == en) {
        types[k] = en;
      } else if (t == cs) {
        final before = types[k - 1];
        if (before == types[k + 1] && (before == en || before == an)) {
          types[k] = before;
        }
      }
    }
    // W5: ETs next to EN are EN.
    for (var k = 0; k < n; k++) {
      if (types[k] != et) continue;
      var end = k;
      while (end < n && types[end] == et) {
        end++;
      }
      final touches =
          (k > 0 && types[k - 1] == en) || (end < n && types[end] == en);
      if (touches) types.fillRange(k, end, en);
      k = end - 1;
    }
    // W6: the remaining separators and terminators are ON.
    for (var k = 0; k < n; k++) {
      final t = types[k];
      if (t == es || t == et || t == cs) types[k] = on;
    }
    // W7: EN after L (back to the first strong, or sos) is L.
    lastStrong = sos;
    for (var k = 0; k < n; k++) {
      final t = types[k];
      if (t == l || t == r) {
        lastStrong = t;
      } else if (t == en && lastStrong == l) {
        types[k] = l;
      }
    }
    // N0: bracket pairs.
    _brackets(indices, types, sos, runLevel);
    // N1, N2: sequences of neutrals take the direction of the strong text
    // around them when both sides agree (numbers counting as R), else the
    // embedding direction.
    bool isNeutral(int t) =>
        t == BidiClass.b.index ||
        t == BidiClass.s.index ||
        t == BidiClass.ws.index ||
        t == on ||
        isIsolateControl(t);
    final embedding = runLevel.isOdd ? r : l;
    for (var k = 0; k < n; k++) {
      if (!isNeutral(types[k])) continue;
      var end = k;
      while (end < n && isNeutral(types[end])) {
        end++;
      }
      int strongOf(int t) => t == en || t == an ? r : t;
      final before = k == 0 ? sos : strongOf(types[k - 1]);
      final after = end == n ? eos : strongOf(types[end]);
      final value = before == after ? before : embedding;
      types.fillRange(k, end, value);
      k = end - 1;
    }
    // I1, I2: the levels.
    for (var k = 0; k < n; k++) {
      final t = types[k];
      final i = indices[k];
      if (runLevel.isEven) {
        if (t == r) {
          levels[i] = runLevel + 1;
        } else if (t == an || t == en) {
          levels[i] = runLevel + 2;
        }
      } else if (t == l || t == en || t == an) {
        levels[i] = runLevel + 1;
      }
    }
  }

  /// Rule N0: each bracket pair (BD16) takes the embedding direction when
  /// strong text of it is inside, else the direction of the strong text
  /// before it when that is opposite and inside is too, and the marks
  /// after a bracket follow it.
  void _brackets(List<int> indices, Uint8List types, int sos, int runLevel) {
    final points = codePoints;
    if (points == null) return;
    final n = indices.length;
    final on = BidiClass.on.index;
    final l = BidiClass.l.index;
    final r = BidiClass.r.index;
    final en = BidiClass.en.index;
    final an = BidiClass.an.index;
    // BD16: the pairs, from a stack of 63 openers.
    final pairs = <(int, int)>[];
    final stack = <(int, int)>[]; // (closing bracket, position)
    for (var k = 0; k < n; k++) {
      if (types[k] != on) continue;
      final c = points[indices[k]];
      final type = _property(c) >> 8 & 3;
      if (type == 1) {
        if (stack.length == 63) break;
        stack.add((_bracketPairs[c]!, k));
      } else if (type == 2) {
        // (U+2329/232A and U+3008/3009 are canonical equivalents.)
        int canonical(int x) => switch (x) {
          0x2329 => 0x3008,
          0x232a => 0x3009,
          _ => x,
        };
        for (var s = stack.length - 1; s >= 0; s--) {
          if (canonical(stack[s].$1) == canonical(c)) {
            pairs.add((stack[s].$2, k));
            stack.length = s;
            break;
          }
        }
      }
    }
    pairs.sort((a, b) => a.$1 - b.$1);
    final embedding = runLevel.isOdd ? r : l;
    int strongOf(int t) => t == en || t == an ? r : t;
    for (final (open, close) in pairs) {
      // Strong types inside.
      var found = -1;
      var opposite = false;
      for (var k = open + 1; k < close; k++) {
        final t = strongOf(types[k]);
        if (t == embedding) {
          found = t;
          break;
        }
        if (t == l || t == r) opposite = true;
      }
      int? value;
      if (found >= 0) {
        value = embedding;
      } else if (opposite) {
        // The strong type before the opening bracket.
        var before = sos;
        for (var k = open - 1; k >= 0; k--) {
          final t = strongOf(types[k]);
          if (t == l || t == r) {
            before = t;
            break;
          }
        }
        value = before != embedding ? before : embedding;
      }
      if (value == null) continue;
      types[open] = value;
      types[close] = value;
      // The NSMs after each bracket (originally) take its type.
      for (final b in [open, close]) {
        for (var k = b + 1; k < n; k++) {
          if (original[indices[k]] == BidiClass.nsm.index) {
            types[k] = value;
          } else {
            break;
          }
        }
      }
    }
  }

  /// Explicit formatting characters and boundary neutrals (removed by X9)
  /// take the level of the character before them, the paragraph's at its
  /// start.
  void _resolveFormatting() {
    for (var i = 0; i < classes.length; i++) {
      if (!_isRemovedByX9(original[i])) continue;
      levels[i] = i == 0 ? level : levels[i - 1];
    }
  }
}
