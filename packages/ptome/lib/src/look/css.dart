/// A look's CSS (ADR-0023 decision 2): for HTML pages, its tokens as
/// custom properties (`--ptome-*`; the screen's values, the print values in
/// `@media print`) and its styles as rules over Asciidoctor's markup that
/// read them; for an EPUB, the same rules over asciidoctor-epub3's markup
/// with the e-book's values written out (reading systems such as Kindle's
/// KF8 and Adobe's don't read custom properties). Laid after the output's
/// base stylesheet, with the device rules that hold no values.
library;

import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/look/outcome.dart';

/// The output a look's CSS is for.
enum CssTarget {
  /// HTML pages and the website.
  html,

  /// An EPUB's content documents.
  epub,
}

/// The CSS of [look]'s tokens and styles for [target] (its own CSS is
/// [lookOwnCss]); what [target] can't render of it
/// reported to [warn], and what each item became, or why it was left
/// out, to [trace] (`ptome look explain`).
String lookCss(
  Look look,
  CssTarget target, {
  void Function(String message)? warn,
  void Function(LookOutcome outcome)? trace,
}) => _CssCompiler(look, target, warn ?? (_) {}, trace ?? (_) {}).compile();

/// The CSS [look] writes itself for [target], its `css:` or `epub-css:`
/// (the looks it extends first): laid after the device rules, to have
/// the last word.
String lookOwnCss(Look look, CssTarget target) => [
  for (final css in target == CssTarget.html ? look.css : look.epubCss)
    css.trim(),
].join('\n');

/// What a look's own CSS becomes ([lookOwnCss]).
const String _own = 'after the device rules, as written';

/// A declaration and the item of the look it comes from.
typedef _Declaration = (String item, String css);

/// A rule: a selector and its declarations.
typedef _Rule = (String selector, List<_Declaration> declarations);

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
  // (Asciidoctor's own selectors for its code blocks' background, which
  // a look's must match to override.)
  LookElement.codeBlock: (
    '.literalblock pre,.listingblock>.content>pre:not(.highlight),'
        '.listingblock>.content>pre[class=highlight],'
        '.listingblock>.content>pre[class^="highlight "]',
    'pre',
  ),
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
  new(this.look, this.target, this.warn, this.trace);

  final Look look;
  final CssTarget target;
  final void Function(String message) warn;
  final void Function(LookOutcome outcome) trace;

  Tokens get tokens => look.tokens;

  bool get html => target == CssTarget.html;

  String get _output => html ? 'HTML' : 'an EPUB';

  void _unsupported(String item, [String? why]) {
    final reason = why ?? 'has no effect in $_output';
    warn('look ${look.name}: $item $reason');
    trace(Dropped(item, reason));
  }

  /// Nothing, for [item], which names a [kind] token without a value in
  /// [medium].
  String? _noValue(String item, String kind, String name, Medium medium) {
    trace(
      Dropped(
        item,
        'the $kind token $name has no ${medium.name} value',
        warned: false,
      ),
    );
    return null;
  }

  /// The medium an outcome in [medium] is told apart by: HTML's print
  /// rules are print's alone, its others every medium's.
  Medium? _only(Medium medium) =>
      html && medium == Medium.print ? Medium.print : null;

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
      if (look.templates.titlePage?.verso case [_, ...]) {
        out.write(_versoBreak('#header>.verso', '@media print{', '}'));
      }
      if (look.css.isNotEmpty) trace(const Became('css', _own));
    } else {
      _medium(out, Medium.ebook);
      _readerOwns(out);
      if (look.templates.titlePage?.verso case [_, ...]) {
        out.write(_versoBreak('.titlepage.verso'));
      }
      if (look.epubCss.isNotEmpty) trace(const Became('epub-css', _own));
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
        final where = switch ((html, side)) {
          (true, 'recto') => 'the header',
          (true, _) => "the header's verso",
          (false, 'recto') => 'the title page',
          (false, _) => "the title page's verso",
        };
        final parts = [
          for (final slot in slots)
            switch (slot.content) {
              PartContent(:final part) => part.name,
              AttributeContent(:final name) => 'the attribute $name',
            },
        ];
        trace(
          Became('templates.title-page.$side', '$where: ${parts.join(', ')}'),
        );
      }
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
            null => _noValue(item, 'color', name, medium),
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
            null => _noValue(item, 'rule', name, medium),
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
    final rules = <_Rule>[];
    void rule(String selector, List<_Declaration> declarations) {
      if (declarations.isNotEmpty) rules.add((selector, declarations));
    }

    if (html) {
      final screen = medium == Medium.screen
          ? const <String>{}
          : {for (final (_, p) in _properties(Medium.screen)) p};
      final properties = [
        for (final p in _properties(medium))
          if (!screen.contains(p.$2)) p,
      ];
      if (properties.isNotEmpty) {
        out.write(':root{${properties.map((p) => p.$2).join(';')}}\n');
      }
      for (final (item, property) in properties) {
        trace(Became(item, property, medium: _only(medium)));
      }
    }
    // Tokens the base stylesheet's elements take.
    final body = <_Declaration>[];
    if (tokens.fonts['text']?.at(medium) case MediumFace(:final family?)) {
      body.add((
        'tokens.font.text',
        'font-family:${_fontFamily(family, 'text')}',
      ));
    }
    if (tokens.textSize?.of(medium) case final size?) {
      body.add(('tokens.size.text', 'font-size:${_length(size)}'));
    }
    if (tokens.leading?.of(medium) case final leading?) {
      body.add(('tokens.leading', 'line-height:$leading'));
    }
    if (tokens.align?.of(medium) case final align?) {
      body.add(('tokens.align', 'text-align:${_align(align)}'));
    }
    if (tokens.hyphenate?.of(medium) case final hyphenate?) {
      final value = hyphenate ? 'auto' : 'manual';
      for (final css in [
        '-webkit-hyphens:$value',
        '-epub-hyphens:$value',
        'adobe-hyphenate:${hyphenate ? 'auto' : 'none'}',
        'hyphens:$value',
      ]) {
        body.add(('tokens.hyphenate', css));
      }
    }
    if (tokens.colors['ink']?.of(medium) != null) {
      body.add((
        'tokens.color.ink',
        'color:${_color(const ColorToken('ink'), medium, 'ink')}',
      ));
    }
    if (tokens.colors['paper']?.of(medium) != null) {
      body.add((
        'tokens.color.paper',
        'background-color:'
            '${_color(const ColorToken('paper'), medium, 'paper')}',
      ));
    }
    rule('body', body);
    if (tokens.headingSizes?.of(medium) case final sizes?) {
      for (final (i, size) in sizes.take(6).indexed) {
        rule('h${i + 1}', [
          ('tokens.size.headings', 'font-size:${_length(size)}'),
        ]);
      }
    }
    if (tokens.fonts['code']?.at(medium) case MediumFace(:final family?)) {
      rule('code,kbd,pre,samp', [
        ('tokens.font.code', 'font-family:${_fontFamily(family, 'code')}'),
      ]);
    }
    if (tokens.paragraph case final paragraph?) {
      const item = 'tokens.paragraph';
      final space = paragraph.space?.of(medium);
      final indent = paragraph.indent?.of(medium);
      final selector = html ? '.paragraph>p' : 'body p';
      switch (paragraph.signal?.of(medium)) {
        case ParagraphSignal.indent:
          rule(selector, [(item, 'margin-bottom:0')]);
          final first = indent ?? const Length(1.5, LengthUnit.em);
          rule(html ? '.paragraph+.paragraph>p' : 'body p+p', [
            (item, 'text-indent:${_length(first)}'),
          ]);
        case ParagraphSignal.space || null:
          if (space != null) {
            rule(selector, [(item, 'margin-bottom:${_length(space)}')]);
          }
          if (indent != null) {
            rule(html ? '.paragraph+.paragraph>p' : 'body p+p', [
              (item, 'text-indent:${_length(indent)}'),
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
          trace(Became('tokens.measure', declaration, medium: Medium.screen));
        } else {
          rules.add((
            selector,
            [('tokens.measure', 'max-width:${_length(measure)}')],
          ));
        }
      } else {
        _unsupported('tokens.measure', "is the reader's in an EPUB");
      }
    }
    for (final MapEntry(key: target, value: style) in look.styles.entries) {
      _style(rules, target, style.at(medium), medium);
    }
    // The title page's slots' space (the header in HTML, the title page
    // in an EPUB).
    if (look.templates.titlePage case final page?) {
      for (final (side, slots) in [
        ('recto', page.recto),
        ('verso', page.verso),
      ]) {
        final item = 'templates.title-page.$side';
        for (final slot in slots) {
          final name = switch (slot.content) {
            PartContent(:final part) => part.name,
            AttributeContent(:final name) => name,
          };
          rule('${html ? '#header' : '.titlepage'} .title-page-$name', [
            if (slot.spaceBefore?.of(medium) case final space?)
              (item, 'margin-top:${_length(space)}'),
            if (slot.spaceAfter?.of(medium) case final space?)
              (item, 'margin-bottom:${_length(space)}'),
          ]);
        }
      }
    }
    for (final (selector, declarations) in rules) {
      // (A declaration two items make, as a table's frame and its sides'
      // one border-width, written once.)
      final css = {for (final (_, css) in declarations) css};
      final line = '$selector{${css.join(';')}}';
      if (except.contains(line)) continue;
      out.write('$line\n');
      for (final (item, css) in declarations) {
        trace(Became(item, '$selector{$css}', medium: _only(medium)));
      }
    }
  }

  /// The custom properties of [medium]'s tokens, with their items.
  List<_Declaration> _properties(Medium medium) => [
    for (final MapEntry(key: role, value: face) in tokens.fonts.entries)
      if (face.at(medium).family case final family?)
        ('tokens.font.$role', '--ptome-font-$role:${_family(family, role)}'),
    for (final MapEntry(:key, :value) in tokens.colors.entries)
      if (value.of(medium) case final color?)
        ('tokens.color.$key', '--ptome-color-$key:$color'),
    for (final MapEntry(:key, :value) in tokens.rules.entries)
      if (value.of(medium) case final width?)
        ('tokens.rule.$key', '--ptome-rule-$key:${_length(width)}'),
  ];

  /// A face's `font-family` value: its custom property in HTML, the
  /// family itself in an EPUB.
  String _fontFamily(FontStack family, String role) =>
      html ? 'var(--ptome-font-$role)' : _family(family, role);

  /// [stack] as CSS writes it: each family quoted, then the generic one
  /// the stack names, else [role]'s.
  static String _family(FontStack stack, String role) => [
    for (final family in stack.families)
      if (FontStack.generics.contains(family)) family else '"$family"',
    if (!stack.families.any(FontStack.generics.contains)) _generic(role),
  ].join(',');

  static String _align(Alignment align) => switch (align) {
    Alignment.start => 'start',
    Alignment.center => 'center',
    Alignment.end => 'end',
    Alignment.justify => 'justify',
  };

  static String _pageSize(PageSize size) => switch (size) {
    NamedPageSize(:final name) => name,
    PageDimensions(:final width, :final height) =>
      '${_length(width)} ${_length(height)}',
  };

  /// The `@page` rules of the page tokens (HTML printed): a recto's
  /// inner margin is its left, a verso's its right.
  String? _page() {
    final page = tokens.page;
    if (page == null) return null;
    final all = [
      if (page.size case final size?) 'size:${_pageSize(size)}',
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
    for (final rule in rules) {
      trace(Became('tokens.page', rule, medium: Medium.print));
    }
    return rules.isEmpty ? null : rules.join('\n');
  }

  /// The declarations of [style] (in [medium]) on its target's selector.
  void _style(
    List<_Rule> rules,
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
    final declarations = <_Declaration>[];
    void add(String property, String css) =>
        declarations.add(('$item.$property', css));
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
    if (face case (
      final role,
      MediumFace(family: null, weight: null, shape: null, size: null),
    )) {
      _noValue('$item.font', 'font', role, medium);
    }
    if (face case (final role, MediumFace(:final family?))) {
      add('font', 'font-family:${_fontFamily(family, role)}');
    }
    if (style.weight ?? face?.$2.weight case final weight?) {
      add(style.weight == null ? 'font' : 'weight', 'font-weight:$weight');
    }
    if (style.shape ?? face?.$2.shape case final shape?) {
      add(style.shape == null ? 'font' : 'style', 'font-style:${shape.name}');
    }
    if (style.variant case final variant?) {
      add('variant', 'font-variant:${variant.wire}');
      if (variant == FontVariant.smallCaps) {
        add('variant', 'font-feature-settings:"smcp"');
      }
    }
    if (style.size case final size?) {
      final value = switch (size) {
        SizeLength(:final length) => _length(length),
        SizeRatio(:final ratio) => '${ratio}em',
        SizeToken(name: 'small') when tokens.small?.of(medium) != null =>
          '${tokens.small!.of(medium)}em',
        SizeToken() => null,
      };
      if (value != null) add('size', 'font-size:$value');
    }
    if (style.color case final color?) {
      if (_color(color, medium, '$item.color') case final c?) {
        add('color', 'color:$c');
      }
    }
    if (style.background case final background?) {
      if (_color(background, medium, '$item.background') case final c?) {
        add('background', 'background-color:$c');
      }
    }
    if (style.leading case final leading?) {
      add('leading', 'line-height:$leading');
    }
    if (style.spaceBefore case final space?) {
      add('space-before', 'margin-top:${_length(space)}');
    }
    if (style.spaceAfter case final space?) {
      add('space-after', 'margin-bottom:${_length(space)}');
    }
    if (style.padding case final padding?) {
      add('padding', 'padding:${_length(padding)}');
    }
    if (style.radius case final radius?) {
      add('radius', 'border-radius:${_length(radius)}');
    }
    if (style.border case final border?) {
      add('border', switch (_rule(border, medium, '$item.border')) {
        null => 'border:0',
        (final w, null) => 'border-width:$w',
        (final w, final c) => 'border:$w solid $c',
      });
    }
    if (style.rule case final rule?) {
      add('rule', switch (_rule(rule, medium, '$item.rule')) {
        null => 'border-left:0',
        (final w, null) => 'border-left-width:$w',
        (final w, final c) => 'border-left:$w solid $c',
      });
    }
    if (style.keepWithNext case final keep?) {
      add('keep-with-next', 'break-after:${keep ? 'avoid' : 'auto'}');
      add('keep-with-next', 'page-break-after:${keep ? 'avoid' : 'auto'}');
    }
    // A heading's number: its first `[.number]` span, hung left of the
    // title's edge (a float as wide as the hang, pulled into the margin)
    // or on a line of its own.
    if (style.number case final number?) {
      final heading = switch (styleTarget) {
        ElementTarget(:final element) =>
          element == LookElement.heading ||
              element.name.length == 2 && element.name.startsWith('h'),
        RoleTarget() => false,
      };
      if (!heading || selector == null) {
        _unsupported('$item.number');
      } else {
        final hang = _length(style.hang ?? const Length(2.5, LengthUnit.em));
        rules.add((
          [for (final s in selector.split(',')) '$s>.number:first-child']
              .join(','),
          [
            for (final css in switch (number) {
              NumberPlacement.hang => [
                'float:left',
                'width:$hang',
                'margin-left:-$hang',
              ],
              NumberPlacement.line => ['display:block'],
              NumberPlacement.inline => [
                'display:inline',
                'float:none',
                'margin-left:0',
              ],
            })
              ('$item.number', css),
          ],
        ));
      }
    }
    // (A target without the element, as HTML without a subtitle's: left
    // out by design.)
    if (selector == null) {
      for (final item in {for (final (item, _) in declarations) item}) {
        trace(Dropped(item, '$_output has no such element', warned: false));
      }
    } else if (declarations.isNotEmpty) {
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
    List<_Rule> rules,
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
      final firstColor = color(first, firstName);
      final c = firstColor ?? color(second, secondName);
      rules.add((
        selector,
        [
          for (final (name, rule) in [(firstName, first), (secondName, second)])
            if (rule != null)
              ('$item.$name', 'border-width:${widths.join(' ')}'),
          if (c != null)
            (
              '$item.${firstColor != null ? firstName : secondName}',
              'border-color:$c',
            ),
        ],
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
          (
            '$item.head-rule',
            switch (_rule(rule, medium, '$item.head-rule')) {
              null => 'border-bottom:0',
              (final w, null) => 'border-bottom-width:$w',
              (final w, final c) => 'border-bottom:$w solid $c',
            },
          ),
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
          [('$item.stripes', 'background-color:$c')],
        ));
      }
    }
  }

  /// The title page's verso on a page of its own: [selector]'s rule,
  /// within [open] and [close].
  String _versoBreak(String selector, [String open = '', String close = '']) {
    final rule = '$selector{break-before:page;page-break-before:always}';
    trace(
      Became(
        'templates.title-page.verso',
        rule,
        medium: html ? Medium.print : null,
      ),
    );
    return '$open$rule$close\n';
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
      trace(
        const Dropped(
          'tokens.align',
          "is the reader's in an EPUB (asciidoctor-epub3's justified "
              'text undone)',
          warned: false,
        ),
      );
    }
    if (tokens.leading?.of(Medium.ebook) == null) {
      out.write(
        'body{line-height:normal}\n'
        'body p,li,dt,dd,footer{line-height:inherit}\n',
      );
      trace(
        const Dropped(
          'tokens.leading',
          "is the reader's in an EPUB (asciidoctor-epub3's 1.6 undone)",
          warned: false,
        ),
      );
    }
  }
}
