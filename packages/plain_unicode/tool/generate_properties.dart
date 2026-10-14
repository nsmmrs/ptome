/// Generates `lib/src/properties_data.g.dart` from the Unicode Character
/// Database files in `vendor/ucd/18.0.0` (Unicode 18.0.0), for text
/// shaping (the shapers of plain_typesetting, after HarfBuzz's) and
/// vertical layout:
///
/// - each code point's General_Category (DerivedGeneralCategory.txt),
///   Script (Scripts.txt), Indic_Syllabic_Category and
///   Indic_Positional_Category (IndicSyllabicCategory.txt,
///   IndicPositionalCategory.txt), Vertical_Orientation
///   (VerticalOrientation.txt, its `@missing` defaults first),
///   Default_Ignorable_Code_Point (DerivedCoreProperties.txt) and the
///   emoji properties (Emoji, Emoji_Presentation, Emoji_Modifier,
///   Emoji_Modifier_Base, Extended_Pictographic: emoji-data.txt), packed into
///   one value, as a three-stage table over a palette of the distinct
///   values (as `generate_bidi.dart` lays it out);
/// - the canonical decompositions (UnicodeData.txt's decomposition
///   mappings without a tag) and the code points excluded from
///   composition (Full_Composition_Exclusion, DerivedNormalizationProps.txt);
/// - the enumerations of the property values, in PropertyValueAliases.txt's
///   order.
///
/// ```sh
/// dart run tool/generate_properties.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The bit positions of the properties in a packed value.
const int _scriptShift = 5;
const int _syllabicShift = 13;
const int _positionalShift = 19;
const int _verticalShift = 23;
const int _ignorableShift = 25;
const int _emojiShift = 26;

/// The emoji properties, from [_emojiShift] up.
const List<String> _emojiProperties = [
  'Emoji',
  'Emoji_Presentation',
  'Emoji_Modifier',
  'Emoji_Modifier_Base',
  'Extended_Pictographic',
];

void main() {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final ucd = '$root/vendor/ucd/18.0.0';

  void each(String file, void Function(int start, int end, List<String>) f) {
    for (final line in File('$ucd/$file').readAsLinesSync()) {
      final data = line.split('#').first.trim();
      if (data.isEmpty) continue;
      final fields = data.split(';').map((s) => s.trim()).toList();
      final bounds = fields.first.split('..');
      f(
        int.parse(bounds.first, radix: 16),
        int.parse(bounds.last, radix: 16),
        fields.sublist(1),
      );
    }
  }

  // The property values, short and long names, in the aliases' order.
  final aliases = <String, List<(String, String)>>{};
  for (final line in File('$ucd/PropertyValueAliases.txt').readAsLinesSync()) {
    final data = line.split('#').first.trim();
    if (data.isEmpty) continue;
    final fields = data.split(';').map((s) => s.trim()).toList();
    (aliases[fields[0]] ??= []).add((fields[1], fields[2]));
  }
  // General_Category: the 30 values, not the groups (C, L, LC, M, ...).
  final categories = [
    for (final (short, long) in aliases['gc']!)
      if (short.length == 2 && short != 'LC') (short, long),
  ];
  final scripts = aliases['sc']!;
  final syllabic = aliases['InSC']!;
  final positional = aliases['InPC']!;
  final vertical = aliases['vo']!;
  int indexOf(List<(String, String)> values, String name) {
    for (final (i, (short, long)) in values.indexed) {
      if (short == name || long == name) return i;
    }
    throw StateError('unknown value $name');
  }

  final values = Uint32List(0x110000);
  // Defaults: Cn, Zzzz (Unknown), Other, NA; Vertical_Orientation's from
  // its @missing lines, in order.
  final unassigned = indexOf(categories, 'Cn');
  final unknown = indexOf(scripts, 'Zzzz');
  final other = indexOf(syllabic, 'Other');
  final na = indexOf(positional, 'NA');
  for (var c = 0; c < values.length; c++) {
    values[c] =
        unassigned |
        unknown << _scriptShift |
        other << _syllabicShift |
        na << _positionalShift;
  }
  final verticals = Uint8List(0x110000);
  for (final line in File('$ucd/VerticalOrientation.txt').readAsLinesSync()) {
    final m = RegExp(r'^# @missing: ([0-9A-F]+)\.\.([0-9A-F]+); (\w+)')
        .firstMatch(line);
    if (m == null) continue;
    final value = indexOf(vertical, m[3]!);
    for (
      var c = int.parse(m[1]!, radix: 16);
      c <= int.parse(m[2]!, radix: 16);
      c++
    ) {
      verticals[c] = value;
    }
  }
  each('VerticalOrientation.txt', (start, end, fields) {
    final value = indexOf(vertical, fields.first);
    for (var c = start; c <= end; c++) {
      verticals[c] = value;
    }
  });
  void set(String file, List<(String, String)> list, int shift, int mask) {
    each(file, (start, end, fields) {
      final value = indexOf(list, fields.first);
      for (var c = start; c <= end; c++) {
        values[c] = (values[c] & ~(mask << shift)) | value << shift;
      }
    });
  }

  set('DerivedGeneralCategory.txt', categories, 0, 0x1f);
  set('Scripts.txt', scripts, _scriptShift, 0xff);
  set('IndicSyllabicCategory.txt', syllabic, _syllabicShift, 0x3f);
  set('IndicPositionalCategory.txt', positional, _positionalShift, 0xf);
  for (var c = 0; c < values.length; c++) {
    values[c] |= verticals[c] << _verticalShift;
  }
  each('DerivedCoreProperties.txt', (start, end, fields) {
    if (fields.first != 'Default_Ignorable_Code_Point') return;
    for (var c = start; c <= end; c++) {
      values[c] |= 1 << _ignorableShift;
    }
  });
  each('emoji-data.txt', (start, end, fields) {
    final bit = _emojiProperties.indexOf(fields.first);
    if (bit < 0) return;
    for (var c = start; c <= end; c++) {
      values[c] |= 1 << (_emojiShift + bit);
    }
  });
  if (scripts.length > 256 ||
      syllabic.length > 64 ||
      positional.length > 16 ||
      vertical.length > 4) {
    throw StateError('a property has outgrown its bits');
  }

  // The canonical decompositions, and the exclusions from composition.
  final decompositions = <int, List<int>>{};
  for (final line in File('$ucd/UnicodeData.txt').readAsLinesSync()) {
    final fields = line.split(';');
    final mapping = fields[5];
    if (mapping.isEmpty || mapping.startsWith('<')) continue;
    decompositions[int.parse(fields[0], radix: 16)] = [
      for (final part in mapping.split(' ')) int.parse(part, radix: 16),
    ];
  }
  final excluded = <int>{};
  each('DerivedNormalizationProps.txt', (start, end, fields) {
    if (fields.first != 'Full_Composition_Exclusion') return;
    for (var c = start; c <= end; c++) {
      excluded.add(c);
    }
  });

  // The palette, and the three stages over it.
  final palette = <int, int>{};
  final indices = Uint16List(values.length);
  for (var c = 0; c < values.length; c++) {
    indices[c] = palette.putIfAbsent(values[c], () => palette.length);
  }
  if (palette.length > 0x10000) throw StateError('palette too large');
  final stage3 = <int>[];
  final stage3Blocks = <String, int>{};
  final stage3Offsets = <int>[];
  for (var c = 0; c < indices.length; c += 32) {
    final block = indices.sublist(c, c + 32);
    stage3Offsets.add(
      stage3Blocks.putIfAbsent(block.join(','), () {
        stage3.addAll(block);
        return stage3.length - 32;
      }),
    );
  }
  final stage2 = <int>[];
  final stage2Blocks = <String, int>{};
  final stage1 = <int>[];
  for (var b = 0; b < stage3Offsets.length; b += 64) {
    final block = stage3Offsets.sublist(b, b + 64);
    stage1.add(
      stage2Blocks.putIfAbsent(block.join(','), () {
        stage2.addAll(block);
        return stage2.length - 64;
      }),
    );
  }
  if (stage3.length > 0x10000 || stage2.length > 0x10000) {
    throw StateError('stage offsets exceed 16 bits');
  }
  final paletteValues = palette.keys.toList();
  for (var c = 0; c < values.length; c++) {
    final index = stage3[stage2[stage1[c >> 11] + ((c >> 5) & 63)] + (c & 31)];
    if (paletteValues[index] != values[c]) {
      throw StateError('trie mismatch at ${c.toRadixString(16)}');
    }
  }

  String camel(String name) {
    final words = name.split('_');
    final out = StringBuffer(words.first.toLowerCase());
    for (final w in words.skip(1)) {
      if (w.isEmpty) continue;
      out.write(w[0].toUpperCase() + w.substring(1).toLowerCase());
    }
    final s = out.toString();
    // (Names Dart reserves, or an enum's own members.)
    const reserved = {'null', 'default', 'values', 'index', 'name'};
    return reserved.contains(s) ? '${s}Value' : s;
  }

  String enumOf(String name, String doc, List<(String, String)> list) {
    final out = StringBuffer()
      ..writeln(doc)
      ..writeln('enum $name {');
    for (final (short, long) in list) {
      out
        ..writeln('  /// `$short` ($long).')
        ..writeln('  ${camel(long)},');
    }
    out.writeln('}');
    return out.toString();
  }

  final decomposed = [
    for (final c in decompositions.keys.toList()..sort()) ...[
      c,
      decompositions[c]!.first,
      if (decompositions[c]!.length > 1) decompositions[c]![1] else 0,
    ],
  ];
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Generated by `dart run tool/generate_properties.dart` from')
    ..writeln('// the Unicode Character Database 18.0.0 (vendor/ucd/18.0.0;')
    ..writeln('// see vendor/ucd/18.0.0/license.txt for its terms).')
    ..writeln('// The stages are long base64 strings: one line each.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('/// The properties text shaping reads of every code point, as a')
    ..writeln('/// three-stage table: those of code point `c` are')
    ..writeln('/// `palette[stage3[stage2[stage1[c >> 11] + (c >> 5 & 63)] +')
    ..writeln('/// (c & 31)]]`; its canonical decompositions; and the')
    ..writeln("/// enumerations of the properties' values.")
    ..writeln('library;')
    ..writeln()
    ..writeln('/// The Unicode version of the data.')
    ..writeln("const String propertiesUnicodeVersion = '18.0.0';")
    ..writeln()
    ..writeln('/// The distinct properties: the General_Category (bits 0-4),')
    ..writeln('/// the Script (bits 5-12), the Indic_Syllabic_Category (bits')
    ..writeln('/// 13-18), the Indic_Positional_Category (bits 19-22), the')
    ..writeln(
      '/// Vertical_Orientation (bits 23-24) and Default_Ignorable_Code_',
    )
    ..writeln('/// Point (bit 25), each the index of its value in its')
    ..writeln('/// enumeration.')
    ..writeln('const List<int> palette = [')
    ..writeln(_wrap(paletteValues))
    ..writeln('];')
    ..writeln()
    ..writeln('/// Stage 1: ${stage1.length} 16-bit offsets into stage 2')
    ..writeln('/// (little-endian, base64).')
    ..writeln("const String stage1 = '${_base64Words(stage1)}';")
    ..writeln()
    ..writeln('/// Stage 2: ${stage2.length} 16-bit offsets into stage 3')
    ..writeln('/// (little-endian, base64).')
    ..writeln("const String stage2 = '${_base64Words(stage2)}';")
    ..writeln()
    ..writeln('/// Stage 3: ${stage3.length} 16-bit palette indices')
    ..writeln('/// (little-endian, base64).')
    ..writeln("const String stage3 = '${_base64Words(stage3)}';")
    ..writeln()
    ..writeln('/// The canonical decompositions: each code point, then the')
    ..writeln('/// first and second of its decomposition (0: it has one), in')
    ..writeln(
      '/// order of code point (as 32-bit little-endian words, base64).',
    )
    ..writeln("const String decompositions = '${_base64Ints(decomposed)}';")
    ..writeln()
    ..writeln('/// The code points excluded from canonical composition')
    ..writeln('/// (Full_Composition_Exclusion) that have a decomposition of')
    ..writeln('/// two, in order.')
    ..writeln('const List<int> compositionExclusions = [')
    ..writeln(
      _wrap([
        for (final c in excluded.toList()..sort())
          if ((decompositions[c]?.length ?? 0) == 2) c,
      ]),
    )
    ..writeln('];')
    ..writeln()
    ..writeln('/// The ISO 15924 codes of the Script values, in their order.')
    ..writeln('const List<String> scriptCodes = [')
    ..writeln(_wrapStrings([for (final (short, _) in scripts) short]))
    ..writeln('];')
    ..writeln()
    ..write(
      enumOf(
        'GeneralCategory',
        "/// A code point's General_Category.",
        categories,
      ),
    )
    ..writeln()
    ..write(
      enumOf(
        'IndicSyllabicCategory',
        "/// A code point's Indic_Syllabic_Category.",
        syllabic,
      ),
    )
    ..writeln()
    ..write(
      enumOf(
        'IndicPositionalCategory',
        "/// A code point's Indic_Positional_Category.",
        positional,
      ),
    )
    ..writeln()
    ..write(
      enumOf(
        'VerticalOrientation',
        "/// A code point's Vertical_Orientation (UAX #50).",
        vertical,
      ),
    );
  File('$root/lib/src/properties_data.g.dart').writeAsStringSync('$out');
  stdout.writeln(
    'palette ${palette.length}, stage1 ${stage1.length}, '
    'stage2 ${stage2.length}, stage3 ${stage3.length}, '
    'decompositions ${decompositions.length}',
  );
}

String _wrap(List<int> values) {
  final out = StringBuffer();
  var line = StringBuffer('  ');
  for (final v in values) {
    final item = '0x${v.toRadixString(16)}, ';
    if (line.length + item.length > 80) {
      out.writeln(line.toString().trimRight());
      line = StringBuffer('  ');
    }
    line.write(item);
  }
  out.write(line.toString().trimRight());
  return out.toString();
}

String _wrapStrings(List<String> values) {
  final out = StringBuffer();
  var line = StringBuffer('  ');
  for (final v in values) {
    final item = "'$v', ";
    if (line.length + item.length > 80) {
      out.writeln(line.toString().trimRight());
      line = StringBuffer('  ');
    }
    line.write(item);
  }
  out.write(line.toString().trimRight());
  return out.toString();
}

String _base64Words(List<int> words) {
  final bytes = ByteData(words.length * 2);
  for (final (i, w) in words.indexed) {
    bytes.setUint16(i * 2, w, Endian.little);
  }
  return base64.encode(bytes.buffer.asUint8List());
}

String _base64Ints(List<int> ints) {
  final bytes = ByteData(ints.length * 4);
  for (final (i, v) in ints.indexed) {
    bytes.setUint32(i * 4, v, Endian.little);
  }
  return base64.encode(bytes.buffer.asUint8List());
}
