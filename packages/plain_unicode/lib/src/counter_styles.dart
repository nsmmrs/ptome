/// Counter styles: how a list item's number, a section's or a page's is
/// written in a script's numerals or letters, as CSS Counter Styles
/// Level 3 defines them (its predefined styles, its longhand Chinese and
/// Ethiopic algorithms, section 7) with the W3C's Ready-made Counter
/// Styles for the names CSS doesn't define; and the numbering system a
/// language writes its numbers in by default, CLDR's (48.2).
library;

import 'package:plain_unicode/src/quotation_marks.dart' show cldrLocales;

part 'counter_styles.g.dart';

/// How a counter style's symbols make a representation (CSS Counter
/// Styles 3, 3.1).
enum _System {
  cyclic,
  numeric,
  alphabetic,
  symbolic,
  additive,
  fixed,
  extension,
}

/// A `@counter-style` rule's descriptors, as written.
final class _Rule {
  const new(
    this.system, {
    this.extended,
    this.first = 1,
    this.symbols = const [],
    this.additive = const [],
    this.prefix,
    this.suffix,
    this.negative,
    this.negativeEnd,
    this.range,
    this.pad,
    this.fallback,
  });

  final _System system;
  final String? extended;
  final int first;
  final List<String> symbols;
  final List<(int, String)> additive;
  final String? prefix;
  final String? suffix;
  final String? negative;
  final String? negativeEnd;
  final (int?, int?)? range;
  final (int, String)? pad;
  final String? fallback;
}

/// The longhand Chinese styles' characters (CSS Counter Styles 3, 7.1.3):
/// the digits 0 to 9, the markers of tens, hundreds and thousands, and
/// the negative sign.
const Map<String, (String, String, String)> _chinese = {
  'simp-chinese-informal': ('零一二三四五六七八九', '十百千', '负'),
  'simp-chinese-formal': ('零壹贰叁肆伍陆柒捌玖', '拾佰仟', '负'),
  'trad-chinese-informal': ('零一二三四五六七八九', '十百千', '負'),
  'trad-chinese-formal': ('零壹貳參肆伍陸柒捌玖', '拾佰仟', '負'),
  'cjk-ideographic': ('零一二三四五六七八九', '十百千', '負'),
};

/// A counter style: [format] writes a number in it, [marker] as a list
/// item's marker (with its [prefix] and [suffix]).
final class CounterStyle {
  new _(this.name, this._rule, this._algorithm);

  /// The style CSS (or the Ready-made Counter Styles) names [name]
  /// (`decimal`, `lower-roman`, `arabic-indic`, `hiragana`,
  /// `cjk-ideographic`, `hebrew`...; ASCII case-insensitive), or null for
  /// a name neither defines.
  static CounterStyle? named(String name) {
    final key = name.trim().toLowerCase();
    if (_cache[key] case final style?) return style;
    final _Rule? rule;
    if (_chinese.containsKey(key)) {
      rule = const _Rule(
        _System.additive,
        suffix: '、',
        range: (-9999, 9999),
        fallback: 'cjk-decimal',
      );
    } else if (key == 'ethiopic-numeric') {
      rule = const _Rule(_System.additive, suffix: '/ ', range: (1, null));
    } else {
      rule = _resolve(key, {});
    }
    if (rule == null) return null;
    final algorithm = _chinese.containsKey(key) || key == 'ethiopic-numeric';
    return _cache[key] = CounterStyle._(key, rule, algorithm);
  }

  static final Map<String, CounterStyle> _cache = {};

  /// The numeric style writing numbers in the digits of the numbering
  /// system CLDR calls [id] (`arab`, `deva`...): the predefined style with
  /// those digits (`arabic-indic`, `devanagari`; `decimal` for `latn`),
  /// else one named `numbering-<id>`; null for an id CLDR has no numeric
  /// system for.
  static CounterStyle? forNumberingSystem(String id) {
    final key = id.trim().toLowerCase();
    final digits = _numberingSystems[key];
    if (digits == null) return null;
    final symbols = [
      for (final rune in digits.runes) String.fromCharCode(rune),
    ];
    bool same(_Rule rule) =>
        rule.system == _System.numeric &&
        rule.prefix == null &&
        rule.suffix == null &&
        rule.symbols.length == 10 &&
        Iterable<int>.generate(10).every((i) => rule.symbols[i] == symbols[i]);
    String? match;
    for (final MapEntry(key: name, value: rule) in _rules.entries) {
      if (!same(rule)) continue;
      if (match == null || (_css3.contains(name) && !_css3.contains(match))) {
        match = name;
      }
    }
    if (match != null) return named(match);
    final name = 'numbering-$key';
    return _cache[name] ??= CounterStyle._(
      name,
      _Rule(_System.numeric, symbols: symbols),
      false,
    );
  }

  /// Whether CSS Counter Styles 3 predefines the style (section 7's
  /// algorithms too), so a browser knows it by name; for the others,
  /// [cssRule] defines it.
  bool get predefined => _algorithm || _css3.contains(name);

  /// The style as a CSS `@counter-style` rule (CSS Counter Styles 3), for
  /// a page whose browser doesn't know it ([predefined]); a style written
  /// by an algorithm (section 7) as its fallback's rule under its name.
  String get cssRule {
    if (_algorithm) {
      return CounterStyle.named(_rule.fallback ?? 'decimal')!.cssRule
          .replaceFirst(
            RegExp(r'^@counter-style [\w-]+'),
            '@counter-style $name',
          );
    }
    String string(String s) {
      final out = StringBuffer('"');
      for (final rune in s.runes) {
        if (rune == 0x22 || rune == 0x5C || rune < 0x20) {
          out.write('\\${rune.toRadixString(16)} ');
        } else {
          out.writeCharCode(rune);
        }
      }
      return '$out"';
    }

    final rule = _rule;
    final system = rule.system == _System.fixed
        ? 'fixed ${rule.first}'
        : rule.system.name;
    final additive = [
      for (final (weight, symbol) in rule.additive) '$weight ${string(symbol)}',
    ];
    final negative = [?rule.negative, ?rule.negativeEnd].map(string);
    final descriptors = [
      'system: $system',
      if (rule.symbols.isNotEmpty)
        'symbols: ${rule.symbols.map(string).join(' ')}',
      if (additive.isNotEmpty) 'additive-symbols: ${additive.join(', ')}',
      if (rule.prefix case final prefix?) 'prefix: ${string(prefix)}',
      if (rule.suffix case final suffix?) 'suffix: ${string(suffix)}',
      if (negative.isNotEmpty) 'negative: ${negative.join(' ')}',
      if (rule.range case (final low, final high))
        'range: ${low ?? 'infinite'} ${high ?? 'infinite'}',
      if (rule.pad case (final length, final symbol))
        'pad: $length ${string(symbol)}',
      if (rule.fallback case final fallback?) 'fallback: $fallback',
    ];
    return '@counter-style $name { ${descriptors.join('; ')}; }';
  }

  /// The names of every style [named] knows, sorted.
  static List<String> get names =>
      ({..._rules.keys, ..._chinese.keys, 'ethiopic-numeric'}.toList()..sort());

  /// The rule [name] with the descriptors of the style it extends filled
  /// in (an `extends` cycle, or a name not defined: null).
  static _Rule? _resolve(String name, Set<String> seen) {
    final rule = _rules[name];
    if (rule == null || !seen.add(name)) return null;
    if (rule.system != _System.extension) return rule;
    final base =
        _resolve(rule.extended!, seen) ??
        // (Extending a style that isn't defined extends decimal.)
        _rules['decimal']!;
    return _Rule(
      base.system,
      first: base.first,
      symbols: base.symbols,
      additive: base.additive,
      prefix: rule.prefix ?? base.prefix,
      suffix: rule.suffix ?? base.suffix,
      negative: rule.negative ?? base.negative,
      negativeEnd: rule.negative != null ? rule.negativeEnd : base.negativeEnd,
      range: rule.range ?? base.range,
      pad: rule.pad ?? base.pad,
      fallback: rule.fallback ?? base.fallback,
    );
  }

  /// The style's name, lower case.
  final String name;

  final _Rule _rule;

  /// Whether the representation is one of section 7's algorithms.
  final bool _algorithm;

  /// What comes before the representation in a marker (none by default).
  String get prefix => _rule.prefix ?? '';

  /// What comes after it in a marker (`. ` by default).
  String get suffix => _rule.suffix ?? '. ';

  /// [value] as a list item's marker: [prefix], the representation,
  /// [suffix], this style's even where a fallback writes the number
  /// (CSS Counter Styles 3, 2).
  String marker(int value) => '$prefix${format(value)}$suffix';

  /// [value] written in this style, without prefix and suffix (in the
  /// fallback style where it is out of the style's range or the style
  /// can't write it).
  String format(int value) {
    if (!_inRange(value)) return _fallbackStyle.format(value);
    final negative = value < 0 && _usesNegative;
    final magnitude = negative ? -value : value;
    final text = _algorithm ? _longhand(magnitude) : _represent(magnitude);
    if (text == null) return _fallbackStyle.format(value);
    var out = text;
    final sign = negative ? (_rule.negative ?? (_chineseOf()?.$3 ?? '-')) : '';
    final signEnd = negative ? (_rule.negativeEnd ?? '') : '';
    if (_rule.pad case (final length, final symbol)) {
      final have = out.runes.length + sign.runes.length + signEnd.runes.length;
      if (have < length) out = symbol * (length - have) + out;
    }
    return '$sign$out$signEnd';
  }

  (String, String, String)? _chineseOf() => _chinese[name];

  CounterStyle get _fallbackStyle =>
      CounterStyle.named(_rule.fallback ?? 'decimal') ??
      CounterStyle.named('decimal')!;

  /// Whether the system writes a negative value with the negative sign.
  bool get _usesNegative => switch (_rule.system) {
    _System.symbolic ||
    _System.alphabetic ||
    _System.numeric ||
    _System.additive => true,
    _ => false,
  };

  /// Whether [value] is in the style's range (its `auto` range by
  /// default: from 1 for alphabetic and symbolic systems, from 0 for
  /// additive ones, any value for the others).
  bool _inRange(int value) {
    final (low, high) =
        _rule.range ??
        switch (_rule.system) {
          _System.alphabetic || _System.symbolic => (1, null),
          _System.additive => (0, null),
          _ => (null, null),
        };
    return (low == null || value >= low) && (high == null || value <= high);
  }

  /// [value] (not negative) in the style's system, or null where the
  /// system can't write it.
  String? _represent(int value) {
    final symbols = _rule.symbols;
    final n = symbols.length;
    switch (_rule.system) {
      case _System.cyclic:
        if (n == 0) return null;
        return symbols[(value - 1) % n];
      case _System.fixed:
        final i = value - _rule.first;
        return i >= 0 && i < n ? symbols[i] : null;
      case _System.symbolic:
        if (n == 0 || value < 1) return null;
        return symbols[(value - 1) % n] * ((value + n - 1) ~/ n);
      case _System.alphabetic:
        if (n < 2 || value < 1) return null;
        final out = <String>[];
        var v = value;
        while (v != 0) {
          v--;
          out.add(symbols[v % n]);
          v ~/= n;
        }
        return out.reversed.join();
      case _System.numeric:
        if (n < 2) return null;
        if (value == 0) return symbols[0];
        final out = <String>[];
        var v = value;
        while (v != 0) {
          out.add(symbols[v % n]);
          v ~/= n;
        }
        return out.reversed.join();
      case _System.additive:
        final tuples = _rule.additive;
        if (value == 0) {
          for (final (weight, symbol) in tuples) {
            if (weight == 0) return symbol;
          }
          return null;
        }
        final out = StringBuffer();
        var v = value;
        for (final (weight, symbol) in tuples) {
          if (weight == 0 || weight > v) continue;
          final reps = v ~/ weight;
          for (var i = 0; i < reps; i++) {
            out.write(symbol);
          }
          v -= reps * weight;
          if (v == 0) return '$out';
        }
        return null;
      case _System.extension:
        return null;
    }
  }

  /// [value] (not negative) by section 7's algorithms: the longhand
  /// Chinese styles (7.1.3) and Ethiopic numerals (7.2).
  String? _longhand(int value) {
    if (_chineseOf() case (final digits, final markers, _)) {
      if (value == 0) return digits[0];
      final decimal = '$value';
      final informal = name.endsWith('informal') || name == 'cjk-ideographic';
      // Each digit with its marker (none for the ones, none on a zero).
      final parts = <(int, String)>[];
      for (var i = 0; i < decimal.length; i++) {
        final digit = decimal.codeUnitAt(i) - 0x30;
        final place = decimal.length - 1 - i;
        parts.add((digit, digit == 0 || place == 0 ? '' : markers[place - 1]));
      }
      // Ten to nineteen, informally: the tens digit dropped, its marker kept.
      if (informal && value >= 10 && value <= 19) {
        parts[0] = (-1, parts[0].$2);
      }
      // Trailing zeros dropped; the zeros left collapsed into one.
      while (parts.length > 1 && parts.last.$1 == 0) {
        parts.removeLast();
      }
      final out = StringBuffer();
      var zero = false;
      for (final (digit, marker) in parts) {
        if (digit == 0) {
          zero = true;
          continue;
        }
        if (zero) out.write(digits[0]);
        zero = false;
        if (digit > 0) out.write(digits[digit]);
        out.write(marker);
      }
      return '$out';
    }
    // Ethiopic.
    if (value < 1) return null;
    if (value == 1) return '፩';
    const tens = '፲፳፴፵፶፷፸፹፺';
    const units = '፩፪፫፬፭፮፯፰፱';
    final groups = <int>[];
    for (var v = value; v > 0; v ~/= 100) {
      groups.add(v % 100);
    }
    final out = StringBuffer();
    for (var index = groups.length - 1; index >= 0; index--) {
      final group = groups[index];
      final drop =
          group == 0 ||
          (index == groups.length - 1 && group == 1) ||
          (index.isOdd && group == 1);
      if (!drop) {
        if (group ~/ 10 > 0) out.write(tens[group ~/ 10 - 1]);
        if (group % 10 > 0) out.write(units[group % 10 - 1]);
      }
      if (index.isOdd && group != 0) out.write('፻');
      if (index.isEven && index != 0) out.write('፼');
    }
    return '$out';
  }

  @override
  String toString() => 'CounterStyle($name)';
}

/// The digits 0 to 9 of the numeric numbering system CLDR calls [id]
/// (`latn`, `arab`, `arabext`, `deva`, `beng`, `thai`, `tibt`,
/// `hanidec`, `fullwide`...), or null for an id CLDR has no numeric
/// system for.
String? numberingSystemDigits(String id) =>
    _numberingSystems[id.trim().toLowerCase()];

/// The numbering system [language] (a BCP 47 tag) writes its numbers in by
/// default, CLDR's `defaultNumberingSystem`: `arab` (Arabic-Indic digits)
/// in Egyptian and Saudi Arabic, `arabext` in Persian, `deva` in Marathi
/// and Nepali, `beng` in Bengali, `mymr` in Burmese; `latn` (0 to 9) for
/// a language whose locale doesn't name another (Arabic as such,
/// Moroccan Arabic, Hindi, Japanese). A `-u-nu-` extension (`ar-u-nu-latn`)
/// chooses one.
String defaultNumberingSystem(String language) {
  final extension = RegExp(
    '-u(?:-[a-z0-9]{3,8})*?-nu-([a-z0-9]{3,8})',
    caseSensitive: false,
  ).firstMatch(language.replaceAll('_', '-'));
  if (extension != null) {
    final id = extension[1]!.toLowerCase();
    if (_numberingSystems.containsKey(id)) return id;
  }
  for (final locale in cldrLocales(language)) {
    if (_defaultNumbering[locale] case final system?) return system;
  }
  return 'latn';
}

/// [value]'s decimal digits in the numbering system [id] (CLDR's; `latn`'s
/// for an id it has no digits for), its sign as `-`.
String formatDigits(int value, String id) {
  final digits = numberingSystemDigits(id);
  final decimal = '$value';
  if (digits == null || id == 'latn') return decimal;
  final glyphs = digits.runes.toList();
  return String.fromCharCodes([
    for (final c in decimal.codeUnits)
      if (c >= 0x30 && c <= 0x39) glyphs[c - 0x30] else c,
  ]);
}
