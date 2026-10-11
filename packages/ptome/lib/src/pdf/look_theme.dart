/// A look's PDF theme (ADR-0023 decision 2): its tokens and styles as the
/// theme keys of the modern engine and asciidoctor-pdf, written as a theme
/// file writes them and laid over the `default` theme, then the look's own
/// `pdf:` entries. What the PDF doesn't apply by design is left out
/// quietly; anything else it can't render is reported.
library;

import 'package:ptome/src/look/model.dart';
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
  final compiler = _Compiler(look, warn ?? (_) {});
  final entries = compiler.compile();
  return (loader ?? ThemeLoader()).loadOver(base, entries, [
    for (final section in look.pdf)
      if (yamlToY(section) case final YMap map) map,
  ])..directory = look.directory;
}

/// The theme keys a look compiles to, in order (for `ptome look
/// explain` and the tests).
Map<String, Y> lookThemeEntries(
  Look look, {
  void Function(String message)? warn,
}) => _Compiler(look, warn ?? (_) {}).compile();

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
  new(this.look, this.warn);

  final Look look;
  final void Function(String message) warn;
  final Map<String, Y> out = {};

  Tokens get tokens => look.tokens;

  void _unsupported(String item, [String why = 'has no effect in the PDF']) =>
      warn('look ${look.name}: $item $why');

  Map<String, Y> compile() {
    _tokens();
    for (final MapEntry(:key, value: style) in look.styles.entries) {
      _style(key, style);
    }
    for (final name in look.templates.named.keys) {
      _unsupported('templates.$name');
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
      final color? => color.of(Medium.print)?.hex.let(_string),
      null => () {
        _unsupported(item, 'names no color token $name');
        return null;
      }(),
    },
  };

  Y? _width(WidthValue value, String item) => switch (value) {
    WidthLength(:final length) => _length(length),
    WidthToken(:final name) => switch (tokens.rules[name]) {
      final length? => length.of(Medium.print)?.let(_length),
      null => () {
        _unsupported(item, 'names no rule token $name');
        return null;
      }(),
    },
  };

  void _set(String key, Y? value) {
    if (value != null) out[key] = value;
  }

  /// A face's weight and shape as asciidoctor-pdf's font style.
  /// (The bold face for 600 and up.)
  static String _fontStyle(FontWeight? weight, FontShape? shape) =>
      switch (((weight ?? 400) >= 600, shape ?? FontShape.normal)) {
        (true, FontShape.italic) => 'bold_italic',
        (true, FontShape.normal) => 'bold',
        (false, FontShape.italic) => 'italic',
        (false, FontShape.normal) => 'normal',
      };

  // Tokens.

  void _tokens() {
    if (tokens.fonts['text']?.at(Medium.print) case final face?) {
      _set('base_font_family', face.family?.let(_string));
      if (face.weight != null || face.shape != null) {
        _set('base_font_style', _string(_fontStyle(face.weight, face.shape)));
      }
    }
    if (tokens.fonts['code']?.at(Medium.print) case final face?) {
      if (face.family case final family?) {
        _set('codespan_font_family', _string(family));
        _set('code_font_family', _string(family));
      }
      if (face.size case final size?) {
        _set('codespan_font_size', _string('${_trim(size)}em'));
      }
    }
    if (tokens.textSize?.of(Medium.print) case final size?) {
      _set('base_font_size', _length(size));
    }
    final headings = tokens.headingSizes?.of(Medium.print) ?? const <Length>[];
    for (final (i, size) in headings.indexed) {
      if (i < 6) {
        _set('heading_h${i + 1}_font_size', _length(size));
      } else {
        _unsupported('tokens.size.headings[$i]', 'is past h6');
      }
    }
    if (tokens.leading?.of(Medium.print) case final leading?) {
      _set('base_line_height', _number(_num(leading)));
    }
    if (tokens.paragraph case final paragraph?) {
      final space = paragraph.space?.of(Medium.print);
      final indent = paragraph.indent?.of(Medium.print);
      switch (paragraph.signal?.of(Medium.print)) {
        case ParagraphSignal.indent:
          _set('prose_margin_bottom', _number(0));
          _set(
            'prose_text_indent',
            _length(indent ?? const Length(1.5, LengthUnit.em)),
          );
        case ParagraphSignal.space || null:
          _set('prose_margin_bottom', space?.let(_length));
          _set('prose_text_indent', indent?.let(_length));
      }
    }
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
    if (tokens.hyphenate?.of(Medium.print) case final hyphenate?) {
      _set('base_hyphens', YScalar(ThemeBool(hyphenate)));
    }
    // The color roles the PDF applies itself: the text and the paper.
    if (tokens.colors['ink']?.of(Medium.print) case final ink?) {
      _set('base_font_color', _string(ink.hex));
    }
    if (tokens.colors['paper']?.of(Medium.print) case final paper?) {
      _set('page_background_color', _string(paper.hex));
    }
    if (tokens.page case final page?) {
      _set('page_size', page.size?.let(_string));
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
    if (tokens.measure?.of(Medium.print) case final measure?) {
      if (tokens.page?.margin == null) {
        _set('page_measure', _string('$measure'));
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

    final face = switch (style.font) {
      null => null,
      final name =>
        tokens.fonts[name]?.at(Medium.print) ??
            () {
              _unsupported('$item.font', 'names no font token $name');
              return null;
            }(),
    };
    key('font_family', face?.family?.let(_string));
    final weight = style.weight ?? face?.weight;
    final shape = style.shape ?? face?.shape;
    if (face != null || style.weight != null || style.shape != null) {
      if (weight != null || shape != null) {
        key('font_style', _string(_fontStyle(weight, shape)));
      }
    }
    if (style.variant case final variant?) {
      key('font_variant', _string(variant.wire));
    }
    if (style.size case final size?) {
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
      key('font_color', _color(color, '$item.color'));
    }
    if (style.background case final background?) {
      key('background_color', _color(background, '$item.background'));
    }
    if (style.leading case final leading?) {
      key('line_height', _number(leading));
    }
    key('margin_top', style.spaceBefore?.let(_length));
    key('margin_bottom', style.spaceAfter?.let(_length));
    key('padding', style.padding?.let(_length));
    key('border_radius', style.radius?.let(_length));
    switch (style.border) {
      case NoRule():
        key('border_width', _number(0));
      case Rule(:final width, :final color):
        key('border_width', _width(width, '$item.border.width'));
        if (color != null) key('border_color', _color(color, '$item.border'));
      case null:
    }
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
    if (style.keepWithNext case final keep?) {
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
      if (w1 != null && w2 != null) {
        _set(widthKey, YList([w1, w2]));
      } else {
        _set(widthKey, w1 ?? w2);
      }
      _set(colorKey, c1 ?? c2);
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
      final (width, color) = _rule(rule, '$item.head-rule');
      _set('table_head_border_bottom_width', width);
      _set('table_head_border_bottom_color', color);
    }
    if (style.stripes case final stripes?) {
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
