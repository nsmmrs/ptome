/// Justification by alternative letterforms (W3C "Arabic & Persian Layout
/// Requirements", 7.2.3): a justified line of Nastaliq (or any script)
/// set with its font's justification alternates (OpenType `jalt`: wider
/// final and isolated letters) at some of its words, so that its spaces
/// widen less. The forms have fixed widths, so they take the line only
/// nearer its measure; the spaces take the rest. As alreq warns against
/// "multiple very wide alternatives close to each other", no two words
/// side by side take them.
library;

import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/font.dart';

/// [glyphs] (the shaped [text] of a run in [style], in visual order) with
/// the font's justification alternates at words chosen from the line's
/// end, each where its wider forms fit in what is left of [extra]
/// (points), none beside another; and how much wider that makes it. The
/// glyphs as they are where the font has no `jalt` or nothing fits.
({List<ShapedGlyph> glyphs, double gained}) justificationAlternates(
  String text,
  List<ShapedGlyph> glyphs,
  TextStyle style,
  double extra, {
  required bool rightToLeft,
}) {
  final none = (glyphs: glyphs, gained: 0.0);
  if (extra <= 0) return none;
  if (style.font case OpenTypeTextFont(:final font)
      when font.hasFeature('jalt')) {
    final wide = style.copyWith(features: {...style.features, 'jalt'});
    // The run's glyphs by word (and the spaces between), as they are
    // drawn; each word's text in reading order.
    final groups = <List<ShapedGlyph>>[];
    bool? space;
    for (final g in glyphs) {
      final isSpace = g.text.isNotEmpty && g.text.trim().isEmpty;
      if (groups.isEmpty || (g.text.isNotEmpty && isSpace != space)) {
        groups.add([]);
        space = isSpace;
      }
      groups.last.add(g);
    }
    String textOf(List<ShapedGlyph> group) =>
        (rightToLeft ? group.reversed : group).map((g) => g.text).join();
    // (From the line's end: its last word read, the leftmost drawn in a
    // right-to-left run.)
    final order = rightToLeft
        ? [for (var i = 0; i < groups.length; i++) i]
        : [for (var i = groups.length - 1; i >= 0; i--) i];
    final chosen = <int, List<ShapedGlyph>>{};
    var left = extra;
    int? previous;
    var words = 0;
    for (final i in order) {
      final word = textOf(groups[i]);
      if (word.trim().isEmpty) continue;
      words++;
      // (Not beside the word that took them.)
      if (previous != null && previous == words - 1) continue;
      final alternate = wide.shape(word, rightToLeft: rightToLeft);
      // (Only a word the feature changes: else what differs is context.)
      final usual = style.shape(word, rightToLeft: rightToLeft);
      if (alternate.length == usual.length &&
          [
            for (var k = 0; k < usual.length; k++)
              alternate[k].id == usual[k].id,
          ].every((same) => same)) {
        continue;
      }
      final gain = wide.widthOf(alternate) - style.widthOf(groups[i]);
      if (gain <= 1e-6 || gain > left) continue;
      chosen[i] = alternate;
      left -= gain;
      previous = words;
    }
    if (chosen.isEmpty) return none;
    return (
      glyphs: [
        for (var i = 0; i < groups.length; i++) ...chosen[i] ?? groups[i],
      ],
      gained: extra - left,
    );
  }
  return none;
}
