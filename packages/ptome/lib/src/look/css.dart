/// A look's CSS (ADR-0023 decision 2): for HTML pages, its tokens as
/// custom properties (`--ptome-*`; the screen's values, the print values in
/// `@media print`) and its styles as rules over Asciidoctor's markup that
/// read them; for an EPUB, the same rules over asciidoctor-epub3's markup
/// with the e-book's values written out (reading systems such as Kindle's
/// KF8 and Adobe's don't read custom properties). Laid after the output's
/// base stylesheet, with the device rules that hold no values.
library;

import 'package:ptome/src/look/model.dart';

/// The output a look's CSS is for.
enum CssTarget {
  /// HTML pages and the website.
  html,

  /// An EPUB's content documents.
  epub,
}

/// The CSS of [look] for [target]; what [target] can't render of it
/// reported to [warn].
String lookCss(
  Look look,
  CssTarget target, {
  void Function(String message)? warn,
}) => _CssCompiler(look, target, warn ?? (_) {}).compile();

/// The selectors of each element in each target's markup (null: the
/// target has no such element).
const Map<LookElement, (String?, String?)> _selectors = {
  LookElement.heading: (
    'h1,h2,h3,#toctitle,.sidebarblock>.content>.title,h4,h5,h6',
    'h1,h2,h3,h4,h5,h6',
  ),
  LookElement.h1: ('h1', 'h1'),
  LookElement.h2: ('h2', 'h2'),
  LookElement.h3: ('h3', 'h3'),
  LookElement.h4: ('h4', 'h4'),
  LookElement.h5: ('h5', 'h5'),
  LookElement.h6: ('h6', 'h6'),
  LookElement.title: ('#header>h1:first-child', null),
  LookElement.subtitle: (null, null),
  LookElement.paragraph: ('.paragraph>p', 'body p'),
  LookElement.link: ('a', 'body a:link'),
  LookElement.code: (':not(pre)>code', ':not(pre)>code'),
  LookElement.codeBlock: ('.listingblock pre,.literalblock pre', 'pre'),
  LookElement.caption: (
    '.admonitionblock td.content>.title,.audioblock>.title,'
        '.exampleblock>.title,.imageblock>.title,.listingblock>.title,'
        '.literalblock>.title,.stemblock>.title,.openblock>.title,'
        '.paragraph>.title,.quoteblock>.title,table.tableblock>.title,'
        '.verseblock>.title,.videoblock>.title,.dlist>.title,.olist>.title,'
        '.ulist>.title,.qlist>.title,.hdlist>.title',
    'figcaption,caption,div.example-title',
  ),
  LookElement.quote: ('.quoteblock blockquote', 'div.blockquote blockquote'),
  LookElement.admonition: (
    '.admonitionblock>table td.content',
    'aside.admonition',
  ),
  LookElement.admonitionLabel: (
    '.admonitionblock td.icon .title',
    'aside.admonition>h2',
  ),
  LookElement.sidebar: ('.sidebarblock', 'aside.sidebar'),
  LookElement.sidebarTitle: (
    '.sidebarblock>.content>.title',
    'aside.sidebar>h2',
  ),
  LookElement.table: ('table.tableblock', 'table.table'),
  LookElement.tableHead: (
    'table.tableblock>thead>tr>th',
    'table.table thead th',
  ),
  LookElement.footnote: ('#footnotes .footnote', 'div.footnotes p'),
};

/// The generic family each face role falls back to.
String _generic(String role) => switch (role) {
  'display' || 'utility' => 'sans-serif',
  'code' => 'monospace',
  _ => 'serif',
};

final class _CssCompiler {
  new(this.look, this.target, this.warn);

  final Look look;
  final CssTarget target;
  final void Function(String message) warn;

  Tokens get tokens => look.tokens;

  bool get html => target == CssTarget.html;

  String get _output => html ? 'HTML' : 'an EPUB';

  void _unsupported(String item, [String? why]) =>
      warn('look ${look.name}: $item ${why ?? 'has no effect in $_output'}');

  String compile() {
    final out = StringBuffer(
      '/*! look ${look.name} (ADR-0023, doc/looks.md) */\n',
    );
    if (html) {
      final screen = StringBuffer();
      _medium(screen, Medium.screen);
      out.write(screen);
      final print = StringBuffer();
      _medium(print, Medium.print, except: '$screen'.split('\n').toSet());
      if (print.isNotEmpty) out.write('@media print{$print}\n');
      if (_page() case final page?) out.write('$page\n');
      for (final css in look.css) {
        out.write('${css.trim()}\n');
      }
    } else {
      _medium(out, Medium.ebook);
      _readerOwns(out);
      for (final css in look.epubCss) {
        out.write('${css.trim()}\n');
      }
    }
    for (final name in look.templates.named.keys) {
      _unsupported('templates.$name');
    }
    return '$out';
  }

  // Values.

  /// [length] in CSS (`lines` as the line height, `lh`).
  static String _length(Length length) => switch (length.unit) {
    LengthUnit.lines => '${length.value}lh',
    _ => '$length',
  };

  /// The value of a color for [medium]: a custom property in HTML (the
  /// token's, declared in that medium), the color itself in an EPUB.
  String? _color(ColorValue value, Medium medium, String item) =>
      switch (value) {
        NoColor() => 'transparent',
        ColorLiteral(:final color) => '$color',
        ColorToken(:final name) => switch (tokens.colors[name]) {
          final color? => switch (color.of(medium)) {
            final c? => html ? 'var(--ptome-color-$name)' : '$c',
            null => null,
          },
          null => () {
            _unsupported(item, 'names no color token $name');
            return null;
          }(),
        },
      };

  String? _width(WidthValue value, Medium medium, String item) =>
      switch (value) {
        WidthLength(:final length) => _length(length),
        WidthToken(:final name) => switch (tokens.rules[name]) {
          final rule? => switch (rule.of(medium)) {
            final length? => html ? 'var(--ptome-rule-$name)' : _length(length),
            null => null,
          },
          null => () {
            _unsupported(item, 'names no rule token $name');
            return null;
          }(),
        },
      };

  // A medium's custom properties and rules.

  /// [medium]'s custom properties and rules into [out], but the lines
  /// in [except] (the screen's, which print takes too).
  void _medium(
    StringBuffer out,
    Medium medium, {
    Set<String> except = const {},
  }) {
    final rules = <(String, List<String>)>[];
    void rule(String selector, List<String> declarations) {
      if (declarations.isNotEmpty) rules.add((selector, declarations));
    }

    if (html) {
      final screen = medium == Medium.screen
          ? const <String>{}
          : _properties(Medium.screen).toSet();
      final properties = [
        for (final p in _properties(medium))
          if (!screen.contains(p)) p,
      ];
      if (properties.isNotEmpty) {
        out.write(':root{${properties.join(';')}}\n');
      }
    }
    // Tokens the base stylesheet's elements take.
    final body = <String>[];
    if (tokens.fonts['text']?.at(medium) case MediumFace(:final family?)) {
      body.add('font-family:${_fontFamily(family, 'text')}');
    }
    if (tokens.textSize?.of(medium) case final size?) {
      body.add('font-size:${_length(size)}');
    }
    if (tokens.leading?.of(medium) case final leading?) {
      body.add('line-height:$leading');
    }
    if (tokens.align?.of(medium) case final align?) {
      body.add('text-align:${_align(align)}');
    }
    if (tokens.hyphenate?.of(medium) case final hyphenate?) {
      final value = hyphenate ? 'auto' : 'manual';
      body.addAll([
        '-webkit-hyphens:$value',
        '-epub-hyphens:$value',
        'adobe-hyphenate:${hyphenate ? 'auto' : 'none'}',
        'hyphens:$value',
      ]);
    }
    if (tokens.colors['ink']?.of(medium) != null) {
      body.add('color:${_color(const ColorToken('ink'), medium, 'ink')}');
    }
    if (tokens.colors['paper']?.of(medium) != null) {
      body.add(
        'background-color:'
        '${_color(const ColorToken('paper'), medium, 'paper')}',
      );
    }
    rule('body', body);
    if (tokens.headingSizes?.of(medium) case final sizes?) {
      for (final (i, size) in sizes.take(6).indexed) {
        rule('h${i + 1}', ['font-size:${_length(size)}']);
      }
    }
    if (tokens.fonts['code']?.at(medium) case MediumFace(:final family?)) {
      rule('code,kbd,pre,samp', ['font-family:${_fontFamily(family, 'code')}']);
    }
    if (tokens.paragraph case final paragraph?) {
      final space = paragraph.space?.of(medium);
      final indent = paragraph.indent?.of(medium);
      final selector = html ? '.paragraph>p' : 'body p';
      switch (paragraph.signal?.of(medium)) {
        case ParagraphSignal.indent:
          rule(selector, ['margin-bottom:0']);
          final first = indent ?? const Length(1.5, LengthUnit.em);
          rule(html ? '.paragraph+.paragraph>p' : 'body p+p', [
            'text-indent:${_length(first)}',
          ]);
        case ParagraphSignal.space || null:
          if (space != null) {
            rule(selector, ['margin-bottom:${_length(space)}']);
          }
          if (indent != null) {
            rule(html ? '.paragraph+.paragraph>p' : 'body p+p', [
              'text-indent:${_length(indent)}',
            ]);
          }
      }
    }
    if (tokens.measure?.of(medium) case final measure?) {
      if (html) {
        const selector = '#header,#content,#footnotes,#footer';
        final declaration = '$selector{max-width:${_length(measure)}}';
        // (The screen's measure on screens alone.)
        if (medium == Medium.screen) {
          out.write('@media screen{$declaration}\n');
        } else {
          rules.add((selector, ['max-width:${_length(measure)}']));
        }
      } else {
        _unsupported('tokens.measure', "is the reader's in an EPUB");
      }
    }
    for (final MapEntry(key: target, value: style) in look.styles.entries) {
      _style(rules, target, style.at(medium), medium);
    }
    for (final (selector, declarations) in rules) {
      final line = '$selector{${declarations.join(';')}}';
      if (!except.contains(line)) out.write('$line\n');
    }
  }

  /// The custom properties of [medium]'s tokens.
  List<String> _properties(Medium medium) => [
    for (final MapEntry(key: role, value: face) in tokens.fonts.entries)
      if (face.at(medium).family case final family?)
        '--ptome-font-$role:${_family(family, role)}',
    for (final MapEntry(:key, :value) in tokens.colors.entries)
      if (value.of(medium) case final color?) '--ptome-color-$key:$color',
    for (final MapEntry(:key, :value) in tokens.rules.entries)
      if (value.of(medium) case final width?)
        '--ptome-rule-$key:${_length(width)}',
  ];

  /// A face's `font-family` value: its custom property in HTML, the
  /// family itself in an EPUB.
  String _fontFamily(String family, String role) =>
      html ? 'var(--ptome-font-$role)' : _family(family, role);

  static String _family(String family, String role) =>
      '"$family",${_generic(role)}';

  static String _align(Alignment align) => switch (align) {
    Alignment.start => 'start',
    Alignment.center => 'center',
    Alignment.end => 'end',
    Alignment.justify => 'justify',
  };

  /// The `@page` rules of the page tokens (HTML printed): a recto's
  /// inner margin is its left, a verso's its right.
  String? _page() {
    final page = tokens.page;
    if (page == null) return null;
    final all = [
      if (page.size case final size?) 'size:$size',
      if (page.margin case final margin?)
        'margin:${margin.map(_length).join(' ')}',
    ];
    final (inner, outer) = (page.inner, page.outer);
    String margins(Length? left, Length? right) => [
      if (left != null) 'margin-left:${_length(left)}',
      if (right != null) 'margin-right:${_length(right)}',
    ].join(';');
    final rules = [
      if (all.isNotEmpty) '@page{${all.join(';')}}',
      if (inner != null || outer != null) ...[
        '@page :right{${margins(inner, outer)}}',
        '@page :left{${margins(outer, inner)}}',
      ],
    ];
    return rules.isEmpty ? null : rules.join('\n');
  }

  /// The declarations of [style] (in [medium]) on its target's selector.
  void _style(
    List<(String, List<String>)> rules,
    StyleTarget styleTarget,
    MediumStyle style,
    Medium medium,
  ) {
    final item = 'styles.$styleTarget';
    final selector = switch (styleTarget) {
      ElementTarget(:final element) => switch (_selectors[element]) {
        (final h, final e) => html ? h : e,
        null => null,
      },
      RoleTarget(:final role) => '.$role',
    };
    final declarations = <String>[];
    final face = switch (style.font) {
      null => null,
      final role => switch (tokens.fonts[role]) {
        final face? => (role, face.at(medium)),
        null => () {
          _unsupported('$item.font', 'names no font token $role');
          return null;
        }(),
      },
    };
    if (face case (final role, MediumFace(:final family?))) {
      declarations.add('font-family:${_fontFamily(family, role)}');
    }
    final weight = style.weight ?? face?.$2.weight;
    if (weight != null) declarations.add('font-weight:$weight');
    final shape = style.shape ?? face?.$2.shape;
    if (shape != null) declarations.add('font-style:${shape.name}');
    if (style.variant case final variant?) {
      declarations.addAll([
        'font-variant:${variant.wire}',
        if (variant == FontVariant.smallCaps) 'font-feature-settings:"smcp"',
      ]);
    }
    if (style.size case final size?) {
      final value = switch (size) {
        SizeLength(:final length) => _length(length),
        SizeRatio(:final ratio) => '${ratio}em',
        SizeToken(name: 'small') when tokens.small?.of(medium) != null =>
          '${tokens.small!.of(medium)}em',
        SizeToken() => null,
      };
      if (value != null) declarations.add('font-size:$value');
    }
    if (style.color case final color?) {
      if (_color(color, medium, '$item.color') case final c?) {
        declarations.add('color:$c');
      }
    }
    if (style.background case final background?) {
      if (_color(background, medium, '$item.background') case final c?) {
        declarations.add('background-color:$c');
      }
    }
    if (style.leading case final leading?) {
      declarations.add('line-height:$leading');
    }
    if (style.spaceBefore case final space?) {
      declarations.add('margin-top:${_length(space)}');
    }
    if (style.spaceAfter case final space?) {
      declarations.add('margin-bottom:${_length(space)}');
    }
    if (style.padding case final padding?) {
      declarations.add('padding:${_length(padding)}');
    }
    if (style.radius case final radius?) {
      declarations.add('border-radius:${_length(radius)}');
    }
    if (style.border case final border?) {
      declarations.add(switch (_rule(border, medium, '$item.border')) {
        null => 'border:0',
        (final w, null) => 'border-width:$w',
        (final w, final c) => 'border:$w solid $c',
      });
    }
    if (style.rule case final rule?) {
      declarations.add(switch (_rule(rule, medium, '$item.rule')) {
        null => 'border-left:0',
        (final w, null) => 'border-left-width:$w',
        (final w, final c) => 'border-left:$w solid $c',
      });
    }
    if (style.keepWithNext case final keep?) {
      declarations.addAll(
        keep
            ? ['break-after:avoid', 'page-break-after:avoid']
            : ['break-after:auto', 'page-break-after:auto'],
      );
    }
    // (A target without the element, as HTML without a subtitle's: left
    // out by design.)
    if (selector != null && declarations.isNotEmpty) {
      rules.add((selector, declarations));
    }
    if (styleTarget case ElementTarget(element: LookElement.table)) {
      _table(rules, style, medium, item);
    } else {
      for (final (property, value) in [
        ('frame', style.frame),
        ('frame-sides', style.frameSides),
        ('rows', style.rows),
        ('columns', style.columns),
        ('head-rule', style.headRule),
        ('stripes', style.stripes),
      ]) {
        if (value != null) _unsupported('$item.$property');
      }
    }
  }

  /// A rule's width and color in [medium]; null for none (or no width in
  /// the medium).
  (String, String?)? _rule(RuleValue rule, Medium medium, String item) =>
      switch (rule) {
        NoRule() => null,
        Rule(:final width, :final color) => switch (_width(
          width,
          medium,
          '$item.width',
        )) {
          final w? => (
            w,
            color == null ? null : _color(color, medium, '$item.color'),
          ),
          null => null,
        },
      };

  void _table(
    List<(String, List<String>)> rules,
    MediumStyle style,
    Medium medium,
    String item,
  ) {
    String width(RuleValue? rule, String what) => switch (rule) {
      null => '',
      _ => _rule(rule, medium, '$item.$what')?.$1 ?? '0',
    };
    String? color(RuleValue? rule, String what) => switch (rule) {
      null => null,
      _ => _rule(rule, medium, '$item.$what')?.$2,
    };
    void pair(
      String selector,
      RuleValue? first,
      RuleValue? second,
      String firstName,
      String secondName,
    ) {
      if (first == null && second == null) return;
      final widths = [
        width(first, firstName),
        width(second, secondName),
      ].where((w) => w.isNotEmpty);
      final c = color(first, firstName) ?? color(second, secondName);
      rules.add((
        selector,
        ['border-width:${widths.join(' ')}', if (c != null) 'border-color:$c'],
      ));
    }

    pair(
      html ? 'table.frame-all' : 'table.table-framed-all',
      style.frame,
      style.frameSides,
      'frame',
      'frame-sides',
    );
    pair(
      html
          ? 'table.grid-all>*>tr>*'
          : 'table.table-grid-all th,table.table-grid-all td',
      style.rows,
      style.columns,
      'rows',
      'columns',
    );
    if (style.headRule case final rule?) {
      final head = html
          ? 'table.tableblock>thead>tr>th'
          : 'table.table thead th';
      rules.add((
        head,
        [
          switch (_rule(rule, medium, '$item.head-rule')) {
            null => 'border-bottom:0',
            (final w, null) => 'border-bottom-width:$w',
            (final w, final c) => 'border-bottom:$w solid $c',
          },
        ],
      ));
    }
    if (style.stripes case final stripes?) {
      if (_color(stripes, medium, '$item.stripes') case final c?) {
        rules.add((
          html
              ? 'table.stripes-all>tbody>tr,'
                    'table.stripes-odd>tbody>tr:nth-of-type(odd),'
                    'table.stripes-even>tbody>tr:nth-of-type(even)'
              : 'table.table tbody tr:nth-of-type(even)',
          ['background-color:$c'],
        ));
      }
    }
  }

  /// In an EPUB, what the look leaves to the reader: asciidoctor-epub3's
  /// justified, 1.6-spaced body text undone unless the look sets the
  /// e-book's alignment or line spacing (ADR-0023 decision 2).
  void _readerOwns(StringBuffer out) {
    if (tokens.align?.of(Medium.ebook) == null) {
      out.write(
        'body p,li>span.principal,dd>span.principal,'
        'aside.sidebar>div.content{text-align:inherit}\n',
      );
    }
    if (tokens.leading?.of(Medium.ebook) == null) {
      out.write(
        'body{line-height:normal}\n'
        'body p,li,dt,dd,footer{line-height:inherit}\n',
      );
    }
  }
}
