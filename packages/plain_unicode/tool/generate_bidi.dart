/// Generates `lib/src/bidi_data.g.dart` from the Unicode Character
/// Database files in `vendor/ucd/18.0.0` (Unicode 18.0.0): the
/// Bidi_Class of every code point (DerivedBidiClass.txt, its `@missing`
/// defaults first), its Joining_Type (DerivedJoiningType.txt) and its
/// Bidi_Paired_Bracket_Type (BidiBrackets.txt), as a three-stage table
/// of 16-bit values (as `generate_line_break.dart` lays it out); and the
/// Bidi_Mirroring_Glyph and Bidi_Paired_Bracket pairs (BidiMirroring.txt,
/// BidiBrackets.txt).
///
/// ```sh
/// dart run tool/generate_bidi.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The Bidi_Class values, in the order of `BidiClass` in
/// `lib/src/bidi.dart`.
const List<String> bidiClasses = [
  'L', 'R', 'AL', 'EN', 'ES', 'ET', 'AN', 'CS', 'NSM', 'BN', 'B', 'S', //
  'WS', 'ON', 'LRE', 'LRO', 'RLE', 'RLO', 'PDF', 'LRI', 'RLI', 'FSI', 'PDI',
];

/// The long names the `@missing` lines use.
const Map<String, String> longNames = {
  'Left_To_Right': 'L',
  'Right_To_Left': 'R',
  'Arabic_Letter': 'AL',
  'European_Terminator': 'ET',
};

/// The Joining_Type values, in the order of `JoiningType`.
const List<String> joiningTypes = ['U', 'R', 'D', 'C', 'L', 'T'];

void main() {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final ucd = '$root/vendor/ucd/18.0.0';
  final values = Uint16List(0x110000);

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

  // Bidi_Class: the defaults of the @missing lines, in order, then the
  // values listed.
  for (final line in File('$ucd/DerivedBidiClass.txt').readAsLinesSync()) {
    final m = RegExp(r'^# @missing: ([0-9A-F]+)\.\.([0-9A-F]+); (\w+)')
        .firstMatch(line);
    if (m == null) continue;
    final value = bidiClasses.indexOf(longNames[m[3]!]!);
    for (
      var c = int.parse(m[1]!, radix: 16);
      c <= int.parse(m[2]!, radix: 16);
      c++
    ) {
      values[c] = value;
    }
  }
  each('DerivedBidiClass.txt', (start, end, fields) {
    final value = bidiClasses.indexOf(fields.first);
    if (value < 0) throw StateError('unknown Bidi_Class ${fields.first}');
    for (var c = start; c <= end; c++) {
      values[c] = value;
    }
  });
  // Joining_Type (bits 5-7; U where not listed).
  each('DerivedJoiningType.txt', (start, end, fields) {
    final value = joiningTypes.indexOf(fields.first);
    if (value < 0) throw StateError('unknown Joining_Type ${fields.first}');
    for (var c = start; c <= end; c++) {
      values[c] |= value << 5;
    }
  });
  // Bidi_Paired_Bracket_Type (bits 8-9: 1 open, 2 close) and the pairs.
  final brackets = <int, int>{};
  each('BidiBrackets.txt', (start, end, fields) {
    brackets[start] = int.parse(fields[0], radix: 16);
    values[start] |= (fields[1] == 'o' ? 1 : 2) << 8;
  });
  final mirrors = <int, int>{};
  each('BidiMirroring.txt', (start, end, fields) {
    mirrors[start] = int.parse(fields[0], radix: 16);
  });

  // The palette, and the three stages over it.
  final palette = <int, int>{};
  final indices = Uint8List(values.length);
  for (var c = 0; c < values.length; c++) {
    indices[c] = palette.putIfAbsent(values[c], () => palette.length);
  }
  if (palette.length > 256) throw StateError('palette too large');
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
  for (var c = 0; c < values.length; c++) {
    final index = stage3[stage2[stage1[c >> 11] + ((c >> 5) & 63)] + (c & 31)];
    if (palette.keys.elementAt(index) != values[c]) {
      throw StateError('trie mismatch at ${c.toRadixString(16)}');
    }
  }
  List<int> pairs(Map<int, int> map) => [
    for (final key in map.keys.toList()..sort()) ...[key, map[key]!],
  ];

  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Generated by `dart run tool/generate_bidi.dart` from the')
    ..writeln('// Unicode Character Database 18.0.0 (vendor/ucd/18.0.0; see')
    ..writeln('// vendor/ucd/18.0.0/license.txt for its terms).')
    ..writeln('// The stages are long base64 strings: one line each.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('/// The bidirectional properties of every code point, as a')
    ..writeln('/// three-stage table: the properties of code point `c` are')
    ..writeln('/// `palette[stage3[stage2[stage1[c >> 11] + (c >> 5 & 63)] +')
    ..writeln('/// (c & 31)]]`.')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// The Unicode version of the data.')
    ..writeln("const String bidiUnicodeVersion = '18.0.0';")
    ..writeln()
    ..writeln('/// The distinct properties: the Bidi_Class (bits 0-4), the')
    ..writeln('/// Joining_Type (bits 5-7) and the Bidi_Paired_Bracket_Type')
    ..writeln('/// (bits 8-9: 1 open, 2 close).')
    ..writeln('const List<int> palette = [')
    ..writeln(_wrap(palette.keys.toList()))
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
    ..writeln('/// Stage 3: ${stage3.length} palette indices, a byte each')
    ..writeln('/// (base64).')
    ..writeln("const String stage3 = '${base64.encode(stage3)}';")
    ..writeln()
    ..writeln('/// The Bidi_Mirroring_Glyph pairs: each code point, then its')
    ..writeln('/// mirror, in order of code point.')
    ..writeln('const List<int> mirrors = [')
    ..writeln(_wrap(pairs(mirrors)))
    ..writeln('];')
    ..writeln()
    ..writeln('/// The Bidi_Paired_Bracket pairs: each bracket, then its')
    ..writeln('/// pair, in order of code point.')
    ..writeln('const List<int> brackets = [')
    ..writeln(_wrap(pairs(brackets)))
    ..writeln('];');
  final path = '$root/lib/src/bidi_data.g.dart';
  File(path).writeAsStringSync(out.toString());
  Process.runSync(Platform.resolvedExecutable, ['format', path]);
  stdout.writeln(
    'generate_bidi: ${palette.length} distinct values, '
    '${stage1.length * 2 + stage2.length * 2 + stage3.length} bytes, '
    '${mirrors.length} mirrors, ${brackets.length} brackets',
  );
}

String _wrap(List<int> values) => [for (final v in values) '  $v,'].join('\n');

String _base64Words(List<int> words) {
  final bytes = Uint8List(words.length * 2);
  for (var i = 0; i < words.length; i++) {
    bytes[2 * i] = words[i] & 0xff;
    bytes[2 * i + 1] = words[i] >> 8;
  }
  return base64.encode(bytes);
}
