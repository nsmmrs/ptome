/// The OpenType language system tags of a BCP 47 language tag, as
/// HarfBuzz 14.6 finds them (`hb_ot_tags_from_script_and_language`,
/// `hb-ot-tag.cc`): a tag of several subtags by its rules (a Chinese
/// region or script, a phonetic variant), else its first subtag (or its
/// extended language subtag) in the registry's tables, else a
/// three-letter language upper-cased; `-x-hbot-xxxx` names one outright.
library;

part 'language_tags.g.dart';

/// How a rule of `hb_ot_tags_from_complex_language` matches.
final class _LanguageRule {
  /// The tag is [spec] or begins with it and a hyphen (`lang_matches`).
  const new matches(this.spec) : subtag = null, kind = 0;

  /// The tag, private use included, is [spec] exactly (`strcmp`).
  const new exact(this.spec) : subtag = null, kind = 1;

  /// The tag begins with [spec] and has the subtag [subtag] before its
  /// private use (`strncmp` and `subtag_matches`).
  const new prefixAndSubtag(this.spec, String this.subtag) : kind = 2;

  /// A subtag after the first is [spec] (`subtag_matches` from the first
  /// hyphen).
  const new variant(this.spec) : subtag = null, kind = 3;

  final String spec;
  final String? subtag;
  final int kind;
}

bool _isAlnum(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x61 && c <= 0x7a) ||
    (c >= 0x41 && c <= 0x5a);

bool _isAlpha(int c) => (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a);

/// Whether [subtag] (with its hyphen) comes in [s] between [from] and
/// [limit], a subtag whole (HarfBuzz's `subtag_matches`).
bool _subtagMatches(String s, int from, int limit, String subtag) {
  if (limit - from < subtag.length) return false;
  var at = from;
  while (true) {
    final i = s.indexOf(subtag, at);
    if (i < 0 || i >= limit) return false;
    final after = i + subtag.length;
    if (after >= s.length || !_isAlnum(s.codeUnitAt(after))) return true;
    at = after;
  }
}

/// Whether [s] from [from] is [spec], or [spec] and a hyphen (HarfBuzz's
/// `lang_matches`).
bool _langMatches(String s, int from, int limit, String spec) {
  if (limit - from < spec.length) return false;
  if (!s.startsWith(spec, from)) return false;
  final after = from + spec.length;
  return after >= s.length || s.codeUnitAt(after) == 0x2d;
}

/// The tags `hb_ot_tags_from_complex_language` gives [s] (up to [limit]),
/// or null.
List<String>? _complex(String s, int limit) {
  final dash = s.indexOf('-');
  final variants = limit >= 7 && dash >= 0 && dash < limit && limit - dash >= 5;
  for (final (rule, tags) in _complexRules) {
    final matched = switch (rule.kind) {
      3 => variants && _subtagMatches(s, dash, limit, rule.spec),
      1 => s == rule.spec,
      0 => _langMatches(s, 0, limit, rule.spec),
      _ => s.startsWith(rule.spec) && _subtagMatches(s, 0, limit, rule.subtag!),
    };
    if (matched) return tags;
  }
  return null;
}

/// The private use subtag's tag after [prefix] (`-hbot`: a language
/// system, upper case), or null.
String? _privateUse(String? privateUse, String prefix) {
  if (privateUse == null) return null;
  final i = privateUse.indexOf(prefix);
  if (i < 0) return null;
  var s = i + prefix.length;
  if (s < privateUse.length && privateUse.codeUnitAt(s) == 0x2d) {
    s++;
    final hex = RegExp('^[0-9a-fA-F]{8}').firstMatch(privateUse.substring(s));
    if (hex == null) return null;
    return String.fromCharCodes([
      for (var k = 0; k < 8; k += 2)
        int.parse(hex[0]!.substring(k, k + 2), radix: 16),
    ]);
  }
  final letters = StringBuffer();
  while (s < privateUse.length &&
      letters.length < 4 &&
      _isAlnum(privateUse.codeUnitAt(s))) {
    letters.write(privateUse[s].toUpperCase());
    s++;
  }
  if (letters.isEmpty) return null;
  final tag = letters.toString().padRight(4);
  // (`DFLT` spelled so is the default language system's tag lower-cased.)
  return tag == 'DFLT' ? 'dflt' : tag;
}

/// The OpenType language system tags of [language] (a BCP 47 tag: `ja`,
/// `zh-Hant-HK`, `sr-Latn`), best first, as HarfBuzz gives them; none
/// for a language without one.
List<String> openTypeLanguageTags(String language) {
  // (HarfBuzz's canonical form: lower case, hyphens.)
  final s = language.trim().toLowerCase().replaceAll('_', '-');
  if (s.isEmpty) return const [];
  String? privateUse;
  var limit = s.length;
  if (s.startsWith('x-')) {
    privateUse = s;
  } else {
    int? found;
    for (var i = 1; i + 1 < s.length; i++) {
      if (s.codeUnitAt(i - 1) == 0x2d && s.codeUnitAt(i + 1) == 0x2d) {
        if (s.codeUnitAt(i) == 0x78) {
          privateUse = s.substring(i);
          found ??= i - 1;
          break;
        }
        found ??= i - 1;
      }
    }
    limit = found ?? s.length;
  }
  if (_privateUse(privateUse, '-hbot') case final tag?) return [tag];
  if (privateUse == s) return const [];
  return _fromLanguage(s, limit);
}

List<String> _fromLanguage(String whole, int limit) {
  if (_complex(whole, limit) case final tags?) return tags;
  var s = whole;
  var end = limit;
  // An extended language subtag stands for the language.
  final dash = s.indexOf('-');
  if (dash >= 0 && limit >= 6) {
    final next = s.indexOf('-', dash + 1);
    final length = (next >= 0 ? next : s.length) - dash - 1;
    if (length == 3 && _isAlpha(s.codeUnitAt(dash + 1))) {
      end -= dash + 1;
      s = s.substring(dash + 1);
    }
  }
  final firstDash = s.indexOf('-');
  final first = s.substring(0, firstDash >= 0 ? firstDash : end);
  if (first.length == 2) {
    if (_languages2[first] case final tags?) return tags;
  } else if (first.length == 3) {
    if (_languages3[first] case final tag?) return [tag];
    if (_languages3Multi[first] case final tags?) return tags;
    if (_languages3Blocked.contains(first)) return const [];
    return [first.toUpperCase().padRight(4)];
  }
  // (A first subtag of three letters, by the whole tag's.)
  final firstOfWhole = whole.split('-').first;
  if (firstOfWhole.length == 3) return [firstOfWhole.toUpperCase().padRight(4)];
  return const [];
}
