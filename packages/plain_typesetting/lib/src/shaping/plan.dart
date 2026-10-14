/// A shaping plan's features, as HarfBuzz 14.6's `hb-ot-map.cc` compiles
/// them: each feature its mask bits and stage, each stage of the GSUB and
/// GPOS tables its lookups in order of index (with how they match) and a
/// pause after it for the shaper.
library;

import 'package:plain_fonts/plain_fonts.dart';

/// How a feature is applied (HarfBuzz's `hb_ot_map_feature_flags_t`).
abstract final class FeatureFlags {
  /// On for every glyph.
  static const int global = 0x01;

  /// Kept even where the font has no lookups for it (a fallback applies).
  static const int hasFallback = 0x02;

  /// ZERO WIDTH NON-JOINER not skipped while matching context.
  static const int manualZwnj = 0x04;

  /// ZERO WIDTH JOINER not skipped while matching.
  static const int manualZwj = 0x08;

  /// Joiners not skipped.
  static const int manualJoiners = manualZwnj | manualZwj;

  /// Looked for in every script of the table (`vert`).
  static const int globalSearch = 0x10;

  /// Alternates chosen at random (`rand`).
  static const int random = 0x20;

  /// Matched within a syllable.
  static const int perSyllable = 0x40;

  /// [global] with [manualJoiners].
  static const int globalManualJoiners = global | manualJoiners;

  /// [global] with [hasFallback].
  static const int globalHasFallback = global | hasFallback;
}

/// What a shaper does at a pause between stages: the stage's glyphs
/// given back to it (to reorder them, to set masks).
typedef PauseFunction = void Function(ShapeState state);

/// The state of a run being shaped that pauses see: its glyphs and the
/// plan.
abstract interface class ShapeState {
  /// The glyphs, in logical order.
  List<LayoutGlyph> get glyphs;

  /// The plan.
  ShapePlan get plan;

  /// The font's layout tables.
  OpenTypeLayout get layout;

  /// Whether the font has a glyph for [codePoint], and which.
  int glyphFor(int codePoint);
}

final class _FeatureInfo {
  new(this.tag, this.seq, this.maxValue, this.flags)
    : defaultValue = flags & FeatureFlags.global != 0 ? maxValue : 0;

  final String tag;
  final int seq;
  int maxValue;
  int flags;
  int defaultValue;
  final List<int> stage = [0, 0];
}

/// A compiled feature: its mask, the shift of its value, its 1-mask.
final class FeatureMap {
  /// Feature [tag], its value in [mask] from bit [shift].
  new(this.tag, this.shift, this.mask);

  /// The feature's tag.
  final String tag;

  /// The bit its value starts at.
  final int shift;

  /// The bits of its value.
  final int mask;

  /// Its value 1, in its bits.
  int get oneMask => (1 << shift) & mask;
}

/// A stage of a table: the lookups up to [lastLookup] and the pause after.
final class StageMap {
  /// A stage ending before lookup [lastLookup], [pause] after it.
  const new(this.lastLookup, this.pause);

  /// The index after the stage's last lookup.
  final int lastLookup;

  /// What the shaper does after it, if anything.
  final PauseFunction? pause;
}

/// A plan's features before they are compiled (HarfBuzz's
/// `hb_ot_map_builder_t`): their flags, values and stages, the pauses.
final class PlanBuilder {
  /// A builder for [layout], the GSUB and GPOS script tags chosen
  /// [gsubScript] and [gposScript].
  new(this.layout, this.gsubScript, this.gposScript);

  /// The font's layout tables.
  final OpenTypeLayout layout;

  /// The script tag the GSUB table's lookups are taken from, if any.
  final String? gsubScript;

  /// The script tag the GPOS table's lookups are taken from, if any.
  final String? gposScript;

  final List<_FeatureInfo> _features = [];
  final List<List<(int, PauseFunction?)>> _stages = [[], []];
  final List<int> _currentStage = [0, 0];

  /// Whether the plan is simple (no shaper features, no user ones): then
  /// features keep their order of addition.
  bool isSimple = true;

  /// Adds [tag], applied as [flags] say, with values up to [value].
  void addFeature(String tag, {int flags = 0, int value = 1}) {
    _features.add(
      _FeatureInfo(tag, _features.length + 1, value, flags)
        ..stage[0] = _currentStage[0]
        ..stage[1] = _currentStage[1],
    );
  }

  /// Adds [tag] as a global feature.
  void enableFeature(String tag, {int flags = 0, int value = 1}) =>
      addFeature(tag, flags: flags | FeatureFlags.global, value: value);

  /// Ends a GSUB stage, [pause] to run after it.
  void addGsubPause([PauseFunction? pause]) => _addPause(0, pause);

  /// Ends a GPOS stage.
  void addGposPause([PauseFunction? pause]) => _addPause(1, pause);

  void _addPause(int table, PauseFunction? pause) {
    _stages[table].add((_currentStage[table], pause));
    _currentStage[table]++;
  }

  /// Whether the font's chosen script has [tag] in either table.
  bool hasFeature(String tag) =>
      (gsubScript != null && layout.featureLookups(tag, gsubScript!) != null) ||
      (gposScript != null &&
          layout.featureLookups(tag, gposScript!, positioning: true) != null);

  /// The plan (HarfBuzz's `hb_ot_map_builder_t::compile`).
  ShapePlan compile() {
    const globalShift = 31;
    const globalMask = 1 << globalShift;
    var mask = globalMask;
    final scripts = [gsubScript, gposScript];
    final required = [
      for (final (table, script) in scripts.indexed)
        if (script == null)
          null
        else
          layout.requiredFeature(script, positioning: table == 1),
    ];
    final requiredStage = [0, 0];

    // Sort the features and merge duplicates.
    final infos = [..._features];
    if (infos.isNotEmpty) {
      if (!isSimple) {
        infos.sort((a, b) {
          final c = a.tag.compareTo(b.tag);
          return c != 0 ? c : a.seq - b.seq;
        });
      }
      final merged = <_FeatureInfo>[infos.first];
      for (final f in infos.skip(1)) {
        final j = merged.last;
        if (f.tag != j.tag) {
          merged.add(f);
          continue;
        }
        if (f.flags & FeatureFlags.global != 0) {
          j
            ..flags |= FeatureFlags.global
            ..maxValue = f.maxValue
            ..defaultValue = f.defaultValue;
        } else {
          if (j.flags & FeatureFlags.global != 0) {
            j.flags ^= FeatureFlags.global;
          }
          if (f.maxValue > j.maxValue) j.maxValue = f.maxValue;
        }
        j
          ..flags |= f.flags & FeatureFlags.hasFallback
          ..stage[0] = j.stage[0] < f.stage[0] ? j.stage[0] : f.stage[0]
          ..stage[1] = j.stage[1] < f.stage[1] ? j.stage[1] : f.stage[1];
      }
      infos
        ..clear()
        ..addAll(merged);
    }

    // Allocate the bits.
    var nextBit = 4;
    final features = <(FeatureMap, _FeatureInfo, List<List<int>?>)>[];
    for (final info in infos) {
      final bitsNeeded =
          info.flags & FeatureFlags.global != 0 && info.maxValue == 1
          ? 0
          : _bitStorage(info.maxValue).clamp(0, 8);
      if (info.maxValue == 0 || nextBit + bitsNeeded >= globalShift) continue;
      final lookups = <List<int>?>[null, null];
      var found = false;
      for (var table = 0; table < 2; table++) {
        if (required[table]?.$1 == info.tag) {
          requiredStage[table] = info.stage[table];
        }
        if (scripts[table] case final script?) {
          lookups[table] = layout.featureLookups(
            info.tag,
            script,
            positioning: table == 1,
          );
          if (lookups[table] != null) found = true;
        }
      }
      if (!found && info.flags & FeatureFlags.globalSearch != 0) {
        for (var table = 0; table < 2; table++) {
          lookups[table] = layout.searchFeature(
            info.tag,
            positioning: table == 1,
          );
          if (lookups[table] != null) found = true;
        }
      }
      if (!found && info.flags & FeatureFlags.hasFallback == 0) continue;
      final FeatureMap map;
      if (info.flags & FeatureFlags.global != 0 && info.maxValue == 1) {
        map = FeatureMap(info.tag, globalShift, globalMask);
      } else {
        final featureMask = (1 << (nextBit + bitsNeeded)) - (1 << nextBit);
        map = FeatureMap(info.tag, nextBit, featureMask);
        nextBit += bitsNeeded;
        mask |= (info.defaultValue << map.shift) & map.mask;
      }
      features.add((map, info, lookups));
    }
    if (isSimple) {
      features.sort((a, b) => a.$1.tag.compareTo(b.$1.tag));
    }
    addGsubPause();
    addGposPause();

    final lookups = <List<LayoutLookup>>[[], []];
    final stages = <List<StageMap>>[[], []];
    for (var table = 0; table < 2; table++) {
      final out = lookups[table];
      final count = layout.lookupCount(positioning: table == 1);
      var stageIndex = 0;
      var last = 0;
      void add(
        List<int> indices,
        int lookupMask, {
        bool autoZwnj = true,
        bool autoZwj = true,
        bool perSyllable = false,
      }) {
        for (final index in indices) {
          if (index >= count) continue;
          out.add(
            LayoutLookup(
              index,
              lookupMask,
              autoZwnj: autoZwnj,
              autoZwj: autoZwj,
              perSyllable: perSyllable,
            ),
          );
        }
      }

      for (var stage = 0; stage < _currentStage[table]; stage++) {
        if (required[table] case (_, final indices)
            when requiredStage[table] == stage) {
          add(indices, globalMask);
        }
        for (final (map, info, featureLookups) in features) {
          if (info.stage[table] != stage) continue;
          if (featureLookups[table] case final indices?) {
            add(
              indices,
              map.mask,
              autoZwnj: info.flags & FeatureFlags.manualZwnj == 0,
              autoZwj: info.flags & FeatureFlags.manualZwj == 0,
              perSyllable: info.flags & FeatureFlags.perSyllable != 0,
            );
          }
        }
        // Sort the stage's lookups and merge duplicates.
        if (last + 1 < out.length) {
          final stageLookups = out.sublist(last)
            ..sort((a, b) => a.index - b.index);
          final merged = <LayoutLookup>[];
          for (final l in stageLookups) {
            if (merged.isNotEmpty && merged.last.index == l.index) {
              final m = merged.removeLast();
              merged.add(
                LayoutLookup(
                  m.index,
                  m.mask | l.mask,
                  autoZwnj: m.autoZwnj && l.autoZwnj,
                  autoZwj: m.autoZwj && l.autoZwj,
                  perSyllable: m.perSyllable,
                ),
              );
            } else {
              merged.add(l);
            }
          }
          out.replaceRange(last, out.length, merged);
        }
        last = out.length;
        if (stageIndex < _stages[table].length &&
            _stages[table][stageIndex].$1 == stage) {
          stages[table].add(StageMap(last, _stages[table][stageIndex].$2));
          stageIndex++;
        }
      }
    }
    return ShapePlan._(
      globalMask: mask,
      features: {for (final (map, _, _) in features) map.tag: map},
      lookups: lookups,
      stages: stages,
      gsubScript: gsubScript,
      gposScript: gposScript,
    );
  }

  static int _bitStorage(int v) => v <= 0 ? 0 : v.bitLength;
}

/// A compiled plan: the global mask, the features' masks, and each
/// table's lookups by stage.
final class ShapePlan {
  new _({
    required this.globalMask,
    required this.features,
    required this.lookups,
    required this.stages,
    required this.gsubScript,
    required this.gposScript,
  });

  /// The mask every glyph starts with: the global bit and the global
  /// features' default values.
  final int globalMask;

  /// The features kept, by tag.
  final Map<String, FeatureMap> features;

  /// The GSUB (0) and GPOS (1) lookups, in the order they apply.
  final List<List<LayoutLookup>> lookups;

  /// The GSUB (0) and GPOS (1) stages.
  final List<List<StageMap>> stages;

  /// The GSUB table's script tag, if any.
  final String? gsubScript;

  /// The GPOS table's script tag, if any.
  final String? gposScript;

  /// [tag]'s mask (0: the plan doesn't have it).
  int maskOf(String tag) => features[tag]?.mask ?? 0;

  /// [tag]'s 1-mask (0: the plan doesn't have it).
  int oneMaskOf(String tag) => features[tag]?.oneMask ?? 0;

  /// Applies the lookups of table [table] (0 GSUB, 1 GPOS) to [state]'s
  /// glyphs, stage by stage, each pause after its stage; [apply] applies
  /// a stage's lookups.
  void run(
    int table,
    ShapeState state,
    void Function(List<LayoutLookup> lookups) apply,
  ) {
    var i = 0;
    for (final stage in stages[table]) {
      if (stage.lastLookup > i) {
        apply(lookups[table].sublist(i, stage.lastLookup));
        i = stage.lastLookup;
      }
      stage.pause?.call(state);
    }
  }
}
