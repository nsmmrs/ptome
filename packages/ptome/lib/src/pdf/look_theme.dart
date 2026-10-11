/// A look's PDF theme (ADR-0023 decision 2): its tokens and styles as the
/// theme keys of the modern engine and asciidoctor-pdf, written as a theme
/// file writes them and laid over the `default` theme, then the look's own
/// `pdf:` entries. What the PDF doesn't apply by design is left out
/// quietly; anything else it can't render is reported.
library;

import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/look/outcome.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:ptome/src/pdf/yaml11.dart';

/// The PDF theme of [look]: [base]'s, with the look's over it; what the
/// PDF can't render of it reported to [warn].
Theme lookTheme(
  Look look, {
  String base = 'default',
  ThemeLoader? loader,
  void Function(String message)? warn,
}) {
  final compiler = _Compiler(look, warn ?? (_) {}, (_) {});
  final entries = compiler.compile();
  return (loader ?? ThemeLoader()).loadOver(base, entries, [
    for (final section in look.pdf)
      if (yamlToY(section) case final YMap map) map,
  ])..directory = look.directory;
}

/// The theme keys a look compiles to, in order; what each item became,
/// or why it was left out, reported to [trace] (`ptome look explain`).
Map<String, Y> lookThemeEntries(
  Look look, {
  void Function(String message)? warn,
  void Function(LookOutcome outcome)? trace,
}) => _Compiler(look, warn ?? (_) {}, trace ?? (_) {}).compile();

/// The theme category of each element.
const Map<LookElement, String> _categories = {
  LookElement.heading: 'heading',
  LookElement.h1: 'heading_h1',
  LookElement.h2: 'heading_h2',
  LookElement.h3: 'heading_h3',
  LookElement.h4: 'heading_h4',
  LookElement.h5: 'heading_h5',
  LookElement.h6: 'heading_h6',
  LookElement.title: 'title_page_title',
  LookElement.subtitle: 'title_page_subtitle',
  LookElement.paragraph: 'prose',
  LookElement.link: 'link',
  LookElement.code: 'codespan',
  LookElement.codeBlock: 'code',
  LookElement.caption: 'caption',
  LookElement.quote: 'quote',
  LookElement.admonition: 'admonition',
  LookElement.admonitionLabel: 'admonition_label',
  LookElement.sidebar: 'sidebar',
  LookElement.sidebarTitle: 'sidebar_title',
  LookElement.table: 'table',
  LookElement.tableHead: 'table_head',
  LookElement.footnote: 'footnotes',
};

final class _Compiler {
  new(this.look, this.warn, this.trace);

  final Look look;
  final void Function(String message) warn;
  final void Function(LookOutcome outcome) trace;
  final Map<String, Y> out = {};

  /// The item the keys being set come from.
  String _item = '';

  Tokens get tokens => look.tokens;

  void _unsupported(String item, [String why = 'has no effect in the PDF']) {
    warn('look ${look.name}: $item $why');
    trace(Dropped(item, why));
  }

  Map<String, Y> compile() {
    _tokens();
    for (final MapEntry(:key, value: style) in look.styles.entries) {
      _style(key, style);
    }
    for (final name in look.templates.named.keys) {
      trace(Became('templates.$name', 'the attribute $name-template'));
    }
    if (look.templates.titlePage case final page?) {
      for (final (side, slots) in [
        ('recto', page.recto),
        ('verso', page.verso),
      ]) {
        if (slots.isEmpty) continue;
        _item = 'templates.title-page.$side';
        _set(
          'title_page_$side',
          YList([for (final slot in slots) _slot(slot)]),
        );
      }
    }
    if (look.pdf.isNotEmpty) {
      trace(const Became('pdf', 'its keys, after these, as written'));
    }
    return out;
  }

  // Values, as a theme file writes them.

  static Y _number(num value) => YScalar(ThemeNumber(value));

  static Y _string(String value) => YScalar(ThemeString(value));

  /// A length: points as a number, other units as written (the theme
  /// loader converts `in`, `mm`, `px`; `em` stays relative).
  static Y _length(Length length) =>
      length.unit == LengthUnit.pt ? _number(length.value) : _string('$length');

  Y? _color(ColorValue value, String item) => switch (value) {
    NoColor() => _string('transparent'),
    ColorLiteral(:final color) => _string(color.hex),
    ColorToken(:final name) => switch (tokens.colors[name]) {
      // (A token without a print value is another medium's.)
      final color? => switch (color.of(Medium.print)) {
        final c? => _string(c.hex),
        null => _noValue(item, 'color', name),
      },
      null => () {
        _unsupported(item, 'names no color token $name');
        return null;
      }(),
    },
  };

  Y? _width(WidthValue value, String item) => switch (value) {
    WidthLength(:final length) => _length(length),
    WidthToken(:final name) => switch (tokens.rules[name]) {
      final length? => switch (length.of(Medium.print)) {
        final l? => _length(l),
        null => _noValue(item, 'rule', name),
      },
      null => () {
        _unsupported(item, 'names no rule token $name');
        return null;
      }(),
    },
  };

  /// Nothing, for [item], which names a [kind] token without a print
  /// value.
  Y? _noValue(String item, String kind, String name) {
    trace(
      Dropped(item, 'the $kind token $name has no print value', warned: false),
    );
    return null;
  }

  /// Sets [key] to [value] (unless null), from [items] (the current
  /// item's).
  void _set(String key, Y? value, [List<String>? items]) {
    if (value == null) return;
    out[key] = value;
    for (final item in items ?? [_item]) {
      trace(Became(item, '$key: ${_show(value)}'));
    }
  }

  /// [value] as a theme file writes it.
  static String _show(Y value) => switch (value) {
    YScalar(value: ThemeString(:final value))
        when num.tryParse(value) != null || !_plain.hasMatch(value) =>
      "'${value.replaceAll("'", "''")}'",
    YScalar(:final value) => value.rubyString,
    YList(:final items) => '[${items.map(_show).join(', ')}]',
    YMap(:final entries) => '{${entries.entries.map(_entry).join(', ')}}',
  };

  /// Text a theme file writes without quotes.
  static final RegExp _plain = RegExp(r'^[\w.%+-](?:[\w .%+/-]*[\w.%+/-])?$');

  static String _entry(MapEntry<String, Y> entry) =>
      '${entry.key}: ${_show(entry.value)}';

  /// A face's weight and shape as asciidoctor-pdf's font style.
  /// (The bold face for 600 and up.)
  static String _fontStyle(FontWeight? weight, FontShape? shape) =>
      switch (((weight ?? 400) >= 600, shape ?? FontShape.normal)) {
        (true, FontShape.italic) => 'bold_italic',
        (true, FontShape.normal) => 'bold',
        (false, FontShape.italic) => 'italic',
        (false, FontShape.normal) => 'normal',
      };

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// A title page's slot as the theme writes it: a part's name, or a
  /// mapping (`content` or `attribute`, `role`, `margin_top`,
  /// `margin_bottom`, `before`, `separator`).
  static Y _slot(Slot slot) => switch (slot) {
    Slot(
      content: PartContent(:final part),
      role: null,
      spaceBefore: null,
      spaceAfter: null,
      before: null,
      separator: null,
    ) =>
      _string(part.name),
    _ => YMap({
      ...switch (slot.content) {
        PartContent(:final part) => {'content': _string(part.name)},
        AttributeContent(:final name) => {'attribute': _string(name)},
      },
      if (slot.role case final role?) 'role': _string(role),
      if (slot.spaceBefore?.of(Medium.print) case final space?)
        'margin_top': _length(space),
      if (slot.spaceAfter?.of(Medium.print) case final space?)
        'margin_bottom': _length(space),
      // (Text, where the theme's is formatted text.)
      if (slot.before case final before?) 'before': _string(_escape(before)),
      if (slot.separator case final separator?)
        'separator': _string(_escape(separator)),
    }),
  };

  // Tokens.

  void _tokens() {
    _item = 'tokens.font.text';
    if (tokens.fonts['text']?.at(Medium.print) case final face?) {
      _set('base_font_family', face.family?.primary.let(_string));
      if (face.weight != null || face.shape != null) {
        _set('base_font_style', _string(_fontStyle(face.weight, face.shape)));
      }
    }
    _item = 'tokens.font.code';
    if (tokens.fonts['code']?.at(Medium.print) case final face?) {
      if (face.family?.primary case final family?) {
        _set('codespan_font_family', _string(family));
        _set('code_font_family', _string(family));
      }
      if (face.size case final size?) {
        _set('codespan_font_size', _string('${_trim(size)}em'));
      }
    }
    _item = 'tokens.size.text';
    if (tokens.textSize?.of(Medium.print) case final size?) {
      _set('base_font_size', _length(size));
    }
    _item = 'tokens.size.headings';
    final headings = tokens.headingSizes?.of(Medium.print) ?? const <Length>[];
    for (final (i, size) in headings.indexed) {
      if (i < 6) {
        _set('heading_h${i + 1}_font_size', _length(size));
      } else {
        _unsupported('tokens.size.headings[$i]', 'is past h6');
      }
    }
    _item = 'tokens.leading';
    if (tokens.leading?.of(Medium.print) case final leading?) {
      _set('base_line_height', _number(_num(leading)));
    }
    _item = 'tokens.paragraph';
    if (tokens.paragraph case final paragraph?) {
      final space = paragraph.space?.of(Medium.print);
      final indent = paragraph.indent?.of(Medium.print);
      // (A first-line indent after another paragraph alone, as books
      // and the CSS set it.)
      switch (paragraph.signal?.of(Medium.print)) {
        case ParagraphSignal.indent:
          _set('prose_margin_inner', _number(0));
          _set(
            'prose_text_indent_inner',
            _length(indent ?? const Length(1.5, LengthUnit.em)),
          );
        case ParagraphSignal.space || null:
          _set('prose_margin_bottom', space?.let(_length));
          _set('prose_text_indent_inner', indent?.let(_length));
      }
    }
    _item = 'tokens.align';
    if (tokens.align?.of(Medium.print) case final align?) {
      _set(
        'base_text_align',
        _string(switch (align) {
          Alignment.start => 'left',
          Alignment.end => 'right',
          Alignment.center => 'center',
          Alignment.justify => 'justify',
        }),
      );
    }
    _item = 'tokens.hyphenate';
    if (tokens.hyphenate?.of(Medium.print) case final hyphenate?) {
      _set('base_hyphens', YScalar(ThemeBool(hyphenate)));
    }
    // The color roles the PDF applies itself: the text and the paper.
    _item = 'tokens.color.ink';
    if (tokens.colors['ink']?.of(Medium.print) case final ink?) {
      _set('base_font_color', _string(ink.hex));
    }
    _item = 'tokens.color.paper';
    if (tokens.colors['paper']?.of(Medium.print) case final paper?) {
      _set('page_background_color', _string(paper.hex));
    }
    _item = 'tokens.page';
    if (tokens.page case final page?) {
      _set('page_size', switch (page.size) {
        NamedPageSize(:final name) => _string(name),
        PageDimensions(:final width, :final height) => YList([
          _length(width),
          _length(height),
        ]),
        null => null,
      });
      if (page.margin case final margin?) {
        _set(
          'page_margin',
          margin.length == 1
              ? _length(margin.single)
              : YList([for (final m in margin) _length(m)]),
        );
      }
      _set('page_margin_inner', page.inner?.let(_length));
      _set('page_margin_outer', page.outer?.let(_length));
    }
    // A measure sets the side margins, unless the look gives them.
    _item = 'tokens.measure';
    if (tokens.measure?.of(Medium.print) case final measure?) {
      if (tokens.page?.margin == null) {
        _set('page_measure', _string('$measure'));
      } else {
        trace(
          const Dropped(
            'tokens.measure',
            'gives way to tokens.page.margin',
            warned: false,
          ),
        );
      }
    }
  }

  static num _num(double value) =>
      value == value.roundToDouble() ? value.round() : value;

  static String _trim(double value) => '${_num(value)}';

  // Styles.

  void _style(StyleTarget target, Style styled) {
    final style = styled.at(Medium.print);
    final category = switch (target) {
      ElementTarget(:final element) => _categories[element]!,
      RoleTarget(:final role) => 'role_$role',
    };
    final item = 'styles.$target';
    void key(String suffix, Y? value) => _set('${category}_$suffix', value);
    void none(String property) => _unsupported('$item.$property');
    void from(String property) => _item = '$item.$property';

    final face = switch (style.font) {
      null => null,
      final name => switch (tokens.fonts[name]?.at(Medium.print)) {
        MediumFace(family: null, weight: null, shape: null, size: null) => () {
          _noValue('$item.font', 'font', name);
          return null;
        }(),
        final face? => face,
        null => () {
          _unsupported('$item.font', 'names no font token $name');
          return null;
        }(),
      },
    };
    from('font');
    key('font_family', face?.family?.primary.let(_string));
    final weight = style.weight ?? face?.weight;
    final shape = style.shape ?? face?.shape;
    if (face != null || style.weight != null || style.shape != null) {
      if (weight != null || shape != null) {
        _set('${category}_font_style', _string(_fontStyle(weight, shape)), [
          if (style.font != null) '$item.font',
          if (style.weight != null) '$item.weight',
          if (style.shape != null) '$item.style',
        ]);
      }
    }
    if (style.variant case final variant?) {
      from('variant');
      key('font_variant', _string(variant.wire));
    }
    if (style.size case final size?) {
      from('size');
      key('font_size', switch (size) {
        SizeLength(:final length) => _length(length),
        SizeRatio(:final ratio) => _string('${_trim(ratio)}em'),
        SizeToken(name: 'small') when tokens.small?.of(Medium.print) != null =>
          _string('${_trim(tokens.small!.of(Medium.print)!)}em'),
        SizeToken(:final name) => () {
          _unsupported('$item.size', 'names no size token $name');
          return null;
        }(),
      });
    }
    if (style.color case final color?) {
      from('color');
      key('font_color', _color(color, '$item.color'));
    }
    if (style.background case final background?) {
      from('background');
      key('background_color', _color(background, '$item.background'));
    }
    if (style.leading case final leading?) {
      from('leading');
      key('line_height', _number(leading));
    }
    from('space-before');
    key('margin_top', style.spaceBefore?.let(_length));
    from('space-after');
    key('margin_bottom', style.spaceAfter?.let(_length));
    from('padding');
    key('padding', style.padding?.let(_length));
    from('radius');
    key('border_radius', style.radius?.let(_length));
    from('border');
    switch (style.border) {
      case NoRule():
        key('border_width', _number(0));
      case Rule(:final width, :final color):
        key('border_width', _width(width, '$item.border.width'));
        if (color != null) key('border_color', _color(color, '$item.border'));
      case null:
    }
    from('rule');
    switch (style.rule) {
      case NoRule():
        key('column_rule_width', _number(0));
      case Rule(:final width, :final color):
        key('column_rule_width', _width(width, '$item.rule.width'));
        if (color != null) {
          key('column_rule_color', _color(color, '$item.rule'));
        }
      case null:
    }
    for (final (property, suffix, value) in [
      ('number', 'number_placement', style.number?.name.let(_string)),
      ('hang', 'number_hang', style.hang?.let(_length)),
    ]) {
      if (value == null) continue;
      if (category.startsWith('heading')) {
        from(property);
        key(suffix, value);
      } else {
        none(property);
      }
    }
    if (style.keepWithNext case final keep?) {
      from('keep-with-next');
      if (category.startsWith('heading')) {
        key('min_height_after', keep ? _string('auto') : _number(0));
      } else {
        none('keep-with-next');
      }
    }
    if (category == 'table') {
      _table(style, item);
    } else {
      for (final (property, value) in [
        ('frame', style.frame),
        ('frame-sides', style.frameSides),
        ('rows', style.rows),
        ('columns', style.columns),
        ('head-rule', style.headRule),
        ('stripes', style.stripes),
      ]) {
        if (value != null) none(property);
      }
    }
  }

  /// A rule's width and color, none being 0 wide.
  (Y?, Y?) _rule(RuleValue rule, String item) => switch (rule) {
    NoRule() => (_number(0), null),
    Rule(:final width, :final color) => (
      _width(width, '$item.width'),
      color == null ? null : _color(color, item),
    ),
  };

  void _table(MediumStyle style, String item) {
    void pair(
      String widthKey,
      String colorKey,
      RuleValue? first,
      RuleValue? second,
      String firstName,
      String secondName,
    ) {
      if (first == null && second == null) return;
      final (w1, c1) = first == null
          ? (null, null)
          : _rule(first, '$item.$firstName');
      final (w2, c2) = second == null
          ? (null, null)
          : _rule(second, '$item.$secondName');
      final items = [
        if (first != null) '$item.$firstName',
        if (second != null) '$item.$secondName',
      ];
      if (w1 != null && w2 != null) {
        _set(widthKey, YList([w1, w2]), items);
      } else {
        _set(widthKey, w1 ?? w2, items);
      }
      _set(colorKey, c1 ?? c2, [
        if (c1 != null) '$item.$firstName' else '$item.$secondName',
      ]);
    }

    pair(
      'table_border_width',
      'table_border_color',
      style.frame,
      style.frameSides,
      'frame',
      'frame-sides',
    );
    pair(
      'table_grid_width',
      'table_grid_color',
      style.rows,
      style.columns,
      'rows',
      'columns',
    );
    if (style.headRule case final rule?) {
      _item = '$item.head-rule';
      final (width, color) = _rule(rule, _item);
      _set('table_head_border_bottom_width', width);
      _set('table_head_border_bottom_color', color);
    }
    if (style.stripes case final stripes?) {
      _item = '$item.stripes';
      _set(
        'table_body_stripe_background_color',
        _color(stripes, '$item.stripes'),
      );
    }
  }
}

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
