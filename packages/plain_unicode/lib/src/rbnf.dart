/// CLDR's rule-based number formats (UTS #35, Part 3, 6) for its
/// algorithmic numbering systems: Hebrew numerals (`hebr`: י״ז, תשפ״ז),
/// the first year of a Japanese era as 元 (`jpanyear`), Chinese days of
/// the month (`hanidays`: 初一, 廿五)... For whole numbers: each rule set's
/// rules by base value, a rule's divisor the highest power of its radix
/// not above its base, `<<` the quotient by the divisor and `>>` the
/// remainder (in the rule set named between them, else the same one),
/// `==` the number itself, `[...]` left out on an even multiple of the
/// divisor, and a rule whose base isn't such a multiple giving way to the
/// one before it on one ("rollback").
library;

import 'package:plain_unicode/src/rbnf.g.dart' show rbnfRules, rbnfSystems;

/// [value] in the algorithmic numbering system [system] (CLDR's id:
/// `hebr`, `jpanyear`, `hanidays`), its plain numbers (`=0=`, `=#,##0=`)
/// written by [digits]; null where [system] isn't one CLDR has rules for.
String? formatAlgorithmic(
  int value,
  String system, {
  String Function(int value)? digits,
}) {
  final (source, name) = rbnfSystems[system] ?? (null, null);
  if (source == null || name == null) return null;
  final sets = _parsed[source] ??= _parse(rbnfRules[source]!);
  final set = sets[name];
  if (set == null) return null;
  return _Formatter(sets, digits ?? (n) => '$n').format(set, value);
}

/// Each source's rule sets by name, parsed when first used.
final Map<String, Map<String, _RuleSet>> _parsed = {};

/// A rule: its base value, its divisor, and its text.
final class _Rule {
  new(this.base, this.divisor, this.text);

  final int base;
  final int divisor;
  final String text;
}

/// A rule set: its rules for whole numbers, by base value, and its rule
/// for negative ones.
final class _RuleSet {
  final List<_Rule> rules = [];
  String? negative;
}

/// The rule sets in [text] (CLDR's rule text: `%name:` and its rules,
/// `base: text;`), by name (without the `%` or `%%`).
Map<String, _RuleSet> _parse(String text) {
  final sets = <String, _RuleSet>{};
  _RuleSet? current;
  final statement = StringBuffer();
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (statement.isEmpty && trimmed.startsWith('%') && trimmed.endsWith(':')) {
      final name = trimmed
          .substring(0, trimmed.length - 1)
          .replaceFirst(RegExp('^%+'), '');
      current = sets[name] = _RuleSet();
      continue;
    }
    statement.write(statement.isEmpty ? trimmed : ' $trimmed');
    if (!trimmed.endsWith(';')) continue;
    final rule = '$statement';
    statement.clear();
    final set = current;
    if (set == null) continue;
    final colon = rule.indexOf(':');
    if (colon < 0) continue;
    final descriptor = rule.substring(0, colon).trim();
    var body = rule.substring(colon + 1, rule.length - 1).trim();
    // (A leading apostrophe keeps the spaces after it.)
    if (body.startsWith("'")) body = body.substring(1);
    if (descriptor == '-x') {
      set.negative = body;
      continue;
    }
    final match = RegExp(r'^([0-9,]+)(?:/([0-9]+))?(>*)$')
        .firstMatch(descriptor);
    if (match == null) continue;
    final base = int.parse(match[1]!.replaceAll(',', ''));
    final radix = int.parse(match[2] ?? '10');
    var divisor = 1;
    while (divisor * radix <= base) {
      divisor *= radix;
    }
    // (Each `>` after the base: a power less.)
    for (var i = 0; i < match[3]!.length && divisor > 1; i++) {
      divisor ~/= radix;
    }
    set.rules.add(_Rule(base, divisor, body));
  }
  for (final set in sets.values) {
    set.rules.sort((a, b) => a.base.compareTo(b.base));
  }
  return sets;
}

/// Formats numbers by the rule sets of one source.
final class _Formatter {
  new(this.sets, this.digits);

  final Map<String, _RuleSet> sets;
  final String Function(int value) digits;

  String format(_RuleSet set, int value) {
    if (value < 0) {
      final negative = set.negative;
      if (negative == null) return '-${format(set, -value)}';
      return _apply(negative, set, -value, 1, negativeRule: true);
    }
    final rules = set.rules;
    var index = -1;
    for (var i = 0; i < rules.length; i++) {
      if (rules[i].base <= value) index = i;
    }
    if (index < 0) return digits(value);
    var rule = rules[index];
    // (Rollback: a rule whose base isn't a multiple of its divisor, with
    // a remainder in its text, gives way to the one before it where the
    // number is.)
    if (index > 0 &&
        rule.text.contains('>') &&
        value % rule.divisor == 0 &&
        rule.base % rule.divisor != 0) {
      rule = rules[index - 1];
    }
    return _apply(rule.text, set, value, rule.divisor);
  }

  /// [text] with its substitutions for [value] by [divisor], its optional
  /// parts left out on an even multiple.
  String _apply(
    String text,
    _RuleSet set,
    int value,
    int divisor, {
    bool negativeRule = false,
  }) {
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c == '[') {
        final end = text.indexOf(']', i);
        final inner = text.substring(i + 1, end < 0 ? text.length : end);
        if (negativeRule || value % divisor != 0) {
          out.write(_apply(inner, set, value, divisor));
        }
        i = end < 0 ? text.length : end + 1;
        continue;
      }
      if (c == '<' || c == '>' || c == '=') {
        // (`>>>`: the remainder, as `>>`.)
        var end = text.indexOf(c, i + 1);
        if (end < 0) {
          out.write(c);
          i++;
          continue;
        }
        if (c == '>' && end == i + 1 && text.startsWith('>>>', i)) end = i + 2;
        final inner = text.substring(i + 1, end);
        final n = switch (c) {
          '<' => value ~/ divisor,
          '>' when negativeRule => value,
          '>' => value % divisor,
          _ => value,
        };
        out.write(_substitute(inner, set, n));
        i = end + 1;
        continue;
      }
      out.write(c);
      i++;
    }
    return '$out';
  }

  /// [n] by the substitution's [inner] descriptor: a rule set (`%name`),
  /// a decimal pattern (`0`, `#,##0`: plain digits), or none (the same
  /// rule set).
  String _substitute(String inner, _RuleSet set, int n) {
    if (inner.startsWith('%')) {
      final named = sets[inner.replaceFirst(RegExp('^%+'), '')];
      return named == null ? digits(n) : format(named, n);
    }
    if (inner.contains('0') || inner.contains('#')) return digits(n);
    return format(set, n);
  }
}
