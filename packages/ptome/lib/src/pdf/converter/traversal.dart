part of '../converter.dart';

// Traversal.

extension _Traversal on PdfConverter {
  /// Converts the blocks of [node], or the text of a block without any
  /// (an admonition paragraph, say) as prose.
  void _traverse(AbstractBlock node) {
    if (node.blocks.isNotEmpty) {
      for (final block in node.blocks) {
        final saved = _at;
        _at = block.sourceLocation ?? saved;
        final before = _out.length;
        try {
          block.convert();
        } finally {
          _at = saved;
        }
        if (_reportTags != null && block is! Section) {
          _tagLast(before, block);
        }
        if (block is! Section &&
            (block.role != null || block.hasAttr('shape'))) {
          _sideFloat(block, before);
        }
      }
    } else if (node is Block && node.contentModel != ContentModel.compound) {
      if (node.content() case final text?) {
        final align = PdfConverter._alignOf(node.roles) ?? _baseTextAlign;
        _out.add(
          CustomBox(_textBox(text, _font, align: align, hyphenate: true)),
        );
      }
    }
  }

  /// The boxes [block] added from [from] on, floating to a side when the
  /// theme floats one of its roles (`role_<role>_float: left` or `right`,
  /// `role_<role>_float_width`, a length or a percentage of the page's
  /// content width (the column's, in columns), `role_<role>_float_gap`;
  /// modern engine): the blocks
  /// after it are set beside it, or below it where they don't fit beside
  /// it whole, and what doesn't fit on its page goes on at the top of the
  /// next, beside what is set there (a report's sidebar).
  void _sideFloat(AbstractBlock block, int from) {
    if (asciidoctorCompat(_document, CompatFormat.pdf)) return;
    // An image floated by its `float` attribute that has a `shape`: to that
    // side, as wide as it is set, the text running around its outline
    // (`image_float_gap`, `image_float_shape_margin`...).
    if (block.context == BlockContext.image && block.hasAttr('shape')) {
      final side = switch (block.attr('float')) {
        'left' => FloatSide.left,
        'right' => FloatSide.right,
        _ => null,
      };
      if (side != null) {
        final pageWidth = _pageSize(_document).$1;
        final content = _floatRoom;
        final width = math.min(
          _imageWidth(block).resolve(content, pageWidth) ?? content / 3,
          content,
        );
        final gap = switch (_theme.value('image_float_gap')) {
          ThemeList(:final values) when values.isNotEmpty =>
            PdfConverter._toPoints(values.first),
          ThemeNumber(:final value) => value.toDouble(),
          _ => 12.0,
        };
        _sideFloated = true;
        final boxes = _out.sublist(from);
        _out
          ..removeRange(from, _out.length)
          ..add(
            BlockBox(
              boxes,
              style: BoxStyle(
                side: side,
                sideWidth: width,
                sideGap: gap,
                sideShape: _floatShape(block, 'image_float', width),
              ),
            ),
          );
        return;
      }
    }
    for (final role in block.roles) {
      final key = 'role_${role.replaceAll('-', '_')}_float';
      // (`top`, `bottom`, `auto`, `next`: the block floats to the top or
      // the bottom of its region, above the notes; `_float_scope: page`
      // across the page's columns, as a study Bible's feature article
      // sits between the text and the notes.)
      final placement = switch (_s(key)) {
        'top' => FloatPlacement.top,
        'bottom' => FloatPlacement.bottom,
        'auto' => FloatPlacement.auto,
        'next' => FloatPlacement.next,
        _ => null,
      };
      if (placement != null) {
        final boxes = _out.sublist(from);
        _out
          ..removeRange(from, _out.length)
          ..add(
            BlockBox(
              boxes,
              style: BoxStyle(
                float: placement,
                floatSpan: _keys(key).string('scope') == 'page',
              ),
            ),
          );
        return;
      }
      final side = switch (_s(key)) {
        'left' => FloatSide.left,
        'right' => FloatSide.right,
        _ => null,
      };
      if (side == null) continue;
      final content = _floatRoom;
      final width = switch (_keys(key).value('width')) {
        ThemeString(:final value) when value.trim().endsWith('%') =>
          content *
              (double.tryParse(value.trim().replaceFirst('%', '')) ?? 50) /
              100,
        _ => _keys(key).length('width', _font.size) ?? content / 3,
      };
      _sideFloated = true;
      final boxes = _out.sublist(from);
      _out
        ..removeRange(from, _out.length)
        ..add(
          BlockBox(
            boxes,
            style: BoxStyle(
              side: side,
              sideWidth: width,
              sideGap: _keys(key).length('gap', _font.size) ?? _font.size,
              sideShape: _floatShape(block, key, width),
            ),
          ),
        );
      return;
    }
  }

  /// The outline of the image [block] floats (its `shape` attribute, else
  /// the theme's `<key>_shape`: `alpha`, its opaque pixels' outline, the
  /// pixels above `<key>_shape_threshold` (0.5) of opacity, with
  /// `<key>_shape_margin` around them), drawn [width] wide; null for its
  /// box.
  FloatShape? _floatShape(AbstractBlock block, String key, double width) {
    if (block.context != BlockContext.image) return null;
    final kind = block.attr('shape') ?? _keys(key).string('shape');
    if (kind != 'alpha') return null;
    final target = block.attr('target');
    if (target == null) return null;
    final bytes = _imageBytes(block, target);
    if (bytes == null) return null;
    final outline = alphaOutline(
      bytes,
      threshold: (_keys(key).number('shape_threshold') ?? 0.5).toDouble(),
    );
    if (outline == null) return null;
    final scale = width / outline.width;
    final band = outline.bandRows * scale;
    final margin = _keys(key).length('shape_margin', _font.size) ?? 0;
    // Each band's columns in points, then grown by the margin: across
    // and to the bands within it above and below.
    final reach = (margin / band).ceil();
    final bands = outline.bands;
    return FloatShape(band, [
      for (var i = 0; i < bands.length; i++)
        () {
          double? left;
          double? right;
          for (var j = i - reach; j <= i + reach; j++) {
            if (j < 0 || j >= bands.length) continue;
            if (bands[j] case (final first, final last)) {
              final l = first * scale - margin;
              final r = (last + 1) * scale + margin;
              left = left == null ? l : math.min(left, l);
              right = right == null ? r : math.max(right, r);
            }
          }
          return left == null
              ? null
              : (math.max<double>(0, left), math.min(width, right!));
        }(),
    ]);
  }

  /// The block after [block] in reading order, looking out of the
  /// containers it ends (the gem's `next_enclosed_block`).
  AbstractBlock? _nextEnclosedBlock(AbstractBlock block) {
    final next = _nextEnclosed(block);
    // (Past a paragraph of index terms alone, in the modern engine.)
    if (next != null && _roomless(next)) return _nextEnclosedBlock(next);
    return next;
  }

  AbstractBlock? _nextEnclosed(AbstractBlock block) {
    if (block is Document) return null;
    final parent = block.parent;
    if (parent is! AbstractBlock) return null;
    final siblings =
        block is ListItem &&
            parent is ListBlock &&
            parent.context == BlockContext.dlist
        ? [
            for (final entry in parent.entries) ...[
              ...entry.terms,
              entry.description,
            ],
          ]
        : <AbstractBlock?>[...parent.blocks];
    final index = siblings.indexOf(block);
    // A block made up by the converter, not among its parent's: none.
    if (index < 0) return null;
    if (index < siblings.length - 1) {
      if (block.context == BlockContext.open &&
          block.style == 'table-container') {
        return _nextEnclosedBlock(parent);
      }
      return siblings[index + 1];
    }
    final parentContext = parent.context;
    if (parentContext == BlockContext.listItem ||
        (parentContext == BlockContext.open && parent.style != 'abstract') ||
        (parent is Section &&
            !_isAbstract(parent) &&
            // (A section in a box of its own, its role's: the end of the
            // box ends it.)
            _boxedRole(parent) == null)) {
      return _nextEnclosedBlock(parent);
    }
    // The last item of a nested list: the next block after the item the
    // list is in.
    if (block is ListItem) {
      if (parent.parent case final ListItem grandparent) {
        return _nextEnclosedBlock(grandparent);
      }
    }
    return null;
  }

  /// The bottom margin of a block of [category] followed by [next] (the
  /// gem's `theme_margin`): the block category's margin before a section,
  /// nothing at the end.
  double _themeMargin(String category, String side, AbstractBlock? next) {
    if (next == null) return 0;
    final key = next is Section ? 'block' : category;
    return (_keys(key).number('margin_$side') ?? 0).toDouble();
  }

  /// The space below [node], followed by [next] (the next enclosed block
  /// by default): the gem's margin ([fallback]'s), or in the modern engine
  /// the block's own `<category>_margin_bottom`, and at least the next
  /// block's `<category>_margin_top` (adjacent margins collapse to the
  /// larger, as in CSS). None at the end of a container.
  double _marginBelow(
    AbstractBlock node, {
    AbstractBlock? next,
    String fallback = 'block',
  }) {
    var following = next ?? _nextEnclosedBlock(node);
    final base = _themeMargin(fallback, 'bottom', following);
    if (!_collapseMargins || following == null) return base;
    // Past images that float out of the flow, to the block that follows
    // in it (a paragraph's space before a heading).
    if (_floatsOut(following) && !_floatsOut(node)) {
      following = _flowNext(following);
      if (following == null) return 0;
    }
    // (A role's `role_<role>_margin_bottom` and `_margin_top` before its
    // category's.)
    double? roleMargin(AbstractBlock block, String side) {
      for (final role in block.roles.reversed) {
        if (_keys('role_$role').number('margin_$side') case final value?) {
          return value.toDouble();
        }
      }
      return null;
    }

    final own =
        roleMargin(node, 'bottom') ??
        _keys(PdfConverter._spacingCategory(node))
            .number('margin_bottom')
            ?.toDouble() ??
        base;
    // A section's heading: the larger of the two, the heading's margin
    // above taking its part.
    if (following is Section) {
      return math.max(0, own - _sectionMarginTop(following));
    }
    final above =
        roleMargin(following, 'top') ??
        _keys(PdfConverter._spacingCategory(following)).number('margin_top') ??
        0;
    return math.max(own, above.toDouble());
  }

  /// The block before [node] in the flow: its previous sibling, past
  /// images that float out of it (`image_placement`, modern engine): a
  /// figure floated away leaves the paragraphs around it next to each
  /// other.
  AbstractBlock? _flowPrevious(AbstractBlock node) {
    var previous = _previousSibling(node);
    while (previous != null && _floatsOut(previous)) {
      previous = _previousSibling(previous);
    }
    return previous;
  }

  /// The block after [node] in the flow: the next enclosed block, past
  /// images that float out of it.
  AbstractBlock? _flowNext(AbstractBlock node) {
    var next = _nextEnclosedBlock(node);
    while (next != null && _floatsOut(next)) {
      next = _nextEnclosedBlock(next);
    }
    return next;
  }

  /// Whether [block] is an image that floats out of the flow
  /// (`image_placement`, modern engine).
  bool _floatsOut(AbstractBlock block) {
    if (block.context != BlockContext.image ||
        !const {
          'auto',
          'top',
          'bottom',
        }.contains(block.attr('placement') ?? _imagePlacement)) {
      return false;
    }
    // (Images float only at the top level: not in a sidebar, a list...)
    final parent = block.parent;
    return parent is Section ||
        parent is Document ||
        parent?.context == BlockContext.preamble;
  }

  /// The space above [section]'s heading (its box's, for a section role
  /// the theme styles).
  double _sectionMarginTop(Section section) {
    if (section.hasOption('notitle')) return 0;
    final level = (section.level ?? 0) + 1;
    if (_boxedRole(section) case final role?) {
      final category = 'section_role_$role';
      return ((_keys(category).number('margin_top') ?? 0) +
              (_keys(category).number('heading_margin_top') ??
                  _keys('heading_h$level').number('margin_top') ??
                  _n('heading_margin_top') ??
                  0))
          .toDouble();
    }
    return (_keys('heading_h$level').number('margin_top') ??
            _n('heading_margin_top') ??
            0)
        .toDouble();
  }

  /// The space above [node] in the modern engine (`<category>_margin_top`)
  /// that the block before it hasn't given: none after a block (whose
  /// space below collapses with it) or at the start of a container but a
  /// section, after a heading what its margin below leaves.
  double _marginAbove(AbstractBlock node) {
    if (!_collapseMargins) return 0;
    final above = _keys(PdfConverter._spacingCategory(node))
        .number('margin_top')
        ?.toDouble();
    if (above == null || above <= 0) return 0;
    if (_previousSibling(node) != null) return 0;
    final parent = node.parent;
    if (parent is! Section) return 0;
    final level = (parent.level ?? 0) + 1;
    final heading =
        (_keys('heading_h$level').number('margin_bottom') ??
                _n('heading_margin_bottom') ??
                0)
            .toDouble();
    return math.max(0, above - heading);
  }
}
