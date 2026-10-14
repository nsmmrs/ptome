/// Word boundaries in the scripts written without spaces between words
/// (Thai, Lao, Khmer, Myanmar), found as ICU 78.3's dictionary break
/// engines find them (`dictbe.cpp`, under the Unicode License: see
/// `vendor/icu/LICENSE`): at each place the dictionary words that start
/// there, the one chosen that lets the most words follow (looking three
/// ahead), what no word starts with joined to the word before, a word
/// never ended before a combining mark.
library;

import 'dart:convert';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_unicode/src/dictionaries.g.dart';
import 'package:plain_unicode/src/line_break.dart';
import 'package:plain_unicode/src/properties.dart';

/// A dictionary of words, sorted for prefix searches (ICU's trie, as a
/// sorted list: the same answers).
final class _Dictionary {
  new(this.words) : _set = words.toSet();

  final List<String> words;
  final Set<String> _set;

  /// The index of the first word not before [s].
  int _lowerBound(String s) {
    var lo = 0;
    var hi = words.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (words[mid].compareTo(s) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The words that are prefixes of [text] from [start], at most
  /// [maxLength] long: their lengths, in increasing order (at most 20);
  /// and the number of characters ICU's matcher read (HarfBuzz's
  /// `UCharsDictionaryMatcher::matches`: the one that matched no word's
  /// start counted).
  (List<int>, int) matches(String text, int start, int maxLength) {
    final lengths = <int>[];
    var read = 0;
    for (var i = start; i < text.length; i++) {
      read++;
      final length = i - start + 1;
      final candidate = text.substring(start, i + 1);
      final at = _lowerBound(candidate);
      final hasPrefix = at < words.length && words[at].startsWith(candidate);
      if (!hasPrefix) break;
      if (_set.contains(candidate)) {
        if (lengths.length < 20) lengths.add(length);
        // (A word no other extends: the trie's final value.)
        final longer =
            at + 1 < words.length && words[at + 1].startsWith(candidate);
        if (!longer) break;
      }
      if (length >= maxLength) break;
    }
    return (lengths, read);
  }
}

final Map<String, _Dictionary> _dictionaries = {};

_Dictionary? _dictionaryOf(String script) {
  final encoded = dictionaries[script];
  if (encoded == null) return null;
  return _dictionaries[script] ??= _Dictionary(
    utf8
        .decode(brotliDecode(base64.decode(encoded)))
        .split('\n')
        .where((w) => w.isNotEmpty)
        .toList()
      ..sort(),
  );
}

/// What a script's engine knows of its characters.
final class _Engine {
  const new({
    required this.script,
    required this.isEndWord,
    required this.isBeginWord,
    this.thaiSuffixes = false,
  });

  final String script;
  final bool Function(int c) isEndWord;
  final bool Function(int c) isBeginWord;
  final bool thaiSuffixes;
}

bool _inWordSet(int c, String script) =>
    lineBreakClass(c) == LineBreakClass.sa && scriptOf(c) == script;

final Map<String, _Engine> _engines = {
  'Thai': _Engine(
    script: 'Thai',
    isEndWord: (c) =>
        _inWordSet(c, 'Thai') && c != 0x0e31 && !(c >= 0x0e40 && c <= 0x0e44),
    isBeginWord: (c) =>
        (c >= 0x0e01 && c <= 0x0e2e) || (c >= 0x0e40 && c <= 0x0e44),
    thaiSuffixes: true,
  ),
  'Laoo': _Engine(
    script: 'Laoo',
    isEndWord: (c) => _inWordSet(c, 'Laoo') && !(c >= 0x0ec0 && c <= 0x0ec4),
    isBeginWord: (c) =>
        (c >= 0x0e81 && c <= 0x0eae) ||
        (c >= 0x0edc && c <= 0x0edd) ||
        (c >= 0x0ec0 && c <= 0x0ec4),
  ),
  'Khmr': _Engine(
    script: 'Khmr',
    isEndWord: (c) => _inWordSet(c, 'Khmr') && c != 0x17d2,
    isBeginWord: (c) => c >= 0x1780 && c <= 0x17b3,
  ),
  'Mymr': _Engine(
    script: 'Mymr',
    isEndWord: (c) => _inWordSet(c, 'Mymr'),
    isBeginWord: (c) => c >= 0x1000 && c <= 0x102a,
  ),
};

/// ICU's `PossibleWord`: the dictionary words at a place, the longest
/// first, one of them marked.
final class _PossibleWord {
  List<int> _lengths = const [];
  int _prefix = 0;
  int _offset = -1;
  int _mark = 0;
  int _current = 0;

  /// The candidates at [at] (found once per place), the longest marked;
  /// the position after it, or [at] when there is none.
  (int, int) candidates(String text, _Dictionary dict, int at, int end) {
    if (at != _offset) {
      _offset = at;
      final (lengths, prefix) = dict.matches(text, at, end - at);
      _lengths = lengths;
      _prefix = prefix;
    }
    final count = _lengths.length;
    _current = count - 1;
    _mark = _current;
    return (count, count > 0 ? at + _lengths[count - 1] : at);
  }

  int acceptMarked() => _lengths[_mark];

  /// The position after the next shorter candidate, or -1.
  int backUp() => _current > 0 ? _offset + _lengths[--_current] : -1;

  int get longestPrefix => _prefix;

  void markCurrent() => _mark = _current;

  int get markedLength => _lengths[_mark];
}

const int _lookahead = 3;
const int _rootCombineThreshold = 3;
const int _prefixCombineThreshold = 3;
const int _minWordSpan = 4;
const int _paiyannoi = 0x0e2f;
const int _maiyamok = 0x0e46;

/// The word boundaries ICU's dictionary engine finds in [text] from
/// [rangeStart] to [rangeEnd] (a run of the script's characters), the end
/// left out (`divideUpDictionaryRange`; `pos` is ICU's text position).
List<int> _divide(
  String text,
  int rangeStart,
  int rangeEnd,
  _Engine engine,
  _Dictionary dict,
) {
  final breaks = <int>[];
  // Not enough characters for two words (Thai counts one more).
  final span = rangeEnd - rangeStart;
  if (engine.thaiSuffixes ? span <= _minWordSpan : span < _minWordSpan) {
    return breaks;
  }
  bool isMark(int c) =>
      c == 0x20 ||
      (_inWordSet(c, engine.script) &&
          switch (generalCategory(c)) {
            GeneralCategory.nonspacingMark ||
            GeneralCategory.spacingMark ||
            GeneralCategory.enclosingMark => true,
            _ => false,
          });
  final words = List.generate(_lookahead, (_) => _PossibleWord());
  _PossibleWord at(int n) => words[n % _lookahead];
  var wordsFound = 0;
  var pos = rangeStart;
  while (pos < rangeEnd) {
    final current = pos;
    var wordLength = 0;
    final word = at(wordsFound);
    final (candidates, after) = word.candidates(text, dict, pos, rangeEnd);
    pos = after;
    if (candidates >= 1) {
      // Of several, the one the most words follow.
      if (candidates > 1 && pos < rangeEnd) {
        search:
        do {
          final second = at(wordsFound + 1);
          final (n2, after2) = second.candidates(text, dict, pos, rangeEnd);
          if (n2 > 0) {
            word.markCurrent();
            if (after2 >= rangeEnd) break search;
            var p2 = after2;
            do {
              final (n3, _) = at(wordsFound + 2)
                  .candidates(text, dict, p2, rangeEnd);
              if (n3 > 0) {
                word.markCurrent();
                break search;
              }
              p2 = second.backUp();
            } while (p2 >= 0);
          }
          pos = word.backUp();
        } while (pos >= 0);
      }
      wordLength = word.acceptMarked();
      pos = current + wordLength;
      wordsFound++;
    }

    // A non-word after a short word (or at the start) joined to it, up to
    // a plausible boundary.
    if (pos < rangeEnd && wordLength < _rootCombineThreshold) {
      final next = at(wordsFound);
      final (n, _) = next.candidates(text, dict, pos, rangeEnd);
      if (n <= 0 &&
          (wordLength == 0 || next.longestPrefix < _prefixCombineThreshold)) {
        var remaining = rangeEnd - (current + wordLength);
        var chars = 0;
        while (true) {
          final pc = text.codeUnitAt(pos);
          pos++;
          chars++;
          remaining--;
          if (remaining <= 0) break;
          final uc = text.codeUnitAt(pos);
          if (engine.isEndWord(pc) && engine.isBeginWord(uc)) {
            final (found, _) = at(wordsFound + 1)
                .candidates(text, dict, pos, rangeEnd);
            if (found > 0) break;
          }
        }
        if (wordLength <= 0) wordsFound++;
        wordLength += chars;
      }
      pos = current + wordLength;
    }

    // Never stop before a combining mark.
    while (pos < rangeEnd && isMark(text.codeUnitAt(pos))) {
      pos++;
      wordLength++;
    }

    // Thai: a suffix (PAIYANNOI, MAIYAMOK) where no word follows.
    if (engine.thaiSuffixes && pos < rangeEnd && wordLength > 0) {
      final (n, _) = at(wordsFound).candidates(text, dict, pos, rangeEnd);
      var uc = text.codeUnitAt(pos);
      if (n <= 0 && (uc == _paiyannoi || uc == _maiyamok)) {
        if (uc == _paiyannoi) {
          final previous = text.codeUnitAt(pos - 1);
          if (previous != _paiyannoi && previous != _maiyamok) {
            pos++;
            wordLength++;
            uc = pos < text.length ? text.codeUnitAt(pos) : -1;
          }
        }
        if (uc == _maiyamok && text.codeUnitAt(pos - 1) != _maiyamok) {
          pos++;
          wordLength++;
        }
      } else {
        pos = current + wordLength;
      }
    }

    if (wordLength > 0) breaks.add(current + wordLength);
  }
  if (breaks.isNotEmpty && breaks.last >= rangeEnd) breaks.removeLast();
  return breaks;
}

/// The word boundaries the dictionaries find in [text]'s runs of Thai,
/// Lao, Khmer and Myanmar characters (of line breaking class SA), each
/// strictly inside its run. A run ends at the next of [ruleBreaks] (the
/// offsets the rules break at, in order), as ICU's ranges end at the
/// rules' boundaries: a mark after punctuation is the punctuation's.
List<int> dictionaryBreaks(String text, List<int> ruleBreaks) {
  final out = <int>[];
  var next = 0;
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (lineBreakClass(c) != LineBreakClass.sa) {
      i++;
      continue;
    }
    while (next < ruleBreaks.length && ruleBreaks[next] <= i) {
      next++;
    }
    final limit = next < ruleBreaks.length ? ruleBreaks[next] : text.length;
    final script = scriptOf(c);
    var end = i + 1;
    while (end < limit && _inWordSet(text.codeUnitAt(end), script)) {
      end++;
    }
    if (_engines[script] case final engine?) {
      if (_dictionaryOf(script) case final dict?) {
        out.addAll(_divide(text, i, end, engine, dict));
      }
    }
    i = end;
  }
  final syllables = syllableBreaks(text, ruleBreaks);
  if (syllables.isEmpty) return out;
  return [...out, ...syllables]..sort();
}

/// The scripts written without spaces that no dictionary knows (ICU has
/// none for them, and no word list under a permissive licence is to be
/// had): Tai Tham, New Tai Lue, Tai Viet and Ahom, broken between their
/// orthographic syllables instead.
const Set<String> _syllableScripts = {'Lana', 'Talu', 'Tavt', 'Ahom'};

/// The boundaries between the orthographic syllables of [text]'s runs of
/// Tai Tham, New Tai Lue, Tai Viet and Ahom (of line breaking class SA),
/// each strictly inside its run (which ends at the next of [ruleBreaks]):
/// before each consonant or independent vowel, and before a vowel written
/// before its consonant (New Tai Lue's and Tai Viet's, in visual order);
/// not after such a vowel or Tai Tham's stacker (sakot: the consonant it
/// stacks stays with the one before), nor before a consonant a killer
/// makes the syllable's final.
List<int> syllableBreaks(String text, List<int> ruleBreaks) {
  final out = <int>[];
  final runes = <(int, int)>[];
  for (var i = 0; i < text.length;) {
    final c = text.codeUnitAt(i);
    var rune = c;
    var length = 1;
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
      final low = text.codeUnitAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        rune = 0x10000 + ((c - 0xd800) << 10) + (low - 0xdc00);
        length = 2;
      }
    }
    runes.add((i, rune));
    i += length;
  }
  bool inRun(int rune) =>
      lineBreakClass(rune) == LineBreakClass.sa &&
      _syllableScripts.contains(scriptOf(rune));
  bool prevowel(int rune) =>
      indicPositionalCategory(rune) == IndicPositionalCategory.visualOrderLeft;
  bool begins(int rune) => switch (indicSyllabicCategory(rune)) {
    IndicSyllabicCategory.consonant ||
    IndicSyllabicCategory.vowelIndependent => true,
    IndicSyllabicCategory.vowelDependent => prevowel(rune),
    _ => false,
  };
  bool stacks(int rune) =>
      indicSyllabicCategory(rune) == IndicSyllabicCategory.invisibleStacker;
  var next = 0;
  for (var k = 1; k < runes.length; k++) {
    final (offset, rune) = runes[k];
    final (_, before) = runes[k - 1];
    if (!inRun(rune) || !inRun(before)) continue;
    // (Not across a break of the rules', which ends the run.)
    while (next < ruleBreaks.length && ruleBreaks[next] < offset) {
      next++;
    }
    if (next < ruleBreaks.length && ruleBreaks[next] == offset) continue;
    if (!begins(rune) || prevowel(before) || stacks(before)) continue;
    // (A consonant killed closes the syllable before it.)
    if (indicSyllabicCategory(rune) == IndicSyllabicCategory.consonant &&
        k + 1 < runes.length &&
        indicSyllabicCategory(runes[k + 1].$2) ==
            IndicSyllabicCategory.pureKiller) {
      continue;
    }
    out.add(offset);
  }
  return out;
}
