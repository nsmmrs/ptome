/// Damaged documents: the XML reader and the SVG drawing fail only with a
/// FormatException, and draw with the canvas's saves and restores paired.
@Tags(['nightly'])
@TestOn('vm')
// (SVG written in pieces.)
// ignore_for_file: missing_whitespace_between_adjacent_strings
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_svg/plain_svg.dart';
import 'package:plain_svg/src/xml.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

/// A canvas counting how deep its saves go.
final class DepthCanvas implements Canvas {
  int depth = 0;

  @override
  void save() => depth++;

  @override
  void restore() => depth--;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #text || invocation.memberName == #glyphs
      ? 0.0
      : null;
}

/// [bytes] damaged by [random]: bytes flipped, dropped, repeated.
List<int> damaged(List<int> bytes, math.Random random) {
  final out = [...bytes];
  for (var n = 1 + random.nextInt(6); n > 0 && out.isNotEmpty; n--) {
    final at = random.nextInt(out.length);
    switch (random.nextInt(3)) {
      case 0:
        out[at] = '<>&;"=/![]#%-:'.codeUnitAt(random.nextInt(14));
      case 1:
        out.removeRange(at, math.min(out.length, at + random.nextInt(20)));
      default:
        out.insertAll(at, out.sublist(at, math.min(out.length, at + 30)));
    }
  }
  return out;
}

void main() {
  final seeds = [
    for (final root in ['../plain_pdf/test/svg', '../ptome/test/pdf/fixtures'])
      if (Directory(root).existsSync())
        for (final entity in Directory(root).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.svg'))
            entity.readAsBytesSync(),
    utf8.encode(
      '<!DOCTYPE svg [<!ENTITY e "<g>&e;</g>"><!ENTITY s "fill:red">]>'
      '<svg xmlns="http://www.w3.org/2000/svg"><clipPath id="c" '
      'clip-path="url(#c)"><use href="#u"/></clipPath><g id="u" '
      'style="&s;" opacity=".5"><use href="#u"/><text>&e;a</text></g>'
      '<path d="M0 0A5 5 0 1 1 9 9z" clip-path="url(#c)"/></svg>',
    ),
  ];

  test('damaged documents fail only as malformed', () {
    final random = math.Random(1013);
    for (var i = 0; i < 4000; i++) {
      final seed = seeds[random.nextInt(seeds.length)];
      final text = utf8.decode(damaged(seed, random), allowMalformed: true);
      try {
        parseXml(text);
      } on FormatException {
        // Malformed.
      }
      try {
        final svg = SvgImage.parse(text);
        final canvas = DepthCanvas();
        svg.paint(canvas, const Rect(0, 0, 100, 100));
        expect(canvas.depth, 0, reason: text);
      } on FormatException {
        // Malformed.
      }
    }
  });
}
