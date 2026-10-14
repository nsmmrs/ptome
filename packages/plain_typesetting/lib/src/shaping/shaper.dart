/// The shapers' common interface (HarfBuzz 14.6's `hb_ot_shaper_t`): the
/// features a shaper adds to the plan, what it does to the text before
/// and after the lookups, how it wants the text normalized, and how
/// marks take their widths.
library;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/normalize.dart';
import 'package:plain_typesetting/src/shaping/plan.dart';

/// When marks' advances are zeroed: not at all, before the GPOS lookups
/// or after them (by their GDEF class).
enum ZeroWidthMarks {
  /// Not zeroed.
  none,

  /// Zeroed before the GPOS lookups.
  byGdefEarly,

  /// Zeroed after them.
  byGdefLate,
}

/// A run being shaped, as a shaper sees it.
final class ShapeContext implements ShapeState {
  /// The run's [glyphs] in [script] (an ISO 15924 code), shaped with
  /// [plan] in [layout]'s font, [rightToLeft] or not.
  new({
    required this.glyphs,
    required this.layout,
    required this.script,
    required this.rightToLeft,
    required this._glyphFor,
  });

  @override
  final List<LayoutGlyph> glyphs;

  @override
  final OpenTypeLayout layout;

  /// The script, an ISO 15924 code.
  final String script;

  /// Whether the run goes right to left.
  final bool rightToLeft;

  final int Function(int) _glyphFor;

  late ShapePlan _plan;

  @override
  ShapePlan get plan => _plan;

  set plan(ShapePlan plan) => _plan = plan;

  @override
  int glyphFor(int codePoint) => _glyphFor(codePoint);
}

/// A shaper, made for one plan (it keeps what it needs of it).
abstract class Shaper implements NormalizationHooks {
  /// A shaper.
  new();

  /// Adds the shaper's features (and pauses) to [builder], for [script].
  void collectFeatures(PlanBuilder builder, String script) {}

  /// Changes features after the user's are added.
  void overrideFeatures(PlanBuilder builder) {}

  /// Takes what it needs from the compiled [plan].
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {}

  /// Works on the characters before normalization (Thai's SARA AM).
  void preprocessText(ShapeContext context) {}

  /// Sets the glyphs' masks (joining forms, syllables).
  void setupMasks(ShapeContext context) {}

  /// Works on the glyphs after positioning.
  void postprocessGlyphs(ShapeContext context) {}

  @override
  NormalizationMode get normalization => NormalizationMode.auto;

  @override
  (int, int)? decompose(int ab) => unicodeDecompose(ab);

  @override
  int? compose(int a, int b) => unicodeCompose(a, b);

  @override
  void reorderMarks(List<LayoutGlyph> glyphs, int start, int end) {}

  /// The GPOS script the shaper applies GPOS for alone (Hebrew's `hebr`),
  /// if any.
  String? get gposTag => null;

  /// When marks' advances are zeroed.
  ZeroWidthMarks get zeroWidthMarks => ZeroWidthMarks.byGdefLate;

  /// Whether marks are placed by fallback where the font can't.
  bool get fallbackPosition => true;
}

/// The default shaper: no features of its own.
final class StandardShaper extends Shaper {
  /// A default shaper.
  new();
}

/// Hebrew: presentation forms composed for fonts without mark
/// positioning, and patah or qamats kept before a meteg (HarfBuzz's
/// `hb-ot-shaper-hebrew.cc`).
final class HebrewShaper extends Shaper {
  /// A Hebrew shaper.
  new();

  bool _hasGposMark = false;

  @override
  void planCompiled(ShapePlan plan, OpenTypeLayout layout) {
    _hasGposMark = plan.gposScript != null && plan.features.containsKey('mark');
  }

  @override
  String? get gposTag => 'hebr';

  static const List<int> _dageshForms = [
    0xfb30, 0xfb31, 0xfb32, 0xfb33, 0xfb34, 0xfb35, 0xfb36, 0x0000, 0xfb38, //
    0xfb39, 0xfb3a, 0xfb3b, 0xfb3c, 0x0000, 0xfb3e, 0x0000, 0xfb40, 0xfb41,
    0x0000, 0xfb43, 0xfb44, 0x0000, 0xfb46, 0xfb47, 0xfb48, 0xfb49, 0xfb4a,
  ];

  @override
  int? compose(int a, int b) {
    final found = unicodeCompose(a, b);
    if (found != null || _hasGposMark) return found;
    switch (b) {
      case 0x05b4:
        if (a == 0x05d9) return 0xfb1d;
      case 0x05b7:
        if (a == 0x05f2) return 0xfb1f;
        if (a == 0x05d0) return 0xfb2e;
      case 0x05b8:
        if (a == 0x05d0) return 0xfb2f;
      case 0x05b9:
        if (a == 0x05d5) return 0xfb4b;
      case 0x05bc:
        if (a >= 0x05d0 && a <= 0x05ea) {
          final form = _dageshForms[a - 0x05d0];
          return form == 0 ? null : form;
        }
        if (a == 0xfb2a) return 0xfb2c;
        if (a == 0xfb2b) return 0xfb2d;
      case 0x05bf:
        switch (a) {
          case 0x05d1:
            return 0xfb4c;
          case 0x05db:
            return 0xfb4d;
          case 0x05e4:
            return 0xfb4e;
        }
      case 0x05c1:
        if (a == 0x05e9) return 0xfb2a;
        if (a == 0xfb49) return 0xfb2c;
      case 0x05c2:
        if (a == 0x05e9) return 0xfb2b;
        if (a == 0xfb49) return 0xfb2d;
    }
    return null;
  }

  @override
  void reorderMarks(List<LayoutGlyph> glyphs, int start, int end) {
    for (var i = start + 2; i < end; i++) {
      final c0 = glyphs[i - 2].combiningClass;
      final c1 = glyphs[i - 1].combiningClass;
      final c2 = glyphs[i].combiningClass;
      // Patah or qamats, sheva or hiriq, then meteg or a mark below.
      if ((c0 == 20 || c0 == 21) &&
          (c1 == 22 || c1 == 23) &&
          (c2 == 25 || c2 == 220)) {
        final g = glyphs[i - 1];
        glyphs[i - 1] = glyphs[i];
        glyphs[i] = g;
        break;
      }
    }
  }
}
