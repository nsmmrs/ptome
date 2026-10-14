/// Full Unicode case mapping (The Unicode Standard, section 3.13), the same
/// on every platform: the Dart VM's own tables are older and lack the
/// special mappings, and JavaScript's apply the Final_Sigma rule.
library;

import 'package:plain_unicode/src/bidi.dart' show canonicalCombiningClass;
import 'package:plain_unicode/src/case_data.g.dart';

/// [text] in upper case: each code point's full mapping, such as `ß` to
/// `SS` (as Ruby's `String#upcase` and JavaScript's `toUpperCase` do).
///
/// With [language] (BCP 47), its tailoring in SpecialCasing.txt applies:
/// Turkish and Azeri `i` to `İ`; Lithuanian removes a combining dot
/// above after a soft-dotted letter (`i̇` to `I`).
String upperCase(String text, {String? language}) {
  switch (_tailoring(language)) {
    case _Tailoring.turkic:
      return _map(text.replaceAll('i', '\u0130'), _upper, upper: true);
    case _Tailoring.lithuanian when text.contains('\u0307'):
      final runes = text.runes.toList();
      final out = StringBuffer();
      for (var i = 0; i < runes.length; i++) {
        if (runes[i] == 0x307 && _afterSoftDotted(runes, i)) continue;
        _write(out, runes[i], _upper, upper: true);
      }
      return out.toString();
    case _:
      return _isAscii(text)
          ? text.toUpperCase()
          : _map(text, _upper, upper: true);
  }
}

/// The languages SpecialCasing.txt tailors.
enum _Tailoring { none, turkic, lithuanian }

_Tailoring _tailoring(String? language) {
  final primary = (language ?? '').toLowerCase().split(RegExp('[-_]')).first;
  return switch (primary) {
    'tr' || 'az' => _Tailoring.turkic,
    'lt' => _Tailoring.lithuanian,
    _ => _Tailoring.none,
  };
}

/// The index of the first code point of combining class 0 or 230 (above)
/// from `runes[from]` walking [step] (1 or -1), or null: what case
/// contexts look past (the classes between are neither).
int? _neighbour(List<int> runes, int from, int step) {
  for (var i = from + step; i >= 0 && i < runes.length; i += step) {
    final ccc = canonicalCombiningClass(runes[i]);
    if (ccc == 0 || ccc == 230) return i;
  }
  return null;
}

/// After_Soft_Dotted: a Soft_Dotted letter before, no character of class
/// 0 or 230 between.
bool _afterSoftDotted(List<int> runes, int index) {
  final i = _neighbour(runes, index, -1);
  return i != null && _in(_softDotted, runes[i]);
}

/// More_Above: a character of class 230 after, none of class 0 between.
bool _moreAbove(List<int> runes, int index) {
  for (var i = index + 1; i < runes.length; i++) {
    final ccc = canonicalCombiningClass(runes[i]);
    if (ccc == 230) return true;
    if (ccc == 0) return false;
  }
  return false;
}

/// After_I: a capital I before, no character of class 0 or 230 between.
bool _afterI(List<int> runes, int index) {
  final i = _neighbour(runes, index, -1);
  return i != null && runes[i] == 0x49;
}

/// Before_Dot: a combining dot above after, no character of class 0 or
/// 230 between.
bool _beforeDot(List<int> runes, int index) {
  final i = _neighbour(runes, index, 1);
  return i != null && runes[i] == 0x307;
}

/// [runes] in lower case as [tailoring] has it, the Final_Sigma rule
/// applied with [finalSigma].
String _lowerTailored(
  List<int> runes,
  _Tailoring tailoring, {
  required bool finalSigma,
}) {
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (tailoring == _Tailoring.turkic) {
      if (rune == 0x130) {
        out.write('i');
        continue;
      }
      if (rune == 0x307 && _afterI(runes, i)) continue;
      if (rune == 0x49) {
        out.write(_beforeDot(runes, i) ? 'i' : '\u0131');
        continue;
      }
    } else if (tailoring == _Tailoring.lithuanian) {
      final dotted = switch (rune) {
        0x49 when _moreAbove(runes, i) => 'i\u0307',
        0x4a when _moreAbove(runes, i) => 'j\u0307',
        0x12e when _moreAbove(runes, i) => '\u012f\u0307',
        0xcc => 'i\u0307\u0300',
        0xcd => 'i\u0307\u0301',
        0x128 => 'i\u0307\u0303',
        _ => null,
      };
      if (dotted != null) {
        out.write(dotted);
        continue;
      }
    }
    if (rune == 0x3a3 && finalSigma) {
      out.write(_isFinalSigma(runes, i) ? 'ς' : 'σ');
    } else {
      _write(out, rune, _lower, upper: false);
    }
  }
  return out.toString();
}

/// [text] in lower case: each code point's full mapping, such as `İ` to
/// `i̇`. With [finalSigma], a capital sigma that ends a word becomes `ς`
/// (Unicode's Final_Sigma context, as JavaScript's `toLowerCase` does);
/// without it, every capital sigma becomes `σ` (as Ruby's
/// `String#downcase` does).
///
/// With [language] (BCP 47), its tailoring in SpecialCasing.txt applies:
/// Turkish and Azeri `I` to `ı` and `İ` to `i`; Lithuanian keeps the dot
/// of `i` and `j` under an accent (`Ì` to `i̇̀`).
String lowerCase(String text, {bool finalSigma = false, String? language}) {
  final tailoring = _tailoring(language);
  if (tailoring != _Tailoring.none) {
    return _lowerTailored(
      text.runes.toList(),
      tailoring,
      finalSigma: finalSigma,
    );
  }
  if (_isAscii(text)) return text.toLowerCase();
  if (!finalSigma || !text.contains('Σ')) {
    return _map(text, _lower, upper: false);
  }
  final runes = text.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune == 0x3a3) {
      out.write(_isFinalSigma(runes, i) ? 'ς' : 'σ');
    } else {
      _write(out, rune, _lower, upper: false);
    }
  }
  return out.toString();
}

/// Whether [rune] is Cased (it has a case, or is a letter with a case
/// property).
bool isCased(int rune) => _in(_cased, rune);

/// Whether [rune] is Case_Ignorable (marks, format characters, modifier
/// letters and the like, skipped by case contexts).
bool isCaseIgnorable(int rune) => _in(_caseIgnorable, rune);

final Map<int, String> _upper = _parse(upperTable);
final Map<int, String> _lower = _parse(lowerTable);
final List<int> _cased = _parseRanges(casedRanges);
final List<int> _caseIgnorable = _parseRanges(caseIgnorableRanges);
final List<int> _softDotted = _parseRanges(softDottedRanges);

bool _isAscii(String text) {
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) >= 0x80) return false;
  }
  return true;
}

String _map(String text, Map<int, String> table, {required bool upper}) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    _write(out, rune, table, upper: upper);
  }
  return out.toString();
}

void _write(
  StringBuffer out,
  int rune,
  Map<int, String> table, {
  required bool upper,
}) {
  if (rune < 0x80) {
    final isLower = rune >= 0x61 && rune <= 0x7a;
    final isUpper = rune >= 0x41 && rune <= 0x5a;
    out.writeCharCode(
      upper && isLower
          ? rune - 32
          : !upper && isUpper
          ? rune + 32
          : rune,
    );
    return;
  }
  final mapped = table[rune];
  if (mapped == null) {
    out.writeCharCode(rune);
  } else {
    out.write(mapped);
  }
}

/// Final_Sigma: a cased letter before (case-ignorable ones skipped), and
/// none after.
bool _isFinalSigma(List<int> runes, int index) {
  var before = false;
  for (var i = index - 1; i >= 0; i--) {
    if (isCaseIgnorable(runes[i])) continue;
    before = isCased(runes[i]);
    break;
  }
  if (!before) return false;
  for (var i = index + 1; i < runes.length; i++) {
    if (isCaseIgnorable(runes[i])) continue;
    return !isCased(runes[i]);
  }
  return true;
}

/// A generated mapping table: runs (`start:delta:count:stride`) and
/// mappings to several code points (`cp=mapped mapped`), in base 36.
Map<int, String> _parse(String table) {
  final map = <int, String>{};
  for (final entry in table.split(',')) {
    if (entry.split('=') case [final cp, final mapped]) {
      map[int.parse(cp, radix: 36)] = String.fromCharCodes([
        for (final c in mapped.split(' ')) int.parse(c, radix: 36),
      ]);
    } else if (entry.split(':') case [
      final start,
      final delta,
      final count,
      final stride,
    ]) {
      final first = int.parse(start, radix: 36);
      final offset = int.parse(delta, radix: 36);
      final step = int.parse(stride);
      for (var i = 0; i < int.parse(count, radix: 36); i++) {
        final cp = first + i * step;
        map[cp] = String.fromCharCode(cp + offset);
      }
    }
  }
  return map;
}

/// Generated ranges (`start-end,...`, base 36) as a flat sorted list.
List<int> _parseRanges(String ranges) => [
  for (final range in ranges.split(','))
    for (final end in range.split('-')) int.parse(end, radix: 36),
];

/// Whether [rune] is in the flat range list [ranges] (binary search).
bool _in(List<int> ranges, int rune) {
  var lo = 0;
  var hi = ranges.length ~/ 2 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (rune < ranges[2 * mid]) {
      hi = mid - 1;
    } else if (rune > ranges[2 * mid + 1]) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}
