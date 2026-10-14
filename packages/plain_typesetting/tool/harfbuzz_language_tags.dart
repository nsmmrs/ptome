/// Generates `lib/src/shaping/language_tags.g.dart` from a HarfBuzz 14.6.0
/// source checkout's `src/hb-ot-tag-table.hh` (which HarfBuzz generates
/// from the OpenType language system tag registry and the IANA language
/// subtag registry): the two- and three-letter languages' OpenType
/// language system tags, the three-letter ones never to be used, and the
/// rules of `hb_ot_tags_from_complex_language` for tags of several
/// subtags (Chinese regions and scripts, phonetic variants...), in order.
///
///     dart run tool/harfbuzz_language_tags.dart HARFBUZZ_DIR
library;

import 'dart:io';

final RegExp _tag = RegExp(r"HB_TAG\('(.)','(.)','(.)','(.)'\)|HB_TAG_NONE");

String _tagOf(Match m) =>
    m[0] == 'HB_TAG_NONE' ? '' : '${m[1]}${m[2]}${m[3]}${m[4]}';

/// The text of the C array [name] in [source].
String _array(String source, String name) {
  final start = source.indexOf('$name[] = {');
  if (start < 0) throw StateError('no $name');
  return source.substring(start, source.indexOf('};', start));
}

String _quote(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/harfbuzz_language_tags.dart HARFBUZZ_DIR',
    );
    exit(2);
  }
  final source = File('${args.first}/src/hb-ot-tag-table.hh')
      .readAsStringSync();

  // Pairs: {language, tag} (a language may come several times, in order).
  List<(String, String)> pairs(String name) => [
    for (final line in _array(source, name).split('\n'))
      if (_tag.allMatches(line).toList() case [final a, final b, ...])
        (_tagOf(a).trimRight(), _tagOf(b)),
  ];

  final two = <String, List<String>>{};
  for (final (lang, tag) in pairs('ot_languages2')) {
    (two[lang] ??= []).add(tag);
  }
  final three = {for (final (lang, tag) in pairs('ot_languages3')) lang: tag};
  final blocked = [
    for (final m in _tag.allMatches(_array(source, 'ot_languages3_blocked')))
      _tagOf(m).trimRight(),
  ];
  final values = [
    for (final m in _tag.allMatches(
      _array(source, 'ot_languages3_multi_values'),
    ))
      _tagOf(m),
  ];
  final multi = <String, List<String>>{};
  for (final line in _array(source, 'ot_languages3_multi').split('\n')) {
    final m = RegExp(r"HB_TAG\('(.)','(.)','(.)','(.)'\),\s*(\d+),\s*(\d+)")
        .firstMatch(line);
    if (m == null) continue;
    final offset = int.parse(m[5]!);
    multi['${m[1]}${m[2]}${m[3]}${m[4]}'.trimRight()] = values.sublist(
      offset,
      offset + int.parse(m[6]!),
    );
  }

  // The complex function's rules, in order.
  final fnStart = source.indexOf(
    'hb_ot_tags_from_complex_language (const char',
  );
  final fnEnd = source.indexOf('hb_ot_ambiguous_tag_to_language', fnStart);
  final fn = source.substring(fnStart, fnEnd);
  final rules = StringBuffer();
  var count = 0;
  String? letter;
  final lines = fn.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (RegExp("^case '(.)':").firstMatch(line) case final m?) {
      letter = m[1];
      continue;
    }
    if (line == 'out:') letter = '';
    if (!line.startsWith('if (') ||
        line.startsWith('if (!p') ||
        line.startsWith('if (limit')) {
      continue;
    }
    // The condition, over one or two lines.
    final parts = StringBuffer(line);
    while (!lines[i].trimRight().endsWith(')') ||
        lines[i + 1].trim().startsWith('&&') ||
        lines[i + 1].trim().startsWith('||')) {
      i++;
      parts.write(' ${lines[i].trim()}');
    }
    final condition = parts.toString();
    // The tags, up to the return.
    final tags = <String>[];
    while (!lines[i].contains('return true;')) {
      i++;
      if (lines[i].contains('tags[0] = ') ||
          (lines[i].trim().startsWith('HB_TAG(') &&
              !lines[i].contains('*count'))) {
        tags.addAll(_tag.allMatches(lines[i]).map(_tagOf));
      }
    }
    String c(String pattern) {
      final m = RegExp(pattern).firstMatch(condition);
      if (m == null) throw StateError('unparsed: $condition');
      return m[1]!;
    }

    final String rule;
    if (condition.contains('subtag_matches (p,')) {
      rule = '_LanguageRule.variant(${_quote(c('"([^"]+)"'))}';
    } else if (condition.contains('0 == strcmp')) {
      rule = '_LanguageRule.exact(${_quote(letter! + c('"([^"]+)"'))}';
    } else if (condition.contains('lang_matches')) {
      rule = '_LanguageRule.matches(${_quote(letter! + c('"([^"]+)"'))}';
    } else if (condition.contains('strncmp')) {
      final quoted = RegExp('"([^"]+)"').allMatches(condition).toList();
      rule =
          '_LanguageRule.prefixAndSubtag(${_quote(letter! + quoted[0][1]!)}, '
          '${_quote(quoted[1][1]!)}';
    } else {
      throw StateError('unparsed: $condition');
    }
    rules.writeln("  (const $rule), [${tags.map(_quote).join(', ')}]),");
    count++;
  }

  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln(
      '// Generated by `dart run tool/harfbuzz_language_tags.dart` from',
    )
    ..writeln("// HarfBuzz 14.6.0's src/hb-ot-tag-table.hh (MIT; see")
    ..writeln('// vendor/harfbuzz/COPYING).')
    ..writeln('// dart format off')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln("part of 'language_tags.dart';")
    ..writeln()
    ..writeln(
      '/// The OpenType language system tags of each two-letter language',
    )
    ..writeln('/// (ISO 639-1), in order; none for a language that has none.')
    ..writeln('const Map<String, List<String>> _languages2 = {');
  for (final MapEntry(:key, :value) in two.entries) {
    out.writeln(
      '  ${_quote(key)}: [${[for (final t in value)
        if (t.isNotEmpty) _quote(t)].join(', ')}],',
    );
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// The tag of each three-letter language (ISO 639-2/3) with one.',
    )
    ..writeln('const Map<String, String> _languages3 = {');
  for (final MapEntry(:key, :value) in three.entries) {
    out.writeln('  ${_quote(key)}: ${_quote(value)},');
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// The tags of each three-letter language with several, in order.',
    )
    ..writeln('const Map<String, List<String>> _languages3Multi = {');
  for (final MapEntry(:key, :value) in multi.entries) {
    out.writeln('  ${_quote(key)}: [${value.map(_quote).join(', ')}],');
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln('/// The three-letter languages no tag is made for.')
    ..writeln('const Set<String> _languages3Blocked = {')
    ..writeln('  ${blocked.map(_quote).join(', ')},')
    ..writeln('};')
    ..writeln()
    ..writeln("/// `hb_ot_tags_from_complex_language`'s rules, in order: the")
    ..writeln("/// variants first, then by the language's first letter.")
    ..writeln('final List<(_LanguageRule, List<String>)> _complexRules = [')
    ..write(rules)
    ..writeln('];');
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  File('$root/lib/src/shaping/language_tags.g.dart')
      .writeAsStringSync(out.toString());
  stdout.writeln(
    '${two.length} two-letter, ${three.length} three-letter, '
    '${multi.length} multiple, ${blocked.length} blocked, $count rules',
  );
}
