part of '../converter.dart';

// The outline.

extension _Outline on PdfConverter {
  /// The outline (the document title, then the sections to
  /// `outlinelevels`) and the page labels (the gem's `add_outline`).
  void _outline(PdfDocument pdf, List<PdfPage> pages, LayoutResult result) {
    final frontMatter = _skip.$2;
    // The back cover is added after the labels (it continues the last).
    final labeled = _backCover ? pages.length - 1 : pages.length;
    for (var n = 0; n < labeled; n++) {
      pdf.labelPages(
        n,
        PageLabel(
          style: PageNumberStyle.none,
          prefix: n < frontMatter
              ? PdfConverter._roman(n + 1)
              : '${n - frontMatter + 1}',
        ),
      );
    }
    if (!_document.hasAttr('outline')) return;
    var levels = _tocLevels;
    var expand = levels;
    final setting = _document.attr('outlinelevels');
    if (setting != null) {
      if (setting.contains(':')) {
        final [count, open] = setting.split(':');
        levels = count.isEmpty ? levels : int.tryParse(count) ?? levels;
        expand = int.tryParse(open) ?? 0;
      } else {
        levels = expand = int.tryParse(setting) ?? levels;
      }
    }
    final anchors = {
      for (final (section, anchor) in _sections) section: anchor,
    };
    PdfDestination? destination(Section section) {
      final anchor = anchors[section];
      final position = anchor == null ? null : result.anchors[anchor];
      if (position == null) return null;
      return PdfDestination.xyz(pages[position.page], left: 0, top: position.y);
    }

    final titlePage = _frontCover ? 1 : 0;
    if (pages.length > titlePage) {
      // An outline title, or the document title for an empty one; none
      // when the attribute is unset.
      var title = _document.attr('outline-title');
      if (title != null && title.isEmpty) {
        title = PdfConverter._resolveDoctitle(_document) ?? '';
      }
      if (title != null && title.isNotEmpty) {
        final page = pages[titlePage];
        pdf.addOutline(
          PdfConverter._plain(title),
          DestinationTarget(
            PdfDestination.xyz(page, left: 0, top: page.height),
          ),
        );
      }
    }
    // The table of contents, as a section of its own (the gem's
    // `insert_toc_section`): first, or after the section its macro is in.
    final tocTitle = _document.attr('toc-title') ?? '';
    final tocNode = _document.attr('toc-placement') == 'macro'
        ? _document.findBy(context: BlockContext.toc).firstOrNull
        : null;
    final tocAfter = switch (tocNode?.parent) {
      final Section section => section,
      _ => null,
    };
    // (At the level of the section its macro follows, else of the first
    // section; left out, as a section is, below the levels shown.)
    void addToc(PdfOutlineItem? parent, int levels) {
      final pages_ = _tocPages;
      final sections = _sectionsOf(_document);
      if (pages_ == null ||
          tocTitle.isEmpty ||
          sections.isEmpty ||
          pages_.$1 > pages.length ||
          ((tocAfter ?? sections.first).level ?? 1) > levels) {
        return;
      }
      final anchor = tocNode == null
          ? null
          : result.anchors[tocNode.id ?? 'toc'];
      final PdfDestination destination;
      if (anchor != null) {
        destination = PdfDestination.xyz(
          pages[anchor.page],
          left: 0,
          top: anchor.y,
        );
      } else {
        final page = pages[pages_.$1 - 1];
        destination = PdfDestination.xyz(page, left: 0, top: page.height);
      }
      final target = DestinationTarget(destination);
      if (parent == null) {
        pdf.addOutline(PdfConverter._plain(tocTitle), target);
      } else {
        parent.add(PdfConverter._plain(tocTitle), target);
      }
    }

    void level(
      List<Section> sections,
      int levels,
      int expand,
      PdfOutlineItem? parent,
    ) {
      for (final section in sections) {
        final sectionLevels =
            int.tryParse(section.attr('outlinelevels') ?? '') ?? levels;
        final depth = section.level ?? 1;
        if (sectionLevels < depth) continue;
        if (section.hasOption('notitle') &&
            section == _document.blocks.lastOrNull &&
            section.blocks.isEmpty) {
          continue;
        }
        final title = PdfConverter._plain(_numberedTitle(section));
        if (title.isEmpty) continue;
        final target = switch (destination(section)) {
          final d? => DestinationTarget(d),
          null => null,
        };
        final children = _sectionsOf(section);
        final open = depth < sectionLevels && children.isNotEmpty;
        final item = parent == null
            ? pdf.addOutline(title, target, open: open && expand >= 1)
            : parent.add(title, target, open: open && expand >= 1);
        if (open) level(children, sectionLevels, expand - 1, item);
        if (section == tocAfter) addToc(parent, levels);
      }
    }

    if (tocAfter == null) addToc(null, levels);
    level(_sectionsOf(_document), levels, expand, null);
  }
}
