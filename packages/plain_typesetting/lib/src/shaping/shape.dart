/// Text shaped as HarfBuzz 14.6 shapes it (`hb-ot-shape.cc`): the run's
/// script picks the font's script tables and the shaper; the characters
/// are normalized, the shaper sets their masks, the GSUB lookups apply
/// stage by stage (the shaper's pauses between), then the advances, the
/// GPOS lookups and the marks' widths, and default ignorables hidden.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/arabic.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';
import 'package:plain_typesetting/src/shaping/scripts.dart';
import 'package:plain_typesetting/src/shaping/shaper.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// A glyph of shaped text in font units: its id, the characters of its
/// cluster (its first glyph has them), its advance and offsets.
typedef ShapedUnits = ({
  int glyph,
  String text,
  int advance,
  int xOffset,
  int yOffset,
});

/// The script of [runes]: the first that isn't Common, Inherited or
/// Unknown (HarfBuzz's guess), else `Zyyy`.
String runScript(List<int> runes) {
  for (final r in runes) {
    final s = scriptOf(r);
    if (s != 'Zyyy' && s != 'Zinh' && s != 'Zzzz') return s;
  }
  return 'Zyyy';
}

final class _Plan {
  new(this.plan, this.shaper, {required this.applyGpos});

  final ShapePlan plan;
  final Shaper shaper;
  final bool applyGpos;
}

/// The plans made so far, by font and key.
final Expando<Map<String, _Plan>> _plans = Expando();

/// The layouts of the fonts shaped so far.
final Expando<OpenTypeLayout> _layouts = Expando();

/// [font]'s layout tables.
OpenTypeLayout layoutOf(OpenTypeFont font) =>
    _layouts[font] ??= OpenTypeLayout(font);

Shaper _shaperOf(ShaperKind kind) => switch (kind) {
  ShaperKind.arabic => ArabicShaper(),
  ShaperKind.hebrew => HebrewShaper(),
  _ => StandardShaper(),
};

_Plan _planFor(
  OpenTypeFont font,
  String script, {
  required bool rightToLeft,
  required bool kerning,
  required bool ligatures,
  required Set<String> features,
}) {
  final key =
      '$script ${rightToLeft ? 'r' : 'l'} ${kerning ? 'k' : ''}'
      '${ligatures ? 'l' : ''} ${(features.toList()..sort()).join(',')}';
  final plans = _plans[font] ??= {};
  return plans[key] ??= () {
    final layout = layoutOf(font);
    final tags = script == 'Zyyy' ? const <String>[] : scriptTags(script);
    final gsub = layout.selectScript(tags);
    final gpos = layout.selectScript(tags, positioning: true);
    final kind = shaperFor(script, gsub?.$1 ?? 'DFLT');
    final shaper = _shaperOf(kind);
    final builder = PlanBuilder(layout, gsub?.$1, gpos?.$1)
      ..enableFeature('rvrn')
      ..addGsubPause();
    if (rightToLeft) {
      builder
        ..enableFeature('rtla')
        ..addFeature('rtlm');
    } else {
      builder
        ..enableFeature('ltra')
        ..enableFeature('ltrm');
    }
    builder
      ..addFeature('frac')
      ..addFeature('numr')
      ..addFeature('dnom')
      ..enableFeature('rand', flags: FeatureFlags.random, value: 255)
      ..enableFeature('Harf')
      ..enableFeature('HARF');
    if (kind != ShaperKind.standard) {
      builder.isSimple = false;
      shaper.collectFeatures(builder, script);
    }
    builder
      ..enableFeature('Buzz')
      ..enableFeature('BUZZ');
    for (final (tag, flags) in const [
      ('abvm', FeatureFlags.global),
      ('blwm', FeatureFlags.global),
      ('ccmp', FeatureFlags.global),
      ('locl', FeatureFlags.global),
      ('mark', FeatureFlags.globalManualJoiners),
      ('mkmk', FeatureFlags.globalManualJoiners),
      ('rlig', FeatureFlags.global),
      ('calt', FeatureFlags.global),
      ('clig', FeatureFlags.global),
      ('curs', FeatureFlags.global),
      ('dist', FeatureFlags.global),
      ('kern', FeatureFlags.globalHasFallback),
      ('liga', FeatureFlags.global),
      ('rclt', FeatureFlags.global),
    ]) {
      builder.addFeature(tag, flags: flags);
    }
    // The caller's features: ligatures and kerning off, others on.
    final user = <(String, int)>[
      if (!kerning) ('kern', 0),
      if (!ligatures) ...[('liga', 0), ('clig', 0)],
      for (final f in features) (f, 1),
    ];
    if (user.isNotEmpty) builder.isSimple = false;
    for (final (tag, value) in user) {
      builder.addFeature(tag, flags: FeatureFlags.global, value: value);
    }
    shaper.overrideFeatures(builder);
    final plan = builder.compile();
    shaper.planCompiled(plan, layout);
    final gposTag = shaper.gposTag;
    final applyGpos = gposTag == null || gposTag == gpos?.$1;
    return _Plan(plan, shaper, applyGpos: applyGpos);
  }();
}

/// [text] in [font] as HarfBuzz shapes it, in visual order: [rightToLeft]
/// the run's direction, [kerning] and [ligatures] on or off, [features]
/// more features on.
List<ShapedUnits> shapeText(
  OpenTypeFont font,
  String text, {
  required bool rightToLeft,
  bool kerning = true,
  bool ligatures = true,
  Set<String> features = const {},
}) {
  final runes = text.runes.toList();
  if (runes.isEmpty) return const [];
  final script = runScript(runes);
  final entry = _planFor(
    font,
    script,
    rightToLeft: rightToLeft,
    kerning: kerning,
    ligatures: ligatures,
    features: features,
  );
  final plan = entry.plan;
  final shaper = entry.shaper;
  final layout = layoutOf(font);
  final glyphs = <LayoutGlyph>[
    for (final (i, r) in runes.indexed)
      LayoutGlyph(0, i, mask: plan.globalMask)
        ..char = r
        ..apply(setUnicodeProps),
  ];
  // Clusters: a mark (or a continuation) joins its base's.
  for (var i = 1; i < glyphs.length; i++) {
    final g = glyphs[i];
    if (isUnicodeMark(g) || (g.char >= 0xe0020 && g.char <= 0xe007f)) {
      g.cluster = glyphs[i - 1].cluster;
    }
  }
  final context = ShapeContext(
    glyphs: glyphs,
    layout: layout,
    script: script,
    rightToLeft: rightToLeft,
    glyphFor: font.glyphFor,
  )..plan = plan;
  shaper.preprocessText(context);

  // Mirrored characters, where right to left.
  if (rightToLeft) {
    final rtlm = plan.oneMaskOf('rtlm');
    for (final g in glyphs) {
      final mirror = bidiMirror(g.char);
      if (mirror != g.char && font.glyphFor(mirror) != 0) {
        g.char = mirror;
      } else {
        g.mask |= rtlm;
      }
    }
  }
  final normalized = normalize(context.glyphs, shaper, font.glyphFor);
  context.glyphs
    ..clear()
    ..addAll(normalized);
  _setupFractionMasks(context.glyphs, plan, rightToLeft: rightToLeft);
  shaper.setupMasks(context);

  // Substitution.
  layout.classify(context.glyphs);
  if (!layout.hasGlyphClasses) {
    for (final g in context.glyphs) {
      g.props =
          g.generalCategory == GeneralCategory.nonspacingMark.index &&
              g.flags & UnicodeFlags.ignorable == 0
          ? GlyphProps.mark
          : GlyphProps.base;
    }
  }
  plan.run(0, context, (lookups) => layout.substitute(context.glyphs, lookups));

  // Positioning.
  final run = context.glyphs;
  for (final g in run) {
    g
      ..xAdvance = font.advance(g.glyph)
      ..yAdvance = 0
      ..xOffset = 0
      ..yOffset = 0
      ..attachChain = 0
      ..attachType = 0;
  }
  final zero = shaper.zeroWidthMarks;
  if (zero == ZeroWidthMarks.byGdefEarly) {
    for (final g in run) {
      if (g.isMark) g.xAdvance = 0;
    }
  }
  layout.position(
    run,
    entry.applyGpos ? plan.lookups[1] : const [],
    rightToLeft: rightToLeft,
    zeroMarks: zero == ZeroWidthMarks.byGdefLate,
  );
  // Default ignorables take no room, and show as the space glyph.
  final space = font.glyphFor(0x20);
  for (final g in run) {
    if (g.flags & UnicodeFlags.ignorable != 0) {
      g
        ..xAdvance = 0
        ..xOffset = 0;
      if (space != 0) g.glyph = space;
    }
  }
  shaper.postprocessGlyphs(context);

  // The text of each glyph: its cluster's characters, with its first.
  final starts = {for (final g in run) g.cluster}.toList()..sort();
  String textOf(int cluster) {
    final next = starts.firstWhere((c) => c > cluster, orElse: () => -1);
    return String.fromCharCodes(
      runes.sublist(cluster, next < 0 ? runes.length : next),
    );
  }

  final seen = <int>{};
  final out = <ShapedUnits>[
    for (final g in run)
      (
        glyph: g.glyph,
        text: seen.add(g.cluster) ? textOf(g.cluster) : '',
        advance: g.xAdvance,
        xOffset: g.xOffset,
        yOffset: g.yOffset,
      ),
  ];
  return rightToLeft ? out.reversed.toList() : out;
}

/// The `numr`, `frac` and `dnom` masks around each FRACTION SLASH between
/// digits (HarfBuzz's automatic fractions).
void _setupFractionMasks(
  List<LayoutGlyph> glyphs,
  ShapePlan plan, {
  required bool rightToLeft,
}) {
  final frac = plan.oneMaskOf('frac');
  final numr = plan.oneMaskOf('numr');
  final dnom = plan.oneMaskOf('dnom');
  if (frac == 0 && (numr == 0 || dnom == 0)) return;
  bool digit(LayoutGlyph g) =>
      g.generalCategory == GeneralCategory.decimalNumber.index;
  final pre = rightToLeft ? frac | dnom : numr | frac;
  final post = rightToLeft ? numr | frac : frac | dnom;
  for (var i = 0; i < glyphs.length; i++) {
    if (glyphs[i].char != 0x2044) continue;
    var start = i;
    var end = i + 1;
    while (start > 0 && digit(glyphs[start - 1])) {
      start--;
    }
    while (end < glyphs.length && digit(glyphs[end])) {
      end++;
    }
    if (start == i || end == i + 1) continue;
    for (var j = start; j < i; j++) {
      glyphs[j].mask |= pre;
    }
    glyphs[i].mask |= frac;
    for (var j = i + 1; j < end; j++) {
      glyphs[j].mask |= post;
    }
    i = end - 1;
  }
}

extension on LayoutGlyph {
  void apply(void Function(LayoutGlyph) f) => f(this);
}
