/// `ptome look explain` (ADR-0023 decision 4): what each item of a look
/// became in each output (its theme keys, custom properties and CSS
/// declarations), and what an output left out and why. The outcomes are
/// the compilers' own ([LookOutcome]), the ones their warnings are made
/// of, so the explanation and the warnings can't disagree.
library;

import 'package:ptome/src/look/css.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/look/outcome.dart';
import 'package:ptome/src/pdf/look_theme.dart';

/// An output a look compiles to.
enum LookOutput {
  /// The PDF: theme keys over asciidoctor-pdf's `default` theme.
  pdf('PDF', {Medium.print}, 'pdf'),

  /// HTML pages and the website: CSS after Asciidoctor's stylesheet.
  html('HTML', {Medium.screen, Medium.print}, 'css'),

  /// An EPUB: CSS after asciidoctor-epub3's stylesheet.
  epub3('EPUB', {Medium.ebook}, 'epub-css');

  new(this.label, this.media, this.own);

  /// Its name in the explanation.
  final String label;

  /// The media its values are read in.
  final Set<Medium> media;

  /// The part of a look file in its own terms.
  final String own;

  /// The output a `--format` value names, or null.
  static LookOutput? named(String name) => switch (name) {
    'pdf' => pdf,
    'html' || 'html5' => html,
    'epub3' || 'epub' => epub3,
    _ => null,
  };
}

/// The explanation of [look] for [outputs], as text.
String explainLook(
  Look look, [
  Set<LookOutput> outputs = const {...LookOutput.values},
]) {
  final items = _items(look);
  final outcomes = {
    for (final output in LookOutput.values)
      if (outputs.contains(output)) output: _outcomes(look, output, items),
  };
  // (Items only an outcome names, as an EPUB's alignment left to the
  // reader when the look sets none, after the look's own.)
  for (final byItem in outcomes.values) {
    for (final item in byItem.keys) {
      items.putIfAbsent(item, () => const {});
    }
  }
  final width = outcomes.keys.map((o) => o.label.length).fold(0, _max) + 2;
  final out = StringBuffer('look ${look.name}');
  if (look.directory case final directory?) out.write(' ($directory)');
  out
    ..writeln(': what each item became, by output')
    ..writeln();
  var warnings = 0;
  for (final MapEntry(key: item, value: media) in items.entries) {
    out.writeln(item);
    for (final MapEntry(key: output, value: byItem) in outcomes.entries) {
      final these = byItem[item] ?? const <LookOutcome>[];
      // (What every medium has, print need not repeat.)
      final everywhere = {
        for (final outcome in these)
          if (outcome case Became(:final result, medium: null)) result,
      };
      final lines = {
        for (final outcome in these)
          switch (outcome) {
            Became(:final result, medium: Medium.print)
                when everywhere.contains(result) =>
              null,
            Became(:final result, :final medium) => [
              _abbreviate(result),
              if (medium != null && output.media.length > 1) '(${medium.name})',
            ].join('  '),
            Dropped(:final why, :final warned) =>
              'left out: $why${warned ? ' (a warning)' : ''}',
          },
      }.nonNulls.toList();
      warnings += these.whereType<Dropped>().where((d) => d.warned).length;
      if (lines.isEmpty) lines.add('— ${_nothing(item, media, output)}');
      for (final (i, line) in lines.indexed) {
        final label = i == 0 ? output.label : '';
        out.writeln('  ${label.padRight(width)}$line');
      }
    }
  }
  if (warnings > 0) {
    out
      ..writeln()
      ..writeln(
        '$warnings ${warnings == 1 ? 'warning' : 'warnings'}: what the '
        "look sets that an output can't render.",
      );
  }
  return '$out';
}

int _max(int a, int b) => a > b ? a : b;

/// What [output]'s compiler made of [look], by item: an outcome of a
/// part of one of [items] (a rule's color) is that item's.
Map<String, List<LookOutcome>> _outcomes(
  Look look,
  LookOutput output,
  Map<String, Set<Medium>> items,
) {
  final byItem = <String, List<LookOutcome>>{};
  String itemOf(String item) {
    for (var part = item; part.contains('.');) {
      if (items.containsKey(part)) return part;
      part = part.substring(0, part.lastIndexOf('.'));
    }
    return item;
  }

  void trace(LookOutcome outcome) =>
      (byItem[itemOf(outcome.item)] ??= []).add(outcome);
  switch (output) {
    case LookOutput.pdf:
      lookThemeEntries(look, trace: trace);
    case LookOutput.html:
      lookCss(look, CssTarget.html, trace: trace);
    case LookOutput.epub3:
      lookCss(look, CssTarget.epub, trace: trace);
  }
  return byItem;
}

/// Why [output] made nothing of [item], set in [media].
String _nothing(String item, Set<Medium> media, LookOutput output) {
  if (const {'pdf', 'css', 'epub-css'}.contains(item)) {
    return item == output.own ? 'empty' : "another output's";
  }
  if (media.isEmpty) return 'not set';
  if (media.intersection(output.media).isEmpty) {
    return 'set for ${media.map((m) => m.name).join(' and ')} only';
  }
  if (RegExp(r'^tokens\.(font|color|rule)\.|^tokens\.size\.small$')
      .hasMatch(item)) {
    return 'read by the styles that name it';
  }
  return 'nothing';
}

/// [css] with a long selector list shortened to its first selector and a
/// count of the others.
String _abbreviate(String css) {
  final brace = css.indexOf('{');
  if (brace < 0 || css.startsWith('@')) return css;
  final selectors = css.substring(0, brace).split(',');
  if (selectors.length < 3) return css;
  return '${selectors.first}, … (${selectors.length - 1} more)'
      '${css.substring(brace)}';
}

/// The items [look] sets, in its file's order, each with the media it
/// sets them in (every medium for a plain value).
Map<String, Set<Medium>> _items(Look look) {
  final items = <String, Set<Medium>>{};
  void add(String item, Iterable<ByMedium<Object>?> values) {
    final media = {
      for (final value in values.nonNulls)
        ...value.all != null ? Medium.values : value.each.keys,
    };
    if (media.isNotEmpty) items[item] = media;
  }

  final tokens = look.tokens;
  for (final MapEntry(key: role, value: face) in tokens.fonts.entries) {
    add('tokens.font.$role', [face.family, face.weight, face.shape, face.size]);
  }
  add('tokens.size.text', [tokens.textSize]);
  add('tokens.size.headings', [tokens.headingSizes]);
  add('tokens.size.small', [tokens.small]);
  add('tokens.leading', [tokens.leading]);
  add('tokens.measure', [tokens.measure]);
  if (tokens.paragraph case final p?) {
    add('tokens.paragraph', [p.signal, p.space, p.indent]);
  }
  add('tokens.align', [tokens.align]);
  add('tokens.hyphenate', [tokens.hyphenate]);
  for (final MapEntry(:key, :value) in tokens.colors.entries) {
    add('tokens.color.$key', [value]);
  }
  for (final MapEntry(:key, :value) in tokens.rules.entries) {
    add('tokens.rule.$key', [value]);
  }
  if (tokens.page != null) items['tokens.page'] = {Medium.print};
  for (final MapEntry(key: target, value: style) in look.styles.entries) {
    final item = 'styles.$target';
    for (final (property, value) in <(String, ByMedium<Object>?)>[
      ('font', style.font),
      ('weight', style.weight),
      ('style', style.shape),
      ('variant', style.variant),
      ('size', style.size),
      ('color', style.color),
      ('background', style.background),
      ('leading', style.leading),
      ('space-before', style.spaceBefore),
      ('space-after', style.spaceAfter),
      ('padding', style.padding),
      ('radius', style.radius),
      ('border', style.border),
      ('rule', style.rule),
      ('keep-with-next', style.keepWithNext),
      ('number', style.number),
      ('hang', style.hang),
      ('frame', style.frame),
      ('frame-sides', style.frameSides),
      ('rows', style.rows),
      ('columns', style.columns),
      ('head-rule', style.headRule),
      ('stripes', style.stripes),
    ]) {
      add('$item.$property', [value]);
    }
  }
  for (final name in look.templates.named.keys) {
    items['templates.$name'] = {...Medium.values};
  }
  if (look.templates.titlePage case final page?) {
    if (page.recto.isNotEmpty) {
      items['templates.title-page.recto'] = {...Medium.values};
    }
    if (page.verso.isNotEmpty) {
      items['templates.title-page.verso'] = {...Medium.values};
    }
  }
  if (look.pdf.isNotEmpty) items['pdf'] = {Medium.print};
  if (look.css.isNotEmpty) items['css'] = {Medium.screen, Medium.print};
  if (look.epubCss.isNotEmpty) items['epub-css'] = {Medium.ebook};
  return items;
}
