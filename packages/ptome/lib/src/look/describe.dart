/// A look described for people (ADR-0023 decision 5): a Markdown table of
/// what it sets in each medium, the PDF's, HTML's and an EPUB's, each
/// unset value named as the output's base's. `doc/style.md`'s values are
/// the house look's, written by `tool/style_table.dart`.
library;

import 'package:ptome/src/look/model.dart';

/// The columns: each output, its medium, and what decides where the look
/// doesn't.
const List<(String, Medium, String)> _columns = [
  ('PDF', Medium.print, "asciidoctor-pdf's"),
  ('HTML and website', Medium.screen, "Asciidoctor's"),
  ('EPUB', Medium.ebook, "asciidoctor-epub3's"),
];

/// The Markdown table of what [look] sets in each medium.
String describeLook(Look look) {
  final tokens = look.tokens;
  final rows = <(String, String Function(Medium))>[];
  String? face(String role, Medium m) {
    final f = tokens.fonts[role]?.at(m);
    if (f == null) return null;
    final parts = [
      ?f.family,
      if (f.weight case final w?) _weight(w),
      if (f.shape == FontShape.italic) 'italic',
      if (f.size case final s?) '${_number(s)} of the text',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  void row(String name, String? Function(Medium) value) =>
      rows.add((name, (m) => value(m) ?? ''));

  row('Text face', (m) => face('text', m));
  row('Heading and label face', (m) => face('display', m));
  row('Code face', (m) => face('code', m));
  for (final role in tokens.fonts.keys) {
    if (!const {'text', 'display', 'code'}.contains(role)) {
      row('Face `$role`', (m) => face(role, m));
    }
  }
  row('Text size', (m) => tokens.textSize?.of(m)?.toString());
  row(
    'Heading sizes',
    (m) => tokens.headingSizes?.of(m)?.map((l) => '$l').join(' / '),
  );
  row('Line spacing', (m) => tokens.leading?.of(m)?.let(_number));
  row('Measure', (m) => tokens.measure?.of(m)?.toString());
  row('Paragraphs', (m) {
    final p = tokens.paragraph;
    if (p == null) return null;
    final parts = [
      if (p.signal?.of(m) == ParagraphSignal.space) 'space between',
      if (p.signal?.of(m) == ParagraphSignal.indent) 'first-line indent',
      if (p.space?.of(m) case final space?) '$space apart',
      if (p.indent?.of(m) case final indent?) 'indented $indent',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  });
  row('Alignment', (m) => tokens.align?.of(m)?.name);
  row(
    'Hyphenation',
    (m) => switch (tokens.hyphenate?.of(m)) {
      true => 'hyphenated',
      false => 'not hyphenated',
      null => null,
    },
  );
  row('Page', (m) {
    final page = tokens.page;
    if (page == null || m != Medium.print) return null;
    return [
      ?page.size,
      if (page.margin case final margin?)
        'margins ${margin.map((l) => '$l').join(' ')}',
      if (page.inner case final inner?) 'inner $inner',
      if (page.outer case final outer?) 'outer $outer',
    ].join(', ');
  });
  for (final MapEntry(key: target, value: style) in look.styles.entries) {
    row(_name(target), (m) => _style(style.at(m)));
  }

  String cell(String name, String value, Medium medium, String base) {
    if (value.isNotEmpty) return value;
    // (An e-book's body text the reader's, by the house rule.)
    if (medium == Medium.ebook &&
        const {
          'Text size',
          'Line spacing',
          'Alignment',
          'Measure',
        }.contains(name)) {
      return "the reader's";
    }
    return base;
  }

  final out = StringBuffer()
    ..writeln('| | ${_columns.map((c) => c.$1).join(' | ')} |')
    ..writeln('| --- |${' --- |' * _columns.length}');
  for (final (name, value) in rows) {
    final cells = [
      for (final (_, medium, base) in _columns)
        cell(name, value(medium), medium, base),
    ];
    // (A row the look sets nowhere says nothing.)
    if (cells.indexed.every((c) => c.$2 == _columns[c.$1].$3)) continue;
    out.writeln('| $name | ${cells.join(' | ')} |');
  }
  final colors = [
    for (final MapEntry(:key, :value) in tokens.colors.entries)
      '`$key` ${_media(value)}',
  ];
  if (colors.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Colors: ${colors.join(', ')}.');
  }
  final rules = [
    for (final MapEntry(:key, :value) in tokens.rules.entries)
      '`$key` ${_media(value)}',
  ];
  if (rules.isNotEmpty) out.writeln('Rules: ${rules.join(', ')}.');
  return '$out';
}

/// A value by medium, as text: `#2156A5`, or `0.5pt (print), 1px
/// (screen)`.
String _media<T extends Object>(ByMedium<T> value) => switch (value) {
  ByMedium(:final all?, each: Map(isEmpty: true)) => '$all',
  ByMedium(:final all, :final each) => [
    if (all != null) '$all',
    for (final MapEntry(key: m, value: v) in each.entries) '$v (${m.name})',
  ].join(', '),
};

String _name(StyleTarget target) => switch (target) {
  ElementTarget(:final element) => 'Style `${element.wire}`',
  RoleTarget(:final role) => 'Role `.$role`',
};

String _weight(FontWeight weight) => switch (weight) {
  400 => 'normal',
  700 => 'bold',
  _ => 'weight $weight',
};

String _number(num value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

String _color(ColorValue value) => switch (value) {
  ColorToken(:final name) => '`$name`',
  ColorLiteral(:final color) => '$color',
  NoColor() => 'none',
};

String _rule(RuleValue value) => switch (value) {
  NoRule() => 'none',
  Rule(:final width, :final color) => [
    switch (width) {
      WidthLength(:final length) => '$length',
      WidthToken(:final name) => '`$name`',
    },
    if (color != null) _color(color),
  ].join(' '),
};

/// What [style] sets, as text; null for nothing.
String? _style(MediumStyle style) {
  final parts = [
    if (style.font case final font?) '`$font` face',
    if (style.weight case final weight?) _weight(weight),
    if (style.shape == FontShape.italic) 'italic',
    if (style.variant case final variant?) variant.wire,
    if (style.size case final size?)
      switch (size) {
        SizeLength(:final length) => '$length',
        SizeRatio(:final ratio) => '${_number(ratio)} of the text',
        SizeToken(:final name) => '`$name` size',
      },
    if (style.color case final color?) 'color ${_color(color)}',
    if (style.background case final background?)
      'background ${_color(background)}',
    if (style.leading case final leading?) 'line spacing ${_number(leading)}',
    if (style.spaceBefore case final space?) '$space above',
    if (style.spaceAfter case final space?) '$space below',
    if (style.padding case final padding?) 'padding $padding',
    if (style.radius case final radius?) 'corners $radius',
    if (style.border case final border?) 'border ${_rule(border)}',
    if (style.rule case final rule?) 'rule beside ${_rule(rule)}',
    if (style.keepWithNext == true) 'kept with what follows',
    if (style.frame case final frame?) 'frame ${_rule(frame)}',
    if (style.frameSides case final sides?) 'sides ${_rule(sides)}',
    if (style.rows case final rows?) 'rows ${_rule(rows)}',
    if (style.columns case final columns?) 'columns ${_rule(columns)}',
    if (style.headRule case final head?) 'under the head ${_rule(head)}',
    if (style.stripes case final stripes?) 'stripes ${_color(stripes)}',
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
