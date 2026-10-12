part of '../converter.dart';

// Admonitions.

extension _Admonitions on PdfConverter {
  /// Converts the admonition [node] (with a text label).
  void convertAdmonition(Block node) {
    final type = node.attr('name') ?? 'note';
    final labelAlign = _s('admonition_label_text_align') ?? 'center';
    final minWidth = _n('admonition_label_min_width')?.toDouble();
    var labelFont = _themeFont('admonition_label', _font);
    labelFont = _themeFont('admonition_label_$type', labelFont);
    var label = PdfConverter._plain(node.caption ?? '');
    if (labelFont.transform case final transform? when transform != 'none') {
      label = transformText(label, transform);
    }
    // A font icon in place of the text label.
    final icon = _document.attr('icons') == 'font' && !node.hasAttr('icon')
        ? _admonitionIcon(type)
        : null;
    var labelWidth = icon != null
        ? icon.size * 1.5
        : _fonts
              .font(labelFont.family, labelFont.style)
              .widthOf(label, labelFont.size, kerning: labelFont.kerning);
    if (minWidth != null && minWidth > labelWidth) labelWidth = minWidth;
    final iconColor = icon?.color ?? _font.color;
    final cpad = _padding('admonition_padding');
    final lpad = _theme.value('admonition_label_padding') == null
        ? cpad
        : _padding('admonition_label_padding');
    final ruleWidth = (_n('admonition_column_rule_width') ?? 0).toDouble();
    final ruleColor =
        _c('admonition_column_rule_color') ?? _c('base_border_color');
    final labelText = label.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final labelBox = _textBox(
      labelText,
      labelFont.copyWith(lineHeight: 1),
      align: labelAlign,
      normalize: false,
    );
    // The label shrinks to fit the block (the gem's shrink_to_fit).
    final fittedLabel = _textBox(
      labelText,
      labelFont.copyWith(lineHeight: 1),
      align: labelAlign,
      normalize: false,
      shrinkToFit: true,
    );
    final ruleX = lpad.left + labelWidth + lpad.right;
    // How far down the label is: in the middle, at the top or at the
    // bottom (`admonition_label_vertical_align`).
    final labelValign = _s('admonition_label_vertical_align') ?? 'middle';
    double labelOffset(double room, double height) => switch (labelValign) {
      'top' => 0,
      'bottom' => math.max(0, room - height),
      _ => math.max(0, (room - height) * 0.5),
    };
    void decorate(
      LayoutPage page,
      Rect rect, {
      required bool first,
      required bool last,
    }) {
      final canvas = page.canvas;
      // On a page the block continues past, the label's room and the
      // rule reach the page's bottom margin, as in the gem (whose label
      // box is as high as the cursor is).
      final bottom = last ? rect.bottom : _pageMargins(_document).bottom;
      final room = rect.top - bottom;
      if (ruleWidth > 0) {
        if (pdfColorOf(ruleColor) case final color?) {
          PdfConverter._verticalRule(
            canvas,
            color,
            rect.left + ruleX,
            rect.top,
            bottom,
            ruleWidth,
            _s('admonition_column_rule_style'),
          );
        }
      }
      if (!first) return;
      if (icon != null) {
        final size = math.min(room, icon.size);
        final glyph = _textBox(
          icon.glyph,
          _FontState(
            family: icon.set,
            style: 'normal',
            size: size,
            color: iconColor,
            lineHeight: 1,
            kerning: _font.kerning,
          ),
          align: labelAlign,
          normalize: false,
          gaps: false,
        ).place(labelWidth, double.infinity, atTop: true);
        final offset = labelOffset(room, size);
        glyph?.paint(page, rect.left + lpad.left, rect.top - offset);
        return;
      }
      final whole = labelBox.place(labelWidth, double.infinity, atTop: true);
      if (whole == null) return;
      final offset = labelOffset(room, whole.height);
      final placed = fittedLabel.place(labelWidth, room - offset, atTop: true);
      placed?.paint(page, rect.left + lpad.left, rect.top - offset);
    }

    final children = _collect(() {
      if (node.hasTitle) {
        _caption(node, category: 'admonition', labeled: false);
      }
      _withFont(
        'admonition',
        () => _withBaseKeys('admonition', () => _traverse(node)),
      );
    });
    _out.add(
      BlockBox(
        children,
        style: BoxStyle(
          padding: EdgeInsets(
            top: cpad.top,
            right: cpad.right,
            bottom: cpad.bottom,
            left: lpad.left + labelWidth + lpad.right + cpad.left,
          ),
          margin: EdgeInsets(bottom: _marginBelow(node)),
          keepTogether: node.hasOption('unbreakable'),
          anchor: node.id,
          decoration: _blockDecoration('admonition', extra: decorate),
        ),
      ),
    );
  }

  /// The font icon of admonitions of [type] (the gem's
  /// `admonition_icon_data`): its set, glyph, color and size.
  ({String set, String glyph, ThemeColor? color, double size})? _admonitionIcon(
    String type,
  ) {
    final defaults = PdfConverter._admonitionIcons[type];
    var name = defaults?.$1;
    ThemeColor? color = switch (defaults?.$2) {
      final hex? => HexColor(hex),
      null => null,
    };
    var size = defaults?.$3 ?? 24;
    if (_theme.value('admonition_icon_$type') case ThemeMap(:final entries)) {
      if (entries['name'] case final value?) {
        name = value.rubyString;
        if (!iconSets.any((set) => name!.startsWith('$set-')) &&
            !name.startsWith('fa-')) {
          name = 'fa-$name';
        }
      }
      if (themeColor(entries['stroke_color']) case final value?) {
        color = value;
      }
      if (entries['size'] case ThemeNumber(:final value)) {
        size = value.toDouble();
      }
    }
    name ??= PdfConverter._admonitionIcons['note']!.$1;
    final (set, _, glyph) = _resolveIcon(name, null);
    if (glyph == null || !_iconsInstalled(set)) return null;
    return (set: set, glyph: glyph, color: color, size: size);
  }

  /// Whether the font of icon set [set] is installed; when it isn't, says
  /// so once (its icons are then shown as their text).
  bool _iconsInstalled(String set) {
    if (_fonts.hasIcons(set)) return true;
    if (_missingIcons.add(set)) {
      logger.warn(
        'the $set icon font is not installed: its icons are shown as text '
        '(`ptome doctor` installs it)',
      );
    }
    return false;
  }

  /// The set, name and glyph of icon [name] (`<set>-<name>`, a name of
  /// the `fa` set, or in [explicitSet]); the glyph is null when there's no
  /// such icon.
  (String, String, String?) _resolveIcon(String name, String? explicitSet) {
    var iconName = name;
    var set = explicitSet ?? _document.attr('icon-set') ?? 'fa';
    final explicit = explicitSet != null;
    String? glyph;
    if (set == 'fa' || !iconSets.contains(set)) {
      set = 'fa';
      final bare = iconName.startsWith('fa-')
          ? iconName.substring(3)
          : iconName;
      if (legacyIcon(bare) case final remapped?) {
        final dash = remapped.indexOf('-');
        set = remapped.substring(0, dash);
        iconName = remapped.substring(dash + 1);
        glyph = iconGlyph(set, iconName);
      } else {
        for (final candidate in fontAwesomeSets) {
          if (iconGlyph(candidate, iconName) case final found?) {
            set = candidate;
            glyph = found;
            break;
          }
        }
      }
    } else {
      glyph = iconGlyph(set, iconName);
    }
    if (glyph == null &&
        !explicit &&
        iconSets.any((prefix) => iconName.startsWith('$prefix-'))) {
      final dash = iconName.indexOf('-');
      set = iconName.substring(0, dash);
      iconName = iconName.substring(dash + 1);
      glyph = iconGlyph(set, iconName);
    }
    return (set, iconName, glyph);
  }
}
