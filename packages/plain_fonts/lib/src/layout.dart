/// OpenType Layout: the GSUB, GPOS and GDEF tables (ISO/IEC 14496-22,
/// 6.2–6.3): the lookups a script's and a language's features select,
/// applied to a run of glyphs, substituting glyphs (single, multiple,
/// alternate, ligature, contextual, chained and reverse chained
/// substitutions) and positioning them (single and pair adjustments,
/// cursive attachment, marks attached to bases, ligatures and marks,
/// contextual positioning).
library;

import 'dart:typed_data';

import 'package:plain_fonts/src/opentype.dart';

/// A glyph of a run being laid out: its id, the character it came from
/// (its cluster, an index into the text), the features that apply to it
/// ([mask], a bit each, as its shaper assigns them), and its position.
final class LayoutGlyph {
  /// A glyph [glyph] from the character at [cluster], [mask] its
  /// features' bits.
  new(this.glyph, this.cluster, {this.mask = -1});

  /// The glyph id.
  int glyph;

  /// The index of the first character it stands for.
  int cluster;

  /// The bits of the features that apply to it.
  int mask;

  /// The ligature it is part of (or, for a mark, the ligature it follows),
  /// 0 for none, and which of its components (from 1; 0 for the ligature
  /// itself).
  int ligatureId = 0;

  /// See [ligatureId].
  int ligatureComponent = 0;

  /// The number of components of the ligature this glyph is (1 when it is
  /// none).
  int components = 1;

  /// The advance across, in font units.
  int xAdvance = 0;

  /// The advance down (vertical layout), in font units.
  int yAdvance = 0;

  /// The offset of where the glyph is drawn from its pen position, in font
  /// units.
  int xOffset = 0;

  /// See [xOffset].
  int yOffset = 0;

  /// The glyph this one is attached to, as an index offset (0: none).
  int attachChain = 0;

  /// How it is attached: 1 a mark, 2 cursive.
  int attachType = 0;

  /// Its glyph properties ([GlyphProps]): its class (from GDEF, else as
  /// its shaper guesses it), a mark's attachment class (bits 8 to 15),
  /// and what substitutions made it.
  int props = 0;

  /// Its syllable (as a shaper numbers them; 0: none), which lookups of
  /// a per-syllable feature don't match across.
  int syllable = 0;

  /// The character it is (while a shaper works on it).
  int char = 0;

  /// Its character's General_Category, as an index (while a shaper works
  /// on it).
  int generalCategory = 0;

  /// Its character's combining class as HarfBuzz modifies it (a mark's;
  /// 0 otherwise).
  int combiningClass = 0;

  /// Its category, as its shaper classes it (Indic, USE, ...).
  int category = 0;

  /// Its position, as its shaper classes it.
  int position = 0;

  /// What its character is ([UnicodeFlags]): a default ignorable, a
  /// joiner, a non-joiner, hidden.
  int flags = 0;

  /// Whether it is a mark ([GlyphProps.mark]).
  bool get isMark => props & GlyphProps.mark != 0;

  /// Whether it is a ligature ([GlyphProps.ligature]).
  bool get isLigature => props & GlyphProps.ligature != 0;

  /// Whether a substitution made it.
  bool get isSubstituted => props & GlyphProps.substituted != 0;

  /// Whether a ligature substitution made it.
  bool get isLigated => props & GlyphProps.ligated != 0;

  /// Whether a multiple substitution made it.
  bool get isMultiplied => props & GlyphProps.multiplied != 0;
}

/// The bits of a glyph's properties ([LayoutGlyph.props]), as HarfBuzz
/// keeps them: its class (the bits a lookup flag ignores) and what made
/// it.
abstract final class GlyphProps {
  /// A base glyph.
  static const int base = 0x02;

  /// A ligature.
  static const int ligature = 0x04;

  /// A mark (its attachment class in bits 8 to 15).
  static const int mark = 0x08;

  /// Made by a substitution.
  static const int substituted = 0x10;

  /// Made by a ligature substitution.
  static const int ligated = 0x20;

  /// Made by a multiple substitution.
  static const int multiplied = 0x40;

  /// The bits a substitution keeps.
  static const int preserve = substituted | ligated | multiplied;
}

/// The bits of what a glyph's character is ([LayoutGlyph.flags]).
abstract final class UnicodeFlags {
  /// A default ignorable code point.
  static const int ignorable = 1;

  /// ZERO WIDTH JOINER.
  static const int zwj = 2;

  /// ZERO WIDTH NON-JOINER.
  static const int zwnj = 4;

  /// A default ignorable hidden even from positioning (COMBINING GRAPHEME
  /// JOINER, Mongolian free variation selectors, tags).
  static const int hidden = 8;
}

/// A lookup to apply, with the mask of the glyphs it applies to and how
/// it matches: joiners skipped or not, within a syllable or not.
final class LayoutLookup {
  /// Lookup [index] of the GSUB or GPOS table, applying to the glyphs
  /// [mask] has bits of.
  const new(
    this.index,
    this.mask, {
    this.autoZwnj = true,
    this.autoZwj = true,
    this.perSyllable = false,
  });

  /// The lookup's index.
  final int index;

  /// The bits of the glyphs it applies to.
  final int mask;

  /// Whether a ZERO WIDTH NON-JOINER is skipped while matching context.
  final bool autoZwnj;

  /// Whether a ZERO WIDTH JOINER is skipped while matching.
  final bool autoZwj;

  /// Whether the glyphs it matches are all of one syllable.
  final bool perSyllable;
}

/// The lookup flag bits.
abstract final class _Flag {
  static const int rightToLeft = 1;
  static const int ignoreBaseGlyphs = 2;
  static const int ignoreLigatures = 4;
  static const int ignoreMarks = 8;
  static const int useMarkFilteringSet = 0x10;
}

/// A lookup: its type, flag, mark filtering set and subtables' offsets
/// (an extension's resolved).
final class _Lookup {
  const new(this.type, this.flag, this.markSet, this.subtables);

  final int type;
  final int flag;
  final int markSet;
  final List<int> subtables;
}

/// Big-endian reads of a table.
final class _Table {
  new(this.bytes) : view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData view;

  int u16(int at) => view.getUint16(at);
  int i16(int at) => view.getInt16(at);
  int u32(int at) => view.getUint32(at);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
}

/// A font's OpenType layout tables, read on first use.
final class OpenTypeLayout {
  /// The layout of [font].
  new(this.font);

  /// The font.
  final OpenTypeFont font;

  late final _Table? _gsub = _tableOf('GSUB');
  late final _Table? _gpos = _tableOf('GPOS');
  late final _Table? _gdef = _tableOf('GDEF');

  _Table? _tableOf(String tag) => switch (font.table(tag)) {
    final bytes? when bytes.length >= 10 => _Table(bytes),
    _ => null,
  };

  /// Whether the font has a GSUB or GPOS table.
  bool get hasLayout => _gsub != null || _gpos != null;

  // GDEF.

  /// The GDEF glyph class of [glyph]: 1 base, 2 ligature, 3 mark, 4
  /// component; 0 without one.
  int glyphClass(int glyph) {
    final gdef = _gdef;
    if (gdef == null) return 0;
    final offset = gdef.u16(4);
    return offset == 0 ? 0 : _classOf(gdef, offset, glyph);
  }

  /// Whether the font's GDEF table classes its glyphs.
  late final bool hasGlyphClasses = switch (_gdef) {
    final gdef? => gdef.u16(4) != 0,
    null => false,
  };

  /// [glyph]'s properties ([GlyphProps]) by its GDEF class: a base, a
  /// ligature, or a mark with its attachment class; 0 otherwise.
  int glyphProps(int glyph) => switch (glyphClass(glyph)) {
    1 => GlyphProps.base,
    2 => GlyphProps.ligature,
    3 => GlyphProps.mark | _markAttachClass(glyph) << 8,
    _ => 0,
  };

  /// Each glyph of [run] given its properties by its GDEF class, and no
  /// ligature (HarfBuzz's start of substitution); a font without glyph
  /// classes leaves them 0, for its shaper to guess.
  void classify(List<LayoutGlyph> run) {
    for (final g in run) {
      g
        ..props = glyphProps(g.glyph)
        ..ligatureId = 0
        ..ligatureComponent = 0
        ..components = 1;
    }
  }

  int _markAttachClass(int glyph) {
    final gdef = _gdef;
    if (gdef == null) return 0;
    final offset = gdef.u16(10);
    return offset == 0 ? 0 : _classOf(gdef, offset, glyph);
  }

  bool _inMarkSet(int set, int glyph) {
    final gdef = _gdef;
    if (gdef == null || gdef.u16(2) < 2) return false;
    final sets = gdef.u16(12);
    if (sets == 0 || set >= gdef.u16(sets + 2)) return false;
    final coverage = sets + gdef.u32(sets + 4 + 4 * set);
    return _coverage(gdef, coverage, glyph) >= 0;
  }

  // Common tables.

  /// The index of [glyph] in the coverage table at [at], or -1.
  static int _coverage(_Table t, int at, int glyph) {
    final format = t.u16(at);
    if (format == 1) {
      var lo = 0;
      var hi = t.u16(at + 2) - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final g = t.u16(at + 4 + 2 * mid);
        if (g == glyph) return mid;
        if (g < glyph) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return -1;
    }
    if (format == 2) {
      var lo = 0;
      var hi = t.u16(at + 2) - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final record = at + 4 + 6 * mid;
        final start = t.u16(record);
        final end = t.u16(record + 2);
        if (glyph < start) {
          hi = mid - 1;
        } else if (glyph > end) {
          lo = mid + 1;
        } else {
          return t.u16(record + 4) + glyph - start;
        }
      }
    }
    return -1;
  }

  /// The class of [glyph] in the class definition table at [at].
  static int _classOf(_Table t, int at, int glyph) {
    final format = t.u16(at);
    if (format == 1) {
      final start = t.u16(at + 2);
      final count = t.u16(at + 4);
      final i = glyph - start;
      return i >= 0 && i < count ? t.u16(at + 6 + 2 * i) : 0;
    }
    if (format == 2) {
      var lo = 0;
      var hi = t.u16(at + 2) - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final record = at + 4 + 6 * mid;
        if (glyph < t.u16(record)) {
          hi = mid - 1;
        } else if (glyph > t.u16(record + 2)) {
          lo = mid + 1;
        } else {
          return t.u16(record + 4);
        }
      }
    }
    return 0;
  }

  // Scripts, languages and features.

  /// The indices of the lookups [feature] selects in the GSUB table (or,
  /// with [positioning], the GPOS table) for [script] (an OpenType script
  /// tag: `arab`, `hebr`, `latn`) and [language] (a language system tag:
  /// `ARA `), in order: the script's default language system when the
  /// language has none, `DFLT` when the script has none.
  List<int> lookupsFor(
    String feature, {
    required String script,
    String? language,
    bool positioning = false,
  }) {
    final t = positioning ? _gpos : _gsub;
    if (t == null) return const [];
    final langSys = _langSys(t, script, language);
    if (langSys == null) return const [];
    final featureList = t.u16(6);
    final result = <int>{};
    void addFeature(int index) {
      final record = featureList + 2 + 6 * index;
      if (t.tag(record) != feature) return;
      final table = featureList + t.u16(record + 4);
      for (var k = 0; k < t.u16(table + 2); k++) {
        result.add(t.u16(table + 4 + 2 * k));
      }
    }

    final required = t.u16(langSys + 2);
    if (required != 0xffff) addFeature(required);
    for (var i = 0; i < t.u16(langSys + 4); i++) {
      addFeature(t.u16(langSys + 6 + 2 * i));
    }
    return result.toList()..sort();
  }

  /// The language system table of [script] and [language] (else the
  /// script's default, else `DFLT`'s, else `latn`'s).
  int? _langSys(_Table t, String script, String? language) {
    final scriptList = t.u16(4);
    int? scriptTable(String tag) {
      for (var i = 0; i < t.u16(scriptList); i++) {
        final record = scriptList + 2 + 6 * i;
        if (t.tag(record) == tag) return scriptList + t.u16(record + 4);
      }
      return null;
    }

    final table =
        scriptTable(script) ?? scriptTable('DFLT') ?? scriptTable('latn');
    if (table == null) return null;
    if (language != null) {
      for (var i = 0; i < t.u16(table + 2); i++) {
        final record = table + 4 + 6 * i;
        if (t.tag(record) == language) return table + t.u16(record + 4);
      }
    }
    final defaultLangSys = t.u16(table);
    return defaultLangSys == 0 ? null : table + defaultLangSys;
  }

  /// The script table the GSUB (or, with [positioning], GPOS) table has
  /// for the first of [tags] it has one for (HarfBuzz's
  /// `select_script`), with whether it was found; else `DFLT`'s, `dflt`'s
  /// or `latn`'s, not found; null when the table has none of them.
  (String, bool)? selectScript(List<String> tags, {bool positioning = false}) {
    final t = positioning ? _gpos : _gsub;
    if (t == null) return null;
    final scriptList = t.u16(4);
    bool has(String tag) {
      for (var i = 0; i < t.u16(scriptList); i++) {
        if (t.tag(scriptList + 2 + 6 * i) == tag) return true;
      }
      return false;
    }

    for (final tag in tags) {
      if (has(tag)) return (tag, true);
    }
    for (final tag in const ['DFLT', 'dflt', 'latn']) {
      if (has(tag)) return (tag, false);
    }
    return null;
  }

  /// The default language system of [script]'s table (exactly that
  /// script's), or null.
  int? _defaultLangSys(_Table t, String script) {
    final scriptList = t.u16(4);
    for (var i = 0; i < t.u16(scriptList); i++) {
      final record = scriptList + 2 + 6 * i;
      if (t.tag(record) != script) continue;
      final table = scriptList + t.u16(record + 4);
      final offset = t.u16(table);
      return offset == 0 ? null : table + offset;
    }
    return null;
  }

  /// The lookups of [featureIndex] in the table's feature list.
  List<int> _featureLookups(_Table t, int featureIndex) {
    final featureList = t.u16(6);
    final table = featureList + t.u16(featureList + 2 + 6 * featureIndex + 4);
    return [
      for (var k = 0; k < t.u16(table + 2); k++) t.u16(table + 4 + 2 * k),
    ];
  }

  /// The lookups of [feature] in [script]'s default language system (the
  /// first feature of that tag there, as HarfBuzz finds it), or null when
  /// it has none (with [positioning], in the GPOS table).
  List<int>? featureLookups(
    String feature,
    String script, {
    bool positioning = false,
  }) {
    final t = positioning ? _gpos : _gsub;
    if (t == null) return null;
    final langSys = _defaultLangSys(t, script);
    if (langSys == null) return null;
    final featureList = t.u16(6);
    for (var i = 0; i < t.u16(langSys + 4); i++) {
      final index = t.u16(langSys + 6 + 2 * i);
      if (t.tag(featureList + 2 + 6 * index) == feature) {
        return _featureLookups(t, index);
      }
    }
    return null;
  }

  /// The tag and lookups of [script]'s default language system's required
  /// feature, if it has one.
  (String, List<int>)? requiredFeature(
    String script, {
    bool positioning = false,
  }) {
    final t = positioning ? _gpos : _gsub;
    if (t == null) return null;
    final langSys = _defaultLangSys(t, script);
    if (langSys == null) return null;
    final index = t.u16(langSys + 2);
    if (index == 0xffff) return null;
    final featureList = t.u16(6);
    return (t.tag(featureList + 2 + 6 * index), _featureLookups(t, index));
  }

  /// The lookups of the first feature [feature] of the table, whatever
  /// script lists it (HarfBuzz's global search, for `vert`), or null.
  List<int>? searchFeature(String feature, {bool positioning = false}) {
    final t = positioning ? _gpos : _gsub;
    if (t == null) return null;
    final featureList = t.u16(6);
    for (var i = 0; i < t.u16(featureList); i++) {
      if (t.tag(featureList + 2 + 6 * i) == feature) {
        return _featureLookups(t, i);
      }
    }
    return null;
  }

  /// The number of lookups of the GSUB (or GPOS) table.
  int lookupCount({bool positioning = false}) {
    final t = positioning ? _gpos : _gsub;
    if (t == null) return 0;
    return t.u16(t.u16(8));
  }

  /// Whether [script] (an OpenType script tag) has a script table of its
  /// own in the GSUB or GPOS table.
  bool hasScript(String script) {
    for (final t in [_gsub, _gpos]) {
      if (t == null) continue;
      final scriptList = t.u16(4);
      for (var i = 0; i < t.u16(scriptList); i++) {
        if (t.tag(scriptList + 2 + 6 * i) == script) return true;
      }
    }
    return false;
  }

  final Map<int, _Lookup> _gsubLookups = {};
  final Map<int, _Lookup> _gposLookups = {};

  _Lookup _lookup(_Table t, int index, {required bool positioning}) =>
      (positioning ? _gposLookups : _gsubLookups)[index] ??= () {
        final list = t.u16(8);
        final at = list + t.u16(list + 2 + 2 * index);
        var type = t.u16(at);
        final flag = t.u16(at + 2);
        final count = t.u16(at + 4);
        final extension = positioning ? 9 : 7;
        final subtables = <int>[];
        // (An extension's subtables each the real type's, at an offset of
        // 32 bits.)
        final extended = type == extension;
        for (var s = 0; s < count; s++) {
          var sub = at + t.u16(at + 6 + 2 * s);
          if (extended) {
            type = t.u16(sub + 2);
            sub += t.u32(sub + 4);
          }
          subtables.add(sub);
        }
        final markSet = flag & _Flag.useMarkFilteringSet != 0
            ? t.u16(at + 6 + 2 * count)
            : 0;
        return _Lookup(type, flag, markSet, subtables);
      }();

  // Applying lookups.

  /// Applies the GSUB lookups [lookups] in order to [run].
  void substitute(List<LayoutGlyph> run, List<LayoutLookup> lookups) {
    final t = _gsub;
    if (t == null) return;
    for (final l in lookups) {
      final lookup = _lookup(t, l.index, positioning: false);
      final c = _Context(this, t, run, lookup, l, positioning: false);
      if (lookup.type == 8) {
        for (var i = run.length - 1; i >= 0; i--) {
          if (c.applicable(i)) c.applyAt(i);
        }
      } else {
        var i = 0;
        while (i < run.length) {
          if (c.applicable(i)) {
            final next = c.applyAt(i);
            if (next != null) {
              i = next;
              continue;
            }
          }
          i++;
        }
      }
    }
  }

  /// Applies the GPOS lookups [lookups] in order to [run], whose glyphs
  /// have their advances; then, with [zeroMarks], marks take no advance
  /// (GDEF's mark glyphs, HarfBuzz's late zeroing); then each attached
  /// glyph's offset is made its pen position's, [rightToLeft] the run's
  /// logical order going right to left.
  void position(
    List<LayoutGlyph> run,
    List<LayoutLookup> lookups, {
    required bool rightToLeft,
    bool zeroMarks = false,
  }) {
    final t = _gpos;
    if (t == null) {
      if (zeroMarks) {
        for (final g in run) {
          if (g.isMark) g.xAdvance = 0;
        }
      }
      return;
    }
    for (final l in lookups) {
      final lookup = _lookup(t, l.index, positioning: true);
      final c = _Context(
        this,
        t,
        run,
        lookup,
        l,
        positioning: true,
        rightToLeft: rightToLeft,
      );
      var i = 0;
      while (i < run.length) {
        if (c.applicable(i)) {
          final next = c.applyAt(i);
          if (next != null) {
            i = next;
            continue;
          }
        }
        i++;
      }
    }
    if (zeroMarks) {
      for (final g in run) {
        if (g.isMark) g.xAdvance = 0;
      }
    }
    _propagate(run, rightToLeft: rightToLeft);
  }

  /// Each attached glyph's offset made relative to its own pen position:
  /// a mark's from its base's (the advances between taken off), a chain
  /// of attachments added up (HarfBuzz's `propagate_attachment_offsets`).
  static void _propagate(List<LayoutGlyph> run, {required bool rightToLeft}) {
    final done = List<bool>.filled(run.length, false);
    void resolve(int i) {
      if (done[i]) return;
      done[i] = true;
      final g = run[i];
      if (g.attachChain == 0) return;
      final j = i + g.attachChain;
      if (j < 0 || j >= run.length) return;
      resolve(j);
      final parent = run[j];
      if (g.attachType == 2) {
        // Cursive: only the cross-stream offset carries.
        g.yOffset += parent.yOffset;
        return;
      }
      g
        ..xOffset += parent.xOffset
        ..yOffset += parent.yOffset;
      if (!rightToLeft) {
        for (var k = j; k < i; k++) {
          g.xOffset -= run[k].xAdvance;
        }
      } else {
        for (var k = j + 1; k <= i; k++) {
          g.xOffset += run[k].xAdvance;
        }
      }
    }

    for (var i = 0; i < run.length; i++) {
      resolve(i);
    }
  }
}

/// Applying one lookup to a run: the glyphs it skips, its subtables.
final class _Context {
  new(
    this.layout,
    this.t,
    this.run,
    this.lookup,
    this.applied, {
    required this.positioning,
    this.rightToLeft = false,
  });

  final OpenTypeLayout layout;
  final _Table t;
  final List<LayoutGlyph> run;
  final _Lookup lookup;
  final LayoutLookup applied;
  final bool positioning;
  final bool rightToLeft;

  int get mask => applied.mask;

  /// The syllable the input being matched is of (0: none).
  int _syllable = 0;

  /// Whether the lookup's flag (or [flag]) skips [g], by its properties
  /// (HarfBuzz's `check_glyph_property`, negated).
  bool ignored(LayoutGlyph g, [int? flag]) {
    final f = flag ?? lookup.flag;
    final props = g.props;
    const ignorable =
        _Flag.ignoreBaseGlyphs | _Flag.ignoreLigatures | _Flag.ignoreMarks;
    if (props & f & ignorable != 0) return true;
    if (props & GlyphProps.mark != 0) {
      if (f & _Flag.useMarkFilteringSet != 0) {
        return !layout._inMarkSet(lookup.markSet, g.glyph);
      }
      if (f & 0xff00 != 0) return f & 0xff00 != props & 0xff00;
    }
    return false;
  }

  bool applicable(int i) {
    final g = run[i];
    if (g.mask & mask == 0 || ignored(g)) return false;
    _syllable = g.syllable;
    return true;
  }

  /// Whether [g] may be skipped: 2 yes (the lookup flag ignores it), 1
  /// maybe (a default ignorable), 0 no (HarfBuzz's `may_skip`). [context]:
  /// a backtrack or lookahead glyph, else an input one.
  int _maySkip(LayoutGlyph g, {required bool context}) {
    if (ignored(g)) return 2;
    final f = g.flags;
    if (f & UnicodeFlags.ignorable != 0) {
      final ignoreZwnj = positioning || (context && applied.autoZwnj);
      final ignoreZwj = context || applied.autoZwj;
      if ((ignoreZwnj || f & UnicodeFlags.zwnj == 0) &&
          (ignoreZwj || f & UnicodeFlags.zwj == 0) &&
          (positioning || f & UnicodeFlags.hidden == 0)) {
        return 1;
      }
    }
    return 0;
  }

  /// Whether [g] is a glyph [match] matches: 1 yes, 0 no, 2 maybe (no
  /// test given); [input], of the lookup's mask (HarfBuzz's `may_match`).
  int _mayMatch(
    LayoutGlyph g,
    bool Function(LayoutGlyph)? match, {
    required bool input,
  }) {
    if ((input && g.mask & mask == 0) ||
        (applied.perSyllable &&
            !positioning &&
            _syllable != 0 &&
            g.syllable != _syllable)) {
      return 0;
    }
    if (match == null) return 2;
    return match(g) ? 1 : 0;
  }

  /// Whether the glyph at [k] is the one sought: 1 found, 0 not (the
  /// search fails), 2 skipped (it goes on).
  int _step(int k, bool Function(LayoutGlyph)? match, {required bool input}) {
    final g = run[k];
    final skip = _maySkip(g, context: !input);
    if (skip == 2) return 2;
    final found = _mayMatch(g, match, input: input);
    if (found == 1 || (found == 2 && skip == 0)) return 1;
    if (skip == 0) return 0;
    return 2;
  }

  /// The next glyph after [i] the lookup doesn't skip that [match]
  /// matches, or -1: with [input], an input glyph (of the lookup's
  /// mask), else a lookahead one (HarfBuzz's skipping iterators).
  int next(int i, {bool input = false, bool Function(LayoutGlyph)? match}) {
    for (var k = i + 1; k < run.length; k++) {
      switch (_step(k, match, input: input)) {
        case 1:
          return k;
        case 0:
          return -1;
      }
    }
    return -1;
  }

  /// The glyph before [i] the lookup doesn't skip that [match] matches
  /// (a backtrack glyph; with [input], one of the lookup's mask), or -1.
  int previous(int i, {bool input = false, bool Function(LayoutGlyph)? match}) {
    for (var k = i - 1; k >= 0; k--) {
      switch (_step(k, match, input: input)) {
        case 1:
          return k;
        case 0:
          return -1;
      }
    }
    return -1;
  }

  /// Applies the lookup at [i]: the index to go on from, or null when no
  /// subtable applied.
  int? applyAt(int i) {
    for (final sub in lookup.subtables) {
      final result = positioning ? _position(sub, i) : _substitute(sub, i);
      if (result != null) return result;
    }
    return null;
  }

  /// [g] made [glyph] by a substitution: its properties marked so (a
  /// [ligature]'s, a [component]'s of a multiple substitution), its
  /// class the GDEF's of [glyph], else [guess] (HarfBuzz's
  /// `_set_glyph_class`).
  void _setClass(
    LayoutGlyph g,
    int glyph, {
    int guess = 0,
    bool ligature = false,
    bool component = false,
  }) {
    var props = g.props | GlyphProps.substituted;
    if (ligature) {
      props = (props | GlyphProps.ligated) & ~GlyphProps.multiplied;
    }
    if (component) props |= GlyphProps.multiplied;
    if (layout.hasGlyphClasses) {
      props = (props & GlyphProps.preserve) | layout.glyphProps(glyph);
    } else if (guess != 0) {
      props = (props & GlyphProps.preserve) | guess;
    }
    g
      ..glyph = glyph
      ..props = props;
  }

  int _cov(int at, int glyph) => OpenTypeLayout._coverage(t, at, glyph);

  int _cls(int at, int glyph) => OpenTypeLayout._classOf(t, at, glyph);

  // Substitution.

  int? _substitute(int sub, int i) {
    final glyph = run[i].glyph;
    final format = t.u16(sub);
    switch (lookup.type) {
      case 1:
        final index = _cov(sub + t.u16(sub + 2), glyph);
        if (index < 0) return null;
        _setClass(
          run[i],
          format == 1
              ? (glyph + t.i16(sub + 4)) & 0xffff
              : t.u16(sub + 6 + 2 * index),
        );
        return i + 1;
      case 2:
        final index = _cov(sub + t.u16(sub + 2), glyph);
        if (index < 0) return null;
        final sequence = sub + t.u16(sub + 6 + 2 * index);
        final count = t.u16(sequence);
        if (count == 0) {
          run.removeAt(i);
          return i;
        }
        final source = run[i];
        if (count == 1) {
          // (In place, not a multiplication.)
          _setClass(source, t.u16(sequence + 2));
          return i + 1;
        }
        final guess = source.isLigature ? GlyphProps.base : 0;
        final ligatureId = source.ligatureId;
        final copies = [
          for (var k = 0; k < count; k++)
            LayoutGlyph(source.glyph, source.cluster, mask: source.mask)
              ..props = source.props
              ..syllable = source.syllable
              ..flags = source.flags
              ..ligatureId = ligatureId
              // (A component's index, unless it is attached to a ligature.)
              ..ligatureComponent = ligatureId == 0
                  ? k
                  : source.ligatureComponent,
        ];
        for (final (k, copy) in copies.indexed) {
          _setClass(
            copy,
            t.u16(sequence + 2 + 2 * k),
            guess: guess,
            component: true,
          );
        }
        run.replaceRange(i, i + 1, copies);
        return i + count;
      case 3:
        final index = _cov(sub + t.u16(sub + 2), glyph);
        if (index < 0) return null;
        final set = sub + t.u16(sub + 6 + 2 * index);
        if (t.u16(set) == 0) return null;
        _setClass(run[i], t.u16(set + 2));
        return i + 1;
      case 4:
        return _ligature(sub, i);
      case 5:
        return _context(sub, i, chained: false);
      case 6:
        return _context(sub, i, chained: true);
      case 8:
        return _reverseChained(sub, i);
    }
    return null;
  }

  static int _nextLigatureId = 1;

  int? _ligature(int sub, int i) {
    final index = _cov(sub + t.u16(sub + 2), run[i].glyph);
    if (index < 0) return null;
    final set = sub + t.u16(sub + 6 + 2 * index);
    for (var l = 0; l < t.u16(set); l++) {
      final ligature = set + t.u16(set + 2 + 2 * l);
      final count = t.u16(ligature + 2);
      final positions = [i];
      var at = i;
      var matched = true;
      for (var k = 1; k < count && matched; k++) {
        final component = t.u16(ligature + 2 + 2 * k);
        at = next(at, input: true, match: (g) => g.glyph == component);
        matched = at >= 0;
        if (matched) positions.add(at);
      }
      if (!matched) continue;
      // (HarfBuzz's ligate_input: a ligature of a base and marks alone,
      // or of marks alone, takes no ligature id; the marks skipped
      // between a ligature's components are each the component they
      // follow's, a component that was a ligature counted as its own
      // components.)
      final firstMark = run[i].isMark;
      final firstBase = run[i].props & GlyphProps.base != 0;
      final restMarks = positions.skip(1).every((p) => run[p].isMark);
      final isLigature = !(restMarks && (firstBase || firstMark));
      final id = isLigature ? _nextLigatureId++ : 0;
      final first = run[i];
      for (final p in positions.skip(1)) {
        if (run[p].cluster < first.cluster) first.cluster = run[p].cluster;
      }
      var lastId = first.ligatureId;
      var lastComponents = first.components;
      var soFar = lastComponents;
      for (var k = 1; k < positions.length; k++) {
        for (var p = positions[k - 1] + 1; p < positions[k]; p++) {
          if (!isLigature) continue;
          var component = run[p].ligatureComponent;
          if (component == 0) component = lastComponents;
          run[p]
            ..ligatureId = id
            ..ligatureComponent =
                soFar -
                lastComponents +
                (component < lastComponents ? component : lastComponents);
        }
        final g = run[positions[k]];
        lastId = g.ligatureId;
        lastComponents = g.components;
        soFar += lastComponents;
      }
      // (Marks after the last component that were a ligature's follow it
      // into this one.)
      if (!(restMarks && firstMark) && lastId != 0) {
        for (var p = positions.last + 1; p < run.length; p++) {
          if (run[p].ligatureId != lastId) break;
          final component = run[p].ligatureComponent;
          if (component == 0) break;
          run[p]
            ..ligatureId = id
            ..ligatureComponent =
                soFar -
                lastComponents +
                (component < lastComponents ? component : lastComponents);
        }
      }
      positions.skip(1).toList().reversed.forEach(run.removeAt);
      _setClass(
        first,
        t.u16(ligature),
        guess: isLigature ? GlyphProps.ligature : 0,
        ligature: true,
      );
      first
        ..ligatureId = id
        ..ligatureComponent = 0
        ..components = isLigature ? soFar : 1;
      return i + 1;
    }
    return null;
  }

  /// The positions of the [inputCount] glyphs from [i] that [input]
  /// matches, the [backtrack] before and the [lookahead] after them
  /// checked too: the input positions, or null.
  List<int>? _match(
    int i,
    int inputCount,
    bool Function(int k, int glyph) input, {
    int backtrackCount = 0,
    bool Function(int k, int glyph)? backtrack,
    int lookaheadCount = 0,
    bool Function(int k, int glyph)? lookahead,
  }) {
    final positions = [i];
    var at = i;
    for (var k = 1; k < inputCount; k++) {
      at = next(at, input: true, match: (g) => input(k, g.glyph));
      if (at < 0) return null;
      positions.add(at);
    }
    var back = i;
    for (var k = 0; k < backtrackCount; k++) {
      back = previous(back, match: (g) => backtrack!(k, g.glyph));
      if (back < 0) return null;
    }
    var ahead = at;
    for (var k = 0; k < lookaheadCount; k++) {
      ahead = next(ahead, match: (g) => lookahead!(k, g.glyph));
      if (ahead < 0) return null;
    }
    return positions;
  }

  /// A contextual (or [chained]) substitution or positioning at [i].
  int? _context(int sub, int i, {required bool chained}) {
    final format = t.u16(sub);
    final glyph = run[i].glyph;
    List<int>? positions;
    var records = 0;
    var recordCount = 0;
    if (format == 1) {
      final index = _cov(sub + t.u16(sub + 2), glyph);
      if (index < 0) return null;
      final set = sub + t.u16(sub + 6 + 2 * index);
      for (var r = 0; r < t.u16(set) && positions == null; r++) {
        final rule = set + t.u16(set + 2 + 2 * r);
        if (!chained) {
          final count = t.u16(rule);
          positions = _match(
            i,
            count,
            (k, g) => g == t.u16(rule + 4 + 2 * (k - 1)),
          );
          recordCount = t.u16(rule + 2);
          records = rule + 4 + 2 * (count - 1);
        } else {
          final backCount = t.u16(rule);
          final inputAt = rule + 2 + 2 * backCount;
          final inputCount = t.u16(inputAt);
          final aheadAt = inputAt + 2 + 2 * (inputCount - 1);
          final aheadCount = t.u16(aheadAt);
          positions = _match(
            i,
            inputCount,
            (k, g) => g == t.u16(inputAt + 2 + 2 * (k - 1)),
            backtrackCount: backCount,
            backtrack: (k, g) => g == t.u16(rule + 2 + 2 * k),
            lookaheadCount: aheadCount,
            lookahead: (k, g) => g == t.u16(aheadAt + 2 + 2 * k),
          );
          final recordsAt = aheadAt + 2 + 2 * aheadCount;
          recordCount = t.u16(recordsAt);
          records = recordsAt + 2;
        }
      }
    } else if (format == 2) {
      if (_cov(sub + t.u16(sub + 2), glyph) < 0) return null;
      if (!chained) {
        final classes = sub + t.u16(sub + 4);
        final cls = _cls(classes, glyph);
        if (cls >= t.u16(sub + 6)) return null;
        final setOffset = t.u16(sub + 8 + 2 * cls);
        if (setOffset == 0) return null;
        final set = sub + setOffset;
        for (var r = 0; r < t.u16(set) && positions == null; r++) {
          final rule = set + t.u16(set + 2 + 2 * r);
          final count = t.u16(rule);
          positions = _match(
            i,
            count,
            (k, g) => _cls(classes, g) == t.u16(rule + 4 + 2 * (k - 1)),
          );
          recordCount = t.u16(rule + 2);
          records = rule + 4 + 2 * (count - 1);
        }
      } else {
        final backClasses = sub + t.u16(sub + 4);
        final inputClasses = sub + t.u16(sub + 6);
        final aheadClasses = sub + t.u16(sub + 8);
        final cls = _cls(inputClasses, glyph);
        if (cls >= t.u16(sub + 10)) return null;
        final setOffset = t.u16(sub + 12 + 2 * cls);
        if (setOffset == 0) return null;
        final set = sub + setOffset;
        for (var r = 0; r < t.u16(set) && positions == null; r++) {
          final rule = set + t.u16(set + 2 + 2 * r);
          final backCount = t.u16(rule);
          final inputAt = rule + 2 + 2 * backCount;
          final inputCount = t.u16(inputAt);
          final aheadAt = inputAt + 2 + 2 * (inputCount - 1);
          final aheadCount = t.u16(aheadAt);
          positions = _match(
            i,
            inputCount,
            (k, g) => _cls(inputClasses, g) == t.u16(inputAt + 2 + 2 * (k - 1)),
            backtrackCount: backCount,
            backtrack: (k, g) =>
                _cls(backClasses, g) == t.u16(rule + 2 + 2 * k),
            lookaheadCount: aheadCount,
            lookahead: (k, g) =>
                _cls(aheadClasses, g) == t.u16(aheadAt + 2 + 2 * k),
          );
          final recordsAt = aheadAt + 2 + 2 * aheadCount;
          recordCount = t.u16(recordsAt);
          records = recordsAt + 2;
        }
      }
    } else if (format == 3) {
      if (!chained) {
        final count = t.u16(sub + 2);
        recordCount = t.u16(sub + 4);
        positions = _match(
          i,
          count,
          (k, g) => _cov(sub + t.u16(sub + 6 + 2 * k), g) >= 0,
        );
        if (positions != null && _cov(sub + t.u16(sub + 6), glyph) < 0) {
          positions = null;
        }
        records = sub + 6 + 2 * count;
      } else {
        final backCount = t.u16(sub + 2);
        final inputAt = sub + 4 + 2 * backCount;
        final inputCount = t.u16(inputAt);
        final aheadAt = inputAt + 2 + 2 * inputCount;
        final aheadCount = t.u16(aheadAt);
        if (inputCount == 0 || _cov(sub + t.u16(inputAt + 2), glyph) < 0) {
          return null;
        }
        positions = _match(
          i,
          inputCount,
          (k, g) => _cov(sub + t.u16(inputAt + 2 + 2 * k), g) >= 0,
          backtrackCount: backCount,
          backtrack: (k, g) => _cov(sub + t.u16(sub + 4 + 2 * k), g) >= 0,
          lookaheadCount: aheadCount,
          lookahead: (k, g) => _cov(sub + t.u16(aheadAt + 2 + 2 * k), g) >= 0,
        );
        final recordsAt = aheadAt + 2 + 2 * aheadCount;
        recordCount = t.u16(recordsAt);
        records = recordsAt + 2;
      }
    }
    if (positions == null) return null;
    // The nested lookups, each at its position in the input sequence.
    var end = positions.last + 1;
    for (var r = 0; r < recordCount; r++) {
      final sequenceIndex = t.u16(records + 4 * r);
      final lookupIndex = t.u16(records + 4 * r + 2);
      if (sequenceIndex >= positions.length) continue;
      final before = run.length;
      final nested = _Context(
        layout,
        t,
        run,
        layout._lookup(t, lookupIndex, positioning: positioning),
        applied,
        positioning: positioning,
        rightToLeft: rightToLeft,
      ).._syllable = _syllable;
      final at = positions[sequenceIndex];
      if (at >= run.length) continue;
      nested.applyAt(at);
      final delta = run.length - before;
      if (delta != 0) {
        end += delta;
        for (var p = sequenceIndex + 1; p < positions.length; p++) {
          positions[p] += delta;
        }
      }
    }
    return end;
  }

  int? _reverseChained(int sub, int i) {
    final glyph = run[i].glyph;
    final index = _cov(sub + t.u16(sub + 2), glyph);
    if (index < 0) return null;
    final backCount = t.u16(sub + 4);
    final aheadAt = sub + 6 + 2 * backCount;
    final aheadCount = t.u16(aheadAt);
    var back = i;
    for (var k = 0; k < backCount; k++) {
      final coverage = sub + t.u16(sub + 6 + 2 * k);
      back = previous(back, match: (g) => _cov(coverage, g.glyph) >= 0);
      if (back < 0) return null;
    }
    var ahead = i;
    for (var k = 0; k < aheadCount; k++) {
      final coverage = sub + t.u16(aheadAt + 2 + 2 * k);
      ahead = next(ahead, match: (g) => _cov(coverage, g.glyph) >= 0);
      if (ahead < 0) return null;
    }
    final substitutes = aheadAt + 2 + 2 * aheadCount;
    if (index >= t.u16(substitutes)) return null;
    // (In place: HarfBuzz's replace_glyph_inplace, then its class kept as
    // the substituted glyph's.)
    _setClass(run[i], t.u16(substitutes + 2 + 2 * index));
    return i - 1;
  }

  // Positioning.

  /// The size of a value record of [format].
  static int _valueSize(int format) {
    var size = 0;
    for (var f = format; f != 0; f >>= 1) {
      if (f & 1 != 0) size += 2;
    }
    return size;
  }

  /// Applies the value record of [format] at [at] to [g].
  void _value(int format, int at, LayoutGlyph g) {
    var p = at;
    if (format & 1 != 0) {
      g.xOffset += t.i16(p);
      p += 2;
    }
    if (format & 2 != 0) {
      g.yOffset += t.i16(p);
      p += 2;
    }
    if (format & 4 != 0) {
      g.xAdvance += t.i16(p);
      p += 2;
    }
    if (format & 8 != 0) {
      g.yAdvance += t.i16(p);
    }
  }

  (int, int) _anchor(int at) => (t.i16(at + 2), t.i16(at + 4));

  int? _position(int sub, int i) {
    final glyph = run[i].glyph;
    final format = t.u16(sub);
    switch (lookup.type) {
      case 1:
        final index = _cov(sub + t.u16(sub + 2), glyph);
        if (index < 0) return null;
        final valueFormat = t.u16(sub + 4);
        _value(
          valueFormat,
          format == 1 ? sub + 6 : sub + 8 + _valueSize(valueFormat) * index,
          run[i],
        );
        return i + 1;
      case 2:
        return _pair(sub, i);
      case 3:
        return _cursive(sub, i);
      case 4:
        return _markToBase(sub, i);
      case 5:
        return _markToLigature(sub, i);
      case 6:
        return _markToMark(sub, i);
      case 7:
        return _context(sub, i, chained: false);
      case 8:
        return _context(sub, i, chained: true);
    }
    return null;
  }

  int? _pair(int sub, int i) {
    final first = _cov(sub + t.u16(sub + 2), run[i].glyph);
    if (first < 0) return null;
    final j = next(i, input: true);
    if (j < 0) return null;
    final format1 = t.u16(sub + 4);
    final format2 = t.u16(sub + 6);
    final size1 = _valueSize(format1);
    final size2 = _valueSize(format2);
    final second = run[j].glyph;
    if (t.u16(sub) == 1) {
      final set = sub + t.u16(sub + 10 + 2 * first);
      final count = t.u16(set);
      final recordSize = 2 + size1 + size2;
      var lo = 0;
      var hi = count - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final record = set + 2 + recordSize * mid;
        final g = t.u16(record);
        if (g == second) {
          _value(format1, record + 2, run[i]);
          _value(format2, record + 2 + size1, run[j]);
          return format2 != 0 ? j + 1 : j;
        }
        if (g < second) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return null;
    }
    final class1 = _cls(sub + t.u16(sub + 8), run[i].glyph);
    final class2 = _cls(sub + t.u16(sub + 10), second);
    final count1 = t.u16(sub + 12);
    final count2 = t.u16(sub + 14);
    if (class1 >= count1 || class2 >= count2) return null;
    final record = sub + 16 + (class1 * count2 + class2) * (size1 + size2);
    _value(format1, record, run[i]);
    _value(format2, record + size1, run[j]);
    return format2 != 0 ? j + 1 : j;
  }

  int? _cursive(int sub, int i) {
    final index = _cov(sub + t.u16(sub + 2), run[i].glyph);
    if (index < 0) return null;
    final exitOffset = t.u16(sub + 6 + 4 * index + 2);
    if (exitOffset == 0) return null;
    final j = next(i, input: true);
    if (j < 0) return null;
    final nextIndex = _cov(sub + t.u16(sub + 2), run[j].glyph);
    if (nextIndex < 0) return null;
    final entryOffset = t.u16(sub + 6 + 4 * nextIndex);
    if (entryOffset == 0) return null;
    final (exitX, exitY) = _anchor(sub + exitOffset);
    final (entryX, entryY) = _anchor(sub + entryOffset);
    final g = run[i];
    final h = run[j];
    // (HarfBuzz's CursivePosFormat1: the advances meet at the anchors.)
    if (!rightToLeft) {
      g.xAdvance = exitX + g.xOffset;
      final d = entryX + h.xOffset;
      h
        ..xAdvance -= d
        ..xOffset -= d;
    } else {
      final d = exitX + g.xOffset;
      g
        ..xAdvance -= d
        ..xOffset -= d;
      h.xAdvance = entryX + h.xOffset;
    }
    // The child (the later glyph unless the lookup says right to left)
    // hangs from the parent by the difference of the anchors' heights.
    var child = i;
    var parent = j;
    var y = entryY - exitY;
    if (lookup.flag & _Flag.rightToLeft == 0) {
      child = j;
      parent = i;
      y = -y;
    }
    run[child]
      ..attachChain = parent - child
      ..attachType = 2
      ..yOffset = y;
    return j;
  }

  /// The mark array's class and anchor of mark [index] at [marks].
  (int, (int, int)) _mark(int marks, int index) {
    final record = marks + 2 + 4 * index;
    return (t.u16(record), _anchor(marks + t.u16(record + 2)));
  }

  void _attach(int mark, int base, (int, int) markAnchor, (int, int) anchor) {
    run[mark]
      ..xOffset = anchor.$1 - markAnchor.$1
      ..yOffset = anchor.$2 - markAnchor.$2
      ..attachChain = base - mark
      ..attachType = 1;
  }

  int? _markToBase(int sub, int i) {
    final markIndex = _cov(sub + t.u16(sub + 2), run[i].glyph);
    if (markIndex < 0) return null;
    // The base: the first glyph before it not a mark (HarfBuzz skips
    // marks, whatever the lookup flag).
    var j = i - 1;
    while (j >= 0 && run[j].isMark) {
      j--;
    }
    if (j < 0) return null;
    final baseIndex = _cov(sub + t.u16(sub + 4), run[j].glyph);
    if (baseIndex < 0) return null;
    final classCount = t.u16(sub + 6);
    final (cls, markAnchor) = _mark(sub + t.u16(sub + 8), markIndex);
    final bases = sub + t.u16(sub + 10);
    final anchorOffset = t.u16(bases + 2 + 2 * (baseIndex * classCount + cls));
    if (anchorOffset == 0) return null;
    _attach(i, j, markAnchor, _anchor(bases + anchorOffset));
    return i + 1;
  }

  int? _markToLigature(int sub, int i) {
    final markIndex = _cov(sub + t.u16(sub + 2), run[i].glyph);
    if (markIndex < 0) return null;
    var j = i - 1;
    while (j >= 0 && run[j].isMark) {
      j--;
    }
    if (j < 0) return null;
    final ligIndex = _cov(sub + t.u16(sub + 4), run[j].glyph);
    if (ligIndex < 0) return null;
    final classCount = t.u16(sub + 6);
    final (cls, markAnchor) = _mark(sub + t.u16(sub + 8), markIndex);
    final ligatures = sub + t.u16(sub + 10);
    final attach = ligatures + t.u16(ligatures + 2 + 2 * ligIndex);
    final componentCount = t.u16(attach);
    if (componentCount == 0) return null;
    final mark = run[i];
    final lig = run[j];
    var component = componentCount - 1;
    if (lig.ligatureId != 0 &&
        lig.ligatureId == mark.ligatureId &&
        mark.ligatureComponent > 0) {
      component =
          (mark.ligatureComponent < componentCount
              ? mark.ligatureComponent
              : componentCount) -
          1;
    }
    final anchorOffset = t.u16(attach + 2 + 2 * (component * classCount + cls));
    if (anchorOffset == 0) return null;
    _attach(i, j, markAnchor, _anchor(attach + anchorOffset));
    return i + 1;
  }

  int? _markToMark(int sub, int i) {
    final markIndex = _cov(sub + t.u16(sub + 2), run[i].glyph);
    if (markIndex < 0) return null;
    final j = previous(i);
    if (j < 0 || !run[j].isMark) return null;
    // (HarfBuzz's MarkMarkPosFormat1: two marks on the same base, or the
    // same component of a ligature, or one a ligature itself.)
    final id1 = run[i].ligatureId;
    final comp1 = run[i].ligatureComponent;
    final id2 = run[j].ligatureId;
    final comp2 = run[j].ligatureComponent;
    final good = id1 == id2
        ? id1 == 0 || comp1 == comp2
        : (id1 > 0 && comp1 == 0) || (id2 > 0 && comp2 == 0);
    if (!good) return null;
    final m2 = run[j];
    final mark2Index = _cov(sub + t.u16(sub + 4), m2.glyph);
    if (mark2Index < 0) return null;
    final classCount = t.u16(sub + 6);
    final (cls, markAnchor) = _mark(sub + t.u16(sub + 8), markIndex);
    final marks2 = sub + t.u16(sub + 10);
    final anchorOffset = t.u16(
      marks2 + 2 + 2 * (mark2Index * classCount + cls),
    );
    if (anchorOffset == 0) return null;
    _attach(i, j, markAnchor, _anchor(marks2 + anchorOffset));
    return i + 1;
  }
}
