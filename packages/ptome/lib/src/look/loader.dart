/// Reads looks (ADR-0023): a look's file and the looks it extends, merged
/// (a later value wins, `null` removes one), into a [Look]; anything a
/// look can't say is an error with its line and column.
library;

import 'dart:convert';

import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/look/looks.g.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/path_resolver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

/// A look that can't be read, with where.
final class LookException implements Exception {
  /// [message], about the text at [span].
  const new(this.message, [this.span]);

  /// What is wrong.
  final String message;

  /// Where, when it is in a file.
  final SourceSpan? span;

  @override
  String toString() => switch (span) {
    final span? =>
      '${span.sourceUrl?.path ?? 'look'}:${span.start.line + 1}:'
          '${span.start.column + 1}: $message',
    null => message,
  };
}

/// The built-in looks, by name.
Iterable<String> get builtInLookNames => builtInLooks.keys;

/// Reads looks: built-in ones by name, others from files.
final class LookLoader {
  /// A loader that looks for `<name>-look.yml` in [looksDir] before the
  /// built-in looks.
  new({this.looksDir});

  /// The folder of the document's looks.
  final String? looksDir;

  /// The look [name]: a `.yml` path, `<name>-look.yml` in [looksDir], or
  /// a built-in look.
  Look load(String name) {
    final chain = <_Source>[];
    _chain(_resolve(name, looksDir), chain, {});
    var merged = const _RawMap({}, null);
    for (final source in chain) {
      merged = _merge(merged, source.body);
    }
    return _Parser(name: _nameOf(name), directory: chain.last.directory).parse(
      merged,
      pdf: [for (final s in chain) ?s.pdf],
      css: [for (final s in chain) ?s.css],
      epubCss: [for (final s in chain) ?s.epubCss],
      webfonts: chain.reversed.map((s) => s.webfonts).nonNulls.firstOrNull,
    );
  }

  /// The chain of the look at [location], the looks it extends first, into
  /// [chain].
  void _chain(_Location location, List<_Source> chain, Set<String> seen) {
    if (!seen.add(location.key)) {
      throw LookException('${location.key} extends itself');
    }
    final source = _read(location);
    if (source.parent case (final name, final span)) {
      try {
        _chain(_resolve(name, location.directory ?? looksDir), chain, seen);
      } on LookException catch (error) {
        throw error.span == null ? LookException(error.message, span) : error;
      }
    }
    chain.add(source);
  }

  _Location _resolve(String name, String? directory) {
    if (name.endsWith('.yml')) {
      final path = PathResolver().systemPath(name, start: directory);
      return _FileLocation(path);
    }
    if (directory != null) {
      final path = PathResolver().systemPath(
        '$name-look.yml',
        start: directory,
      );
      if (io.isFile(path)) return _FileLocation(path);
    }
    if (builtInLooks.containsKey(name)) return _BuiltIn(name);
    throw LookException(
      'no look named $name'
      '${directory == null ? '' : ' in $directory'} (built in: '
      '${builtInLookNames.join(', ')})',
    );
  }

  _Source _read(_Location location) {
    final String text;
    final Uri url;
    switch (location) {
      case _BuiltIn(:final name):
        text = builtInLooks[name]!;
        url = Uri.parse('ptome:looks/$name-look.yml');
      case _FileLocation(:final path):
        try {
          text = utf8.decode(io.readBytes(path));
        } on io.IoException {
          throw LookException('could not read the look $path');
        }
        url = Uri.file(path);
    }
    final YamlNode root;
    try {
      root = loadYamlNode(text, sourceUrl: url);
    } on YamlException catch (error) {
      throw LookException(error.message, error.span);
    }
    if (root is! YamlMap) {
      if (root is YamlScalar && root.value == null) {
        return _Source(const _RawMap({}, null));
      }
      throw LookException('a look is a mapping', root.span);
    }
    (String, SourceSpan)? extends_;
    YamlMap? pdf;
    String? css;
    String? epubCss;
    List<String>? webfonts;
    final body = <String, _Raw>{};
    for (final MapEntry(key: keyNode, value: node) in root.nodes.entries) {
      if (keyNode is! YamlNode) continue;
      final key = _key(keyNode);
      switch (key) {
        case 'extends':
          extends_ = (_string(node, 'extends'), node.span);
        case 'pdf':
          if (node is! YamlMap) {
            throw LookException('pdf is a mapping of theme keys', node.span);
          }
          pdf = node;
        case 'css':
          css = _string(node, 'css');
        case 'epub-css':
          epubCss = _string(node, 'epub-css');
        case 'webfonts':
          webfonts = switch (node) {
            YamlList(:final nodes) => [
              for (final family in nodes) _string(family, 'webfonts'),
            ],
            _ => [_string(node, 'webfonts')],
          };
        case 'tokens' || 'styles' || 'templates':
          body[key] = _raw(node);
        default:
          throw LookException(
            'unknown part $key (a look has tokens, styles, templates, '
            'extends, pdf, css, epub-css and webfonts)',
            keyNode.span,
          );
      }
    }
    return _Source(
      _RawMap(body, root.span),
      parent: extends_,
      pdf: pdf,
      css: css,
      epubCss: epubCss,
      webfonts: webfonts,
      directory: switch (location) {
        _FileLocation(:final path) => _dirname(path),
        _BuiltIn() => null,
      },
    );
  }

  static String _nameOf(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    return base.endsWith('-look.yml')
        ? base.substring(0, base.length - 9)
        : base.endsWith('.yml')
        ? base.substring(0, base.length - 4)
        : base;
  }

  static String? _dirname(String path) {
    final index = path.lastIndexOf(RegExp(r'[/\\]'));
    return index <= 0 ? null : path.substring(0, index);
  }
}

/// Where a look is.
sealed class _Location {
  const new();

  String get key;

  String? get directory => null;
}

final class _BuiltIn extends _Location {
  const new(this.name);

  final String name;

  @override
  String get key => 'ptome:$name';
}

final class _FileLocation extends _Location {
  const new(this.path);

  final String path;

  @override
  String get key => path;

  @override
  String? get directory => LookLoader._dirname(path);
}

/// One look's file, read.
final class _Source {
  new(
    this.body, {
    this.parent,
    this.pdf,
    this.css,
    this.epubCss,
    this.webfonts,
    this.directory,
  });

  /// Its tokens, styles and templates.
  final _RawMap body;

  /// The look it extends, and where that is said.
  final (String, SourceSpan)? parent;
  final YamlMap? pdf;
  final String? css;
  final String? epubCss;
  final List<String>? webfonts;
  final String? directory;
}

/// A look's mappings before they are parsed: merged across a chain.
sealed class _Raw {
  const new();

  SourceSpan? get span;
}

final class _RawMap extends _Raw {
  const new(this.entries, this.span, [this.keySpans = const {}]);

  final Map<String, _Raw> entries;

  /// Where each key is written.
  final Map<String, SourceSpan> keySpans;

  @override
  final SourceSpan? span;
}

final class _RawLeaf extends _Raw {
  const new(this.node);

  final YamlNode node;

  @override
  SourceSpan get span => node.span;

  bool get isNull => node is YamlScalar && (node as YamlScalar).value == null;
}

_Raw _raw(YamlNode node) => switch (node) {
  YamlMap(:final nodes) => _RawMap(
    {
      for (final MapEntry(:key, :value) in nodes.entries)
        if (key case final YamlNode keyNode) _key(keyNode): _raw(value),
    },
    node.span,
    {
      for (final key in nodes.keys)
        if (key case final YamlNode node) _key(node): node.span,
    },
  ),
  _ => _RawLeaf(node),
};

/// [over] laid on [under]: maps merge, anything else replaces, `null`
/// removes.
_RawMap _merge(_RawMap under, _RawMap over) {
  final entries = {...under.entries};
  final keySpans = {...under.keySpans, ...over.keySpans};
  for (final MapEntry(:key, :value) in over.entries.entries) {
    switch ((entries[key], value)) {
      case (_, _RawLeaf(isNull: true)):
        entries.remove(key);
        keySpans.remove(key);
      case (final _RawMap a, final _RawMap b):
        entries[key] = _merge(a, b);
      case _:
        entries[key] = value;
    }
  }
  return _RawMap(entries, over.span ?? under.span, keySpans);
}

/// A mapping key, as text (`package:yaml` keys every mapping by node).
String _key(YamlNode key) => '${key.value}';

String _string(YamlNode node, String what) => switch (node) {
  YamlScalar(:final String value) => value,
  _ => throw LookException('$what is a string', node.span),
};

/// Parses a merged look into its typed model.
final class _Parser {
  new({required this.name, this.directory});

  final String name;
  final String? directory;

  Look parse(
    _RawMap raw, {
    required List<YamlMap> pdf,
    required List<String> css,
    required List<String> epubCss,
    List<String>? webfonts,
  }) {
    final tokens = raw.entries['tokens'];
    final styles = raw.entries['styles'];
    final templates = raw.entries['templates'];
    return Look(
      name: name,
      tokens: tokens == null ? const Tokens() : _tokens(_map(tokens, 'tokens')),
      styles: styles == null ? const {} : _styles(_map(styles, 'styles')),
      templates: templates == null
          ? const Templates()
          : _templates(_map(templates, 'templates')),
      pdf: pdf,
      css: css,
      epubCss: epubCss,
      webfonts: webfonts ?? const [],
      directory: directory,
    );
  }

  // Tokens.

  Tokens _tokens(_RawMap raw) {
    _only(raw, 'tokens', const {
      'font',
      'size',
      'leading',
      'measure',
      'paragraph',
      'align',
      'hyphenate',
      'color',
      'rule',
      'page',
    });
    final e = raw.entries;
    final size = e['size'] == null ? null : _map(e['size']!, 'tokens.size');
    if (size != null) {
      _only(size, 'tokens.size', const {'text', 'headings', 'small'});
    }
    return Tokens(
      fonts: switch (e['font']) {
        null => const {},
        final font => {
          for (final MapEntry(:key, :value) in _map(
            font,
            'tokens.font',
          ).entries.entries)
            key: _face(_map(value, 'tokens.font.$key'), 'tokens.font.$key'),
        },
      },
      textSize: switch (size?.entries['text']) {
        null => null,
        final v => _byMedium(v, 'tokens.size.text', _length),
      },
      headingSizes: switch (size?.entries['headings']) {
        null => null,
        final v => _byMedium(
          v,
          'tokens.size.headings',
          (raw, what) => _list(raw, what, _length),
        ),
      },
      small: switch (size?.entries['small']) {
        null => null,
        final v => _byMedium(v, 'tokens.size.small', _ratio),
      },
      leading: switch (e['leading']) {
        null => null,
        final v => _byMedium(v, 'tokens.leading', _ratio),
      },
      measure: switch (e['measure']) {
        null => null,
        final v => _byMedium(v, 'tokens.measure', _length),
      },
      paragraph: switch (e['paragraph']) {
        null => null,
        final v => _paragraph(_map(v, 'tokens.paragraph')),
      },
      align: switch (e['align']) {
        null => null,
        final v => _byMedium(
          v,
          'tokens.align',
          (leaf, what) => _choice(leaf, what, Alignment.values),
        ),
      },
      hyphenate: switch (e['hyphenate']) {
        null => null,
        final v => _byMedium(v, 'tokens.hyphenate', _bool),
      },
      colors: switch (e['color']) {
        null => const {},
        final color => {
          for (final MapEntry(:key, :value) in _map(
            color,
            'tokens.color',
          ).entries.entries)
            key: _byMedium(value, 'tokens.color.$key', _color),
        },
      },
      rules: switch (e['rule']) {
        null => const {},
        final rule => {
          for (final MapEntry(:key, :value) in _map(
            rule,
            'tokens.rule',
          ).entries.entries)
            key: _byMedium(value, 'tokens.rule.$key', _length),
        },
      },
      page: switch (e['page']) {
        null => null,
        final v => _page(_map(v, 'tokens.page')),
      },
    );
  }

  Face _face(_RawMap raw, String what) {
    _only(raw, what, const {'family', 'weight', 'style', 'size'});
    final e = raw.entries;
    ByMedium<T>? get<T extends Object>(
      String key,
      T Function(_Raw, String) parse,
    ) => switch (e[key]) {
      null => null,
      final v => _byMedium(v, '$what.$key', parse),
    };
    return Face(
      family: get('family', _text),
      weight: get('weight', _weight),
      shape: get('style', (v, w) => _choice(v, w, FontShape.values)),
      size: get('size', _ratio),
    );
  }

  Paragraph _paragraph(_RawMap raw) {
    _only(raw, 'tokens.paragraph', const {'signal', 'space', 'indent'});
    final e = raw.entries;
    ByMedium<T>? get<T extends Object>(
      String key,
      T Function(_Raw, String) parse,
    ) => switch (e[key]) {
      null => null,
      final v => _byMedium(v, 'tokens.paragraph.$key', parse),
    };
    return Paragraph(
      signal: get('signal', (v, w) => _choice(v, w, ParagraphSignal.values)),
      space: get('space', _length),
      indent: get('indent', _length),
    );
  }

  Page _page(_RawMap raw) {
    _only(raw, 'tokens.page', const {'size', 'margin', 'inner', 'outer'});
    final e = raw.entries;
    final margin = switch (e['margin']) {
      null => null,
      final v && _RawLeaf(node: YamlList()) => _list(
        v,
        'tokens.page.margin',
        _length,
      ),
      final v => [_length(v, 'tokens.page.margin')],
    };
    if (margin != null && !const {1, 2, 4}.contains(margin.length)) {
      throw LookException(
        'tokens.page.margin has 1, 2 or 4 lengths',
        e['margin']!.span,
      );
    }
    return Page(
      size: switch (e['size']) {
        null => null,
        final v && _RawLeaf(node: YamlList()) => switch (_list(
          v,
          'tokens.page.size',
          _length,
        )) {
          [final width, final height] => PageDimensions(width, height),
          _ => throw LookException(
            'tokens.page.size is a name (A4) or [width, height]',
            v.span,
          ),
        },
        final v => NamedPageSize(_text(v, 'tokens.page.size')),
      },
      margin: margin,
      inner: e['inner'] == null
          ? null
          : _length(e['inner']!, 'tokens.page.inner'),
      outer: e['outer'] == null
          ? null
          : _length(e['outer']!, 'tokens.page.outer'),
    );
  }

  // Styles.

  Map<StyleTarget, Style> _styles(_RawMap raw) => {
    for (final MapEntry(:key, :value) in raw.entries.entries)
      (StyleTarget.parse(key) ??
          (throw LookException(
            'unknown element $key (a role starts with a dot: .$key; the '
            'elements are ${LookElement.values.map((e) => e.wire).join(', ')})',
            raw.keySpans[key] ?? value.span,
          ))): _style(
        _map(value, 'styles.$key'),
        'styles.$key',
      ),
  };

  Style _style(_RawMap raw, String what) {
    _only(raw, what, const {
      'font',
      'size',
      'weight',
      'style',
      'variant',
      'color',
      'background',
      'leading',
      'space-before',
      'space-after',
      'padding',
      'radius',
      'border',
      'rule',
      'keep-with-next',
      'frame',
      'frame-sides',
      'rows',
      'columns',
      'head-rule',
      'stripes',
    });
    final e = raw.entries;
    ByMedium<T>? get<T extends Object>(
      String key,
      T Function(_Raw, String) parse,
    ) => switch (e[key]) {
      null => null,
      final v => _byMedium(v, '$what.$key', parse),
    };
    return Style(
      font: get('font', _text),
      size: get('size', _size),
      weight: get('weight', _weight),
      shape: get('style', (v, w) => _choice(v, w, FontShape.values)),
      variant: get(
        'variant',
        (v, w) => _choice(v, w, FontVariant.values, wire: (f) => f.wire),
      ),
      color: get('color', _colorValue),
      background: get('background', _colorValue),
      leading: get('leading', _ratio),
      spaceBefore: get('space-before', _length),
      spaceAfter: get('space-after', _length),
      padding: get('padding', _length),
      radius: get('radius', _length),
      border: get('border', _rule),
      rule: get('rule', _rule),
      keepWithNext: get('keep-with-next', _bool),
      frame: get('frame', _rule),
      frameSides: get('frame-sides', _rule),
      rows: get('rows', _rule),
      columns: get('columns', _rule),
      headRule: get('head-rule', _rule),
      stripes: get('stripes', _colorValue),
    );
  }

  static SizeValue _size(_Raw raw, String what) {
    final scalar = _scalar(raw, what);
    return switch (scalar.value) {
      final num n when n > 0 => SizeRatio(n.toDouble()),
      final String text when _lengthPattern.hasMatch(text.trim()) => SizeLength(
        _length(raw, what),
      ),
      final String text => SizeToken(text),
      _ => throw LookException(
        '$what is a length, a ratio of the text or a size token (small)',
        scalar.span,
      ),
    };
  }

  // Templates.

  Templates _templates(_RawMap raw) {
    final named = <String, String>{};
    String? nodeTemplates;
    TitlePage? titlePage;
    for (final MapEntry(:key, :value) in raw.entries.entries) {
      switch (key) {
        case 'node-templates':
          nodeTemplates = _text(value, 'templates.node-templates');
        case 'title-page':
          titlePage = _titlePage(_map(value, 'templates.title-page'));
        default:
          named[key] = _text(value, 'templates.$key');
      }
    }
    return Templates(
      named: named,
      nodeTemplates: nodeTemplates,
      titlePage: titlePage,
    );
  }

  /// A title page: its `recto` and `verso` slot lists.
  static TitlePage _titlePage(_RawMap raw) {
    const what = 'templates.title-page';
    _only(raw, what, {'recto', 'verso'});
    List<Slot> side(String name) => switch (raw.entries[name]) {
      null => const [],
      _RawLeaf(node: YamlList(:final nodes)) => [
        for (final (i, node) in nodes.indexed) _slot(node, '$what.$name[$i]'),
      ],
      final other => throw LookException(
        '$what.$name is a list of slots',
        other.span,
      ),
    };
    return TitlePage(recto: side('recto'), verso: side('verso'));
  }

  /// A slot: a part's name, or a mapping of what it shows (`slot:` a
  /// part, or `attribute:` a document attribute) and how.
  static Slot _slot(YamlNode node, String what) {
    switch (_raw(node)) {
      case _RawLeaf(node: YamlScalar(value: final String name)):
        return Slot(PartContent(_part(name, node.span, what)));
      case final _RawMap map:
        _only(map, what, {
          'slot',
          'attribute',
          'style',
          'space-before',
          'space-after',
          'before',
          'separator',
        });
        final content = switch ((
          map.entries['slot'],
          map.entries['attribute'],
        )) {
          (final slot?, null) => PartContent(
            _part(_text(slot, '$what.slot'), slot.span, '$what.slot'),
          ),
          (null, final attribute?) => AttributeContent(
            _text(attribute, '$what.attribute'),
          ),
          _ => throw LookException(
            '$what shows a part (slot: ${_parts.join(', ')}) or an '
            'attribute (attribute: copyright), one of them',
            map.span,
          ),
        };
        final style = switch (map.entries['style']) {
          null => null,
          final raw => switch (_text(raw, '$what.style')) {
            final role when role.startsWith('.') && role.length > 1 =>
              role.substring(1),
            _ => throw LookException(
              '$what.style is a role, written with its dot (.publisher)',
              raw.span,
            ),
          },
        };
        ByMedium<Length>? length(String key) => switch (map.entries[key]) {
          null => null,
          final raw => _byMedium(raw, '$what.$key', _length),
        };
        String? text(String key) => switch (map.entries[key]) {
          null => null,
          final raw => _text(raw, '$what.$key'),
        };
        return Slot(
          content,
          role: style,
          spaceBefore: length('space-before'),
          spaceAfter: length('space-after'),
          before: text('before'),
          separator: text('separator'),
        );
      case final other:
        throw LookException(
          '$what is a part (${_parts.join(', ')}) or a mapping',
          other.span,
        );
    }
  }

  static Iterable<String> get _parts => TitlePart.values.map((p) => p.name);

  static TitlePart _part(String name, SourceSpan? span, String what) =>
      TitlePart.values.asNameMap()[name] ??
      (throw LookException(
        'unknown $what $name (known: ${_parts.join(', ')})',
        span,
      ));

  // Values.

  static void _only(_RawMap raw, String what, Set<String> keys) {
    for (final MapEntry(:key, :value) in raw.entries.entries) {
      if (!keys.contains(key)) {
        throw LookException(
          'unknown $what.$key (known: ${keys.join(', ')})',
          raw.keySpans[key] ?? value.span,
        );
      }
    }
  }

  static _RawMap _map(_Raw raw, String what) => switch (raw) {
    final _RawMap map => map,
    _RawLeaf(:final node) => throw LookException(
      '$what is a mapping',
      node.span,
    ),
  };

  static YamlScalar _scalar(_Raw raw, String what) => switch (raw) {
    _RawLeaf(node: final YamlScalar scalar) => scalar,
    _ => throw LookException('$what is a single value', raw.span),
  };

  static String _text(_Raw raw, String what) => switch (_scalar(raw, what)) {
    YamlScalar(:final String value) => value,
    YamlScalar(:final num value) => '$value',
    final scalar => throw LookException('$what is text', scalar.span),
  };

  static bool _bool(_Raw raw, String what) => switch (_scalar(raw, what)) {
    YamlScalar(:final bool value) => value,
    final scalar => throw LookException('$what is true or false', scalar.span),
  };

  static double _ratio(_Raw raw, String what) => switch (_scalar(raw, what)) {
    YamlScalar(:final num value) when value > 0 => value.toDouble(),
    final scalar => throw LookException(
      '$what is a positive number (a ratio)',
      scalar.span,
    ),
  };

  static final RegExp _lengthPattern = RegExp(
    r'^(-?\d+(?:\.\d+)?|-?\.\d+)\s*(pt|px|in|mm|rem|em|ch|lines)$',
  );

  static Length _length(_Raw raw, String what) {
    final scalar = _scalar(raw, what);
    final value = scalar.value;
    if (value == 0) return const Length(0, LengthUnit.pt);
    if (value is String) {
      if (_lengthPattern.firstMatch(value.trim()) case final m?) {
        final number = num.parse(m[1]!);
        return Length(
          number,
          LengthUnit.values.firstWhere((u) => u.symbol == m[2]),
        );
      }
    }
    throw LookException(
      '$what is a length with its unit (10.5pt, 1.5in, 1em, 2lines; '
      'pt, px, in, mm, em, rem, ch or lines)',
      scalar.span,
    );
  }

  static final RegExp _hex = RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

  static LookColor _color(_Raw raw, String what) {
    final scalar = _scalar(raw, what);
    if (scalar.value case final String text) {
      if (_hex.firstMatch(text.trim()) case final m?) {
        var hex = m[1]!.toUpperCase();
        if (hex.length == 3) {
          hex = [for (final c in hex.split('')) '$c$c'].join();
        }
        return LookColor(hex);
      }
    }
    throw LookException(
      "$what is a color: '#RRGGBB' (quoted: YAML reads # as a comment)",
      scalar.span,
    );
  }

  static ColorValue _colorValue(_Raw raw, String what) {
    final scalar = _scalar(raw, what);
    return switch (scalar.value) {
      'none' || 'transparent' => const NoColor(),
      final String text when text.startsWith('#') => ColorLiteral(
        _color(raw, what),
      ),
      final String text => ColorToken(text),
      _ => throw LookException(
        "$what is a color token's name, a color ('#RRGGBB') or none",
        scalar.span,
      ),
    };
  }

  static RuleValue _rule(_Raw raw, String what) {
    if (raw case _RawLeaf(node: YamlScalar(value: 'none'))) {
      return const NoRule();
    }
    final map = switch (raw) {
      final _RawMap map => map,
      _ => throw LookException(
        '$what is none or { width: ..., color: ... }',
        raw.span,
      ),
    };
    _only(map, what, const {'width', 'color'});
    final width = map.entries['width'];
    if (width == null) {
      throw LookException('$what has no width', map.span);
    }
    final widthScalar = _scalar(width, '$what.width');
    return Rule(
      width: switch (widthScalar.value) {
        final String text when !_lengthPattern.hasMatch(text.trim()) =>
          WidthToken(text),
        _ => WidthLength(_length(width, '$what.width')),
      },
      color: switch (map.entries['color']) {
        null => null,
        final c => _colorValue(c, '$what.color'),
      },
    );
  }

  /// A weight: `normal` (400), `bold` (700) or 100 to 900.
  static FontWeight _weight(_Raw raw, String what) {
    final scalar = _scalar(raw, what);
    return switch (scalar.value) {
      'normal' => 400,
      'bold' => 700,
      final int n when n >= 100 && n <= 900 && n % 100 == 0 => n,
      _ => throw LookException(
        '$what is normal, bold or a weight from 100 to 900',
        scalar.span,
      ),
    };
  }

  static T _choice<T extends Enum>(
    _Raw raw,
    String what,
    List<T> values, {
    String Function(T)? wire,
  }) {
    final scalar = _scalar(raw, what);
    final name = wire ?? (T value) => value.name;
    for (final value in values) {
      if (scalar.value == name(value)) return value;
    }
    throw LookException(
      '$what is one of ${values.map(name).join(', ')}',
      scalar.span,
    );
  }

  static List<T> _list<T>(
    _Raw raw,
    String what,
    T Function(_Raw, String) item,
  ) => switch (raw) {
    _RawLeaf(node: YamlList(:final nodes)) => [
      for (final (i, node) in nodes.indexed) item(_RawLeaf(node), '$what[$i]'),
    ],
    _ => throw LookException('$what is a list', raw.span),
  };

  static ByMedium<T> _byMedium<T extends Object>(
    _Raw raw,
    String what,
    T Function(_Raw, String) item,
  ) {
    // (A map is by medium when every key names one; a rule is a map of
    // its own.)
    if (raw is! _RawMap ||
        raw.entries.isEmpty ||
        !raw.entries.keys.any((k) => Medium.named(k) != null)) {
      return ByMedium(all: item(raw, what));
    }
    final each = <Medium, T>{};
    for (final MapEntry(:key, :value) in raw.entries.entries) {
      final medium =
          Medium.named(key) ??
          (throw LookException(
            'unknown medium $what.$key (print, screen or ebook)',
            raw.keySpans[key] ?? value.span,
          ));
      each[medium] = item(value, '$what.$key');
    }
    return ByMedium(each: each);
  }
}
