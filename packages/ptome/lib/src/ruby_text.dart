/// Ruby (`ruby:漢字[かんじ]`, Ptome's syntax), as each format writes it.
library;

import 'package:ptome/src/inline.dart';

/// The base of a ruby [node] and each part of it with its reading: one a
/// character where the readings, separated by spaces, are as many as the
/// base's characters (mono ruby); else the whole base with the whole
/// reading (group ruby).
List<(String, String)> rubyPairs(Inline node) {
  final base = node.text ?? '';
  final reading = node.attributes['reading'] ?? '';
  final readings = reading.split(' ').where((r) => r.isNotEmpty).toList();
  final characters = [for (final c in base.runes) String.fromCharCode(c)];
  if (readings.length > 1 && readings.length == characters.length) {
    return [for (final (i, c) in characters.indexed) (c, readings[i])];
  }
  return [(base, reading)];
}

/// HTML's `<ruby>`: each part's base, then its reading in `<rt>`, between
/// `<rp>` parentheses for readers without ruby.
String rubyHtml(Inline node) => [
  '<ruby>',
  for (final (base, reading) in rubyPairs(node))
    '$base<rp>(</rp><rt>$reading</rt><rp>)</rp>',
  '</ruby>',
].join();

/// Ruby as text: the base, its reading after it in parentheses.
String rubyText(Inline node) =>
    '${node.text ?? ''}(${node.attributes['reading'] ?? ''})';
