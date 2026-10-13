/// Port of `src/lib/compile_keywords.js`.
library;

import 'package:plain_highlighting/src/js_string.dart';
import 'package:plain_highlighting/src/mode.dart';

// Keywords that should have no default relevance value.
const Set<String> _commonKeywords = {
  'of',
  'and',
  'for',
  'in',
  'not',
  'or',
  'if',
  'then',
  'parent', // common variable name
  'list', // common variable name
  'value', // common variable name
};

const String _defaultKeywordScope = 'keyword';

/// Compiles the [raw] keywords of a definition: scope and relevance by word,
/// lower-cased when the language is [caseInsensitive].
CompiledKeywords compileKeywords(
  RawKeywords raw, {
  required bool caseInsensitive,
}) {
  final compiled = <String, ({String scope, num relevance})>{};
  for (final group in raw.groups) {
    final scope = group.scope ?? _defaultKeywordScope;
    // (The two relevances a word without its own has, shared by the
    // group's words: a language has thousands.)
    final common = (scope: scope, relevance: 0);
    final other = (scope: scope, relevance: 1);
    for (final word in group.words) {
      final keyword = caseInsensitive ? jsLowerCase(word) : word;
      final bar = keyword.indexOf('|');
      final name = bar < 0 ? keyword : keyword.substring(0, bar);
      // (The rest of the word after a second bar is ignored, as split
      // has it.)
      final score = bar < 0 ? null : keyword.substring(bar + 1).split('|')[0];
      compiled[name] = score != null && score.isNotEmpty
          ? (scope: scope, relevance: jsNumber(score))
          : _isCommon(name)
          ? common
          : other;
    }
  }
  return CompiledKeywords(compiled);
}

/// Whether [keyword] is one of the common words (in any case), which have
/// no relevance by default.
bool _isCommon(String keyword) {
  // (None is longer than six letters, or has a letter beyond ASCII; a
  // word that has one is lowered as JavaScript lowers it.)
  if (keyword.length > 6) {
    for (final unit in keyword.codeUnits) {
      if (unit >= 0x80) return _commonKeywords.contains(jsLowerCase(keyword));
    }
    return false;
  }
  return _commonKeywords.contains(jsLowerCase(keyword));
}
