/// A document of pages drawn through canvases, with links, named
/// destinations, outlines (bookmarks) and page labels, written with a
/// `PdfWriter` when saved.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_pdf/src/drawing/canvas.dart';
import 'package:plain_pdf/src/drawing/pdf_values.dart';
import 'package:plain_pdf/src/drawing/shading.dart';
import 'package:plain_pdf/src/fonts/fonts.dart';
import 'package:plain_pdf/src/images/images.dart';
import 'package:plain_pdf/src/objects.dart';
import 'package:plain_pdf/src/reader/reader.dart';
import 'package:plain_pdf/src/writer.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// A stream's data as the writer stores it (see [encodeStream]): the
/// compression it was encoded with, the data's length, and the
/// compressed data (null when compressing doesn't make it shorter, and
/// the data is stored as it is).
typedef StreamPayload = ({
  bool compress,
  int level,
  int length,
  Uint8List? data,
});

/// [data] encoded as a writer with [options] stores a stream of it:
/// compressed when that is shorter. Plain data, computed anywhere.
StreamPayload encodeStream(Uint8List data, PdfWriterOptions options) {
  final compressed = options.compress ? options.encodeZlib(data) : null;
  return (
    compress: options.compress,
    level: options.compressionLevel,
    length: data.length,
    data: compressed != null && compressed.length < data.length
        ? compressed
        : null,
  );
}

/// A page: its boxes, its content and its links.
final class PdfPage implements LayoutPage {
  new _(
    this.mediaBox, {
    this.cropBox,
    this.bleedBox,
    this.trimBox,
    this.artBox,
    this.rotation = 0,
  });

  /// The page's extent (`MediaBox`).
  final Rect mediaBox;

  /// The region shown and printed (`CropBox`); the media box by default.
  final Rect? cropBox;

  /// The region to clip to in production, with the bleed (`BleedBox`).
  final Rect? bleedBox;

  /// The finished page after trimming (`TrimBox`).
  final Rect? trimBox;

  /// The page's meaningful content (`ArtBox`).
  final Rect? artBox;

  /// The clockwise rotation when shown, a multiple of 90 degrees.
  final int rotation;

  /// The page's content.
  @override
  final PdfCanvas canvas = newCanvas();

  /// The content stream's data, as painted so far.
  Uint8List get content => canvasContent(canvas);

  /// The content stream as [encodeStream] encoded it elsewhere (another
  /// isolate, say), used when the page is written with the same
  /// compression and its content is as long as it was.
  StreamPayload? contentPayload;

  final List<(Rect, LinkTarget, StructureElement?)> _links = [];

  @override
  void link(Rect rect, LinkTarget target) =>
      _links.add((rect, target, canvasElement(canvas)));

  /// The page's width.
  double get width => mediaBox.width;

  /// The page's height.
  double get height => mediaBox.height;
}

/// A position in the document to go to (ISO 32000-2, 12.3.2.2).
@immutable
sealed class PdfDestination {
  const new _(this.page);

  /// The point ([left], [top]) of [page] at the top left of the window,
  /// at [zoom] (each kept as it is when null).
  const factory xyz(PdfPage page, {double? left, double? top, double? zoom}) =
      XyzDestination;

  /// The whole [page] in the window.
  const factory fit(PdfPage page) = FitDestination;

  /// [page] as wide as the window, with [top] at its top.
  const factory fitWidth(PdfPage page, {double? top}) = FitWidthDestination;

  /// [page] as tall as the window, with [left] at its left.
  const factory fitHeight(PdfPage page, {double? left}) = FitHeightDestination;

  /// The page.
  final PdfPage page;

  /// The destination as an array, with [pageRef] for its page.
  PdfArray _toArray(PdfRef pageRef);
}

/// A point of a page, at a zoom.
final class XyzDestination extends PdfDestination {
  /// The point ([left], [top]) of [page] at [zoom].
  const new(super.page, {this.left, this.top, this.zoom}) : super._();

  /// The left edge of the window, or null to keep it.
  final double? left;

  /// The top edge of the window, or null to keep it.
  final double? top;

  /// The zoom (1 is 100%), or null to keep it.
  final double? zoom;

  @override
  PdfArray _toArray(PdfRef pageRef) => PdfArray([
    pageRef,
    const PdfName('XYZ'),
    _number(left),
    _number(top),
    _number(zoom),
  ]);
}

/// A whole page.
final class FitDestination extends PdfDestination {
  /// The whole of [page].
  const new(super.page) : super._();

  @override
  PdfArray _toArray(PdfRef pageRef) =>
      PdfArray([pageRef, const PdfName('Fit')]);
}

/// A page as wide as the window.
final class FitWidthDestination extends PdfDestination {
  /// [page] as wide as the window, [top] at the top.
  const new(super.page, {this.top}) : super._();

  /// The top edge of the window, or null to keep it.
  final double? top;

  @override
  PdfArray _toArray(PdfRef pageRef) =>
      PdfArray([pageRef, const PdfName('FitH'), _number(top)]);
}

/// A page as tall as the window.
final class FitHeightDestination extends PdfDestination {
  /// [page] as tall as the window, [left] at the left.
  const new(super.page, {this.left}) : super._();

  /// The left edge of the window, or null to keep it.
  final double? left;

  @override
  PdfArray _toArray(PdfRef pageRef) =>
      PdfArray([pageRef, const PdfName('FitV'), _number(left)]);
}

PdfObject _number(double? value) => switch (value) {
  null => const PdfNull(),
  final v when v == v.roundToDouble() && v.abs() < 1e15 => PdfInt(v.toInt()),
  final v => PdfReal(v),
};

/// An explicit destination.
final class DestinationTarget extends LinkTarget {
  /// A link to [destination].
  const new(this.destination);

  /// The destination.
  final PdfDestination destination;
}

/// An item of the document outline (a bookmark), with its children.
final class PdfOutlineItem {
  /// An item titled [title] going to [target]; [open] shows its children.
  new(
    this.title,
    this.target, {
    this.open = false,
    this.bold = false,
    this.italic = false,
    this.color,
  });

  /// The title.
  final String title;

  /// Where the item goes.
  final LinkTarget? target;

  /// Whether the children are shown.
  final bool open;

  /// Whether the title is bold.
  final bool bold;

  /// Whether the title is italic.
  final bool italic;

  /// The title's color.
  final RgbColor? color;

  /// The children.
  final List<PdfOutlineItem> children = [];

  /// Adds a child titled [title] going to [target]; returns it.
  PdfOutlineItem add(
    String title,
    LinkTarget? target, {
    bool open = false,
    bool bold = false,
    bool italic = false,
    RgbColor? color,
  }) {
    final item = PdfOutlineItem(
      title,
      target,
      open: open,
      bold: bold,
      italic: italic,
      color: color,
    );
    children.add(item);
    return item;
  }

  /// The number of descendants shown when the item is shown.
  int get _visible => open
      ? children.length + children.fold<int>(0, (sum, c) => sum + c._visible)
      : 0;
}

/// How page numbers are written (ISO 32000-2, 12.4.2).
enum PageNumberStyle {
  /// 1, 2, 3...
  decimal('D'),

  /// I, II, III...
  upperRoman('R'),

  /// i, ii, iii...
  lowerRoman('r'),

  /// A, B, ... Z, AA...
  upperLetters('A'),

  /// a, b, ... z, aa...
  lowerLetters('a'),

  /// No number (the prefix only).
  none(null);

  new(this.pdfName);

  /// The style's PDF name, or null for none.
  final String? pdfName;
}

/// The labels of a range of pages: a [prefix], then the page number
/// from [start] in [style].
@immutable
final class PageLabel {
  /// Labels in [style] starting at [start], after [prefix].
  const new({
    this.style = PageNumberStyle.decimal,
    this.prefix,
    this.start = 1,
  });

  /// The numbering style.
  final PageNumberStyle style;

  /// The text before the number.
  final String? prefix;

  /// The number of the range's first page.
  final int start;
}

/// How a viewer shows the document when it opens.
enum PageMode {
  /// Neither outline nor thumbnails.
  useNone('UseNone'),

  /// With the outline.
  useOutlines('UseOutlines'),

  /// With page thumbnails.
  useThumbs('UseThumbs'),

  /// Full screen.
  fullScreen('FullScreen');

  new(this.pdfName);

  /// The mode's PDF name.
  final String pdfName;
}

/// How the document's colors are to be reproduced (ISO 32000-2, 14.11.5):
/// an output condition with its ICC profile, as PDF/X requires.
@immutable
final class PdfOutputIntent {
  /// The intent of printing to the condition [profile] (an ICC output
  /// profile) characterizes: [identifier] names it (a registered
  /// condition, or `Custom`), [condition] describes it, [registry] is
  /// where [identifier] is registered (`http://www.color.org`), and
  /// [subtype] is the standard the intent is for (`GTS_PDFX`).
  const new(
    this.profile, {
    required this.identifier,
    this.condition,
    this.registry,
    this.info,
    this.subtype = 'GTS_PDFX',
  });

  /// The ICC profile's bytes.
  final List<int> profile;

  /// The output condition's identifier.
  final String identifier;

  /// A description of the output condition.
  final String? condition;

  /// The registry [identifier] is in.
  final String? registry;

  /// More about the condition (required when [identifier] isn't
  /// registered).
  final String? info;

  /// The standard the intent is for.
  final String subtype;

  /// The profile's color components: 1 (gray), 3 (RGB, Lab) or 4 (CMYK),
  /// from its header; null when it isn't an ICC profile.
  int? get components {
    if (profile.length < 20) return null;
    return switch (String.fromCharCodes(profile.sublist(16, 20))) {
      'GRAY' => 1,
      'RGB ' || 'Lab ' => 3,
      'CMYK' => 4,
      _ => null,
    };
  }

  /// The profile's device class (`prtr` for an output profile), from its
  /// header; null when it isn't an ICC profile.
  String? get deviceClass => profile.length < 16
      ? null
      : String.fromCharCodes(profile.sublist(12, 16));
}

/// A PDF document.
final class PdfDocument implements LayoutDocument<PdfPage> {
  /// An empty document with [info]; [language] is its natural language
  /// (`en-US`), [pageMode] how it opens (and [nonFullScreenPageMode] how
  /// it shows when it leaves full screen), [displayTitle] whether viewers
  /// show the title rather than the file name.
  new({
    this.info = const PdfInfo(),
    this.language,
    this.pageMode,
    this.nonFullScreenPageMode,
    this.displayTitle = false,
    this.tagged = false,
  });

  /// Whether the document is a tagged PDF (ISO 32000-2, 14.8): its pages'
  /// content marked as the elements of its logical structure their
  /// canvases are told it is ([StructureCanvas]), or as artifacts, its
  /// structure tree written with it, its links in it.
  final bool tagged;

  /// The logical structure painted on the pages, when [tagged].
  final _StructureTree _structure = _StructureTree();

  /// The document information.
  final PdfInfo info;

  /// The natural language.
  final String? language;

  /// How the document opens.
  final PageMode? pageMode;

  /// How the document shows when it leaves full screen ([PageMode.useNone],
  /// [PageMode.useOutlines] or [PageMode.useThumbs]).
  final PageMode? nonFullScreenPageMode;

  /// Where the document opens (a destination on one of its pages).
  PdfDestination? openAction;

  /// Whether viewers show the title in the window's title bar.
  final bool displayTitle;

  /// How the colors are to be reproduced (PDF/X: one, for `GTS_PDFX`).
  final List<PdfOutputIntent> outputIntents = [];

  final List<PdfPage> _pages = [];

  /// The pages, in order.
  List<PdfPage> get pages => List.unmodifiable(_pages);

  /// The outline's top-level items.
  final List<PdfOutlineItem> outline = [];

  final Map<String, PdfDestination> _destinations = {};

  final Map<int, PageLabel> _labels = {};

  /// Adds a page of [mediaBox] (with the other boxes) and returns it.
  @override
  PdfPage addPage(
    Rect mediaBox, {
    Rect? cropBox,
    Rect? bleedBox,
    Rect? trimBox,
    Rect? artBox,
    int rotation = 0,
  }) {
    if (rotation % 90 != 0) {
      throw ArgumentError.value(rotation, 'rotation', 'not a multiple of 90');
    }
    final page = PdfPage._(
      mediaBox,
      cropBox: cropBox,
      bleedBox: bleedBox,
      trimBox: trimBox,
      artBox: artBox,
      rotation: rotation,
    );
    if (tagged) tagCanvas(page.canvas, _structure.page(_pages.length));
    _pages.add(page);
    return page;
  }

  /// Adds an outline item titled [title] going to [target]; returns it.
  PdfOutlineItem addOutline(
    String title,
    LinkTarget? target, {
    bool open = false,
    bool bold = false,
    bool italic = false,
    RgbColor? color,
  }) {
    final item = PdfOutlineItem(
      title,
      target,
      open: open,
      bold: bold,
      italic: italic,
      color: color,
    );
    outline.add(item);
    return item;
  }

  /// Names [destination] [name], for links and outline items (and for
  /// links from other documents, `file.pdf#name`).
  void addDestination(String name, PdfDestination destination) =>
      _destinations[name] = destination;

  /// Adds the destination [name] at ([left], [top]) of [page] (an XYZ
  /// destination that keeps the zoom).
  @override
  void addAnchor(String name, PdfPage page, double left, double top) =>
      addDestination(name, PdfDestination.xyz(page, left: left, top: top));

  /// Labels the pages from [pageIndex] (0-based) on, up to the next
  /// labeled index, with [label].
  void labelPages(int pageIndex, PageLabel label) => _labels[pageIndex] = label;

  /// The document as PDF bytes.
  Uint8List save({PdfWriterOptions options = const PdfWriterOptions()}) {
    final out = BytesBuilder(copy: false);
    saveTo(out.add, options: options);
    return out.takeBytes();
  }

  /// Writes the document to [sink].
  void saveTo(
    void Function(List<int> bytes) sink, {
    PdfWriterOptions options = const PdfWriterOptions(),
  }) {
    for (final (i, page) in _pages.indexed) {
      if (canvasUnbalanced(page.canvas) case final problem?) {
        throw StateError('page ${i + 1}: $problem');
      }
    }
    _Saver(this, PdfWriter(sink, options: options, version: _version)).save();
  }

  /// The lowest PDF version with every feature the document uses:
  /// transparency, `Lang` and `DisplayDocTitle` need 1.4, 16-bit images
  /// 1.5 (as do the object streams the writer raises the version for).
  String get _version {
    final seen = <PdfForm>{};
    bool deep(PdfCanvas canvas) => canvasResources(canvas).values.any(
      (entries) => entries.values.any(
        (resource) => switch (resource) {
          ImageResource(image: PdfImage(bitsPerComponent: 16)) => true,
          FormResource(:final form) => seen.add(form) && deep(formCanvas(form)),
          _ => false,
        },
      ),
    );
    // PDF/X-4 is based on PDF 1.6.
    if (info.pdfxVersion != null) return '1.6';
    return _pages.any((page) => deep(page.canvas)) ? '1.5' : '1.4';
  }
}

/// Writes a document's objects.
final class _Saver {
  new(this.document, this.writer);

  final PdfDocument document;
  final PdfWriter writer;
  final Map<PdfPage, PdfRef> _pageRefs = {};
  final Map<PdfForm, PdfRef> _formRefs = {};
  final List<PdfForm> _formQueue = [];
  final Set<PdfFont> _fonts = {};
  final Set<PdfImage> _images = {};
  final Map<(String, CmykColor), PdfArray> _separations = {};
  final Map<PdfShading, PdfRef> _shadings = Map.identity();
  final Map<ImportedPage, PdfRef> _importedPages = Map.identity();
  late final ObjectCopier _copier = ObjectCopier(writer);

  void save() {
    final catalog = writer.reserve();
    final pages = writer.reserve();
    for (final page in document._pages) {
      _pageRefs[page] = writer.reserve();
    }
    for (final page in document._pages) {
      _writePage(page, pages);
    }
    // Forms can use forms: write until none is left.
    while (_formQueue.isNotEmpty) {
      final form = _formQueue.removeAt(0);
      _writeForm(form);
    }
    _copier.flush();
    for (final font in _fonts) {
      font.writeTo(writer);
    }
    for (final image in _images) {
      image.writeTo(writer);
    }
    writer.write(
      PdfDict({
        'Type': const PdfName('Pages'),
        'Kids': PdfArray([
          for (final page in document._pages) _pageRefs[page]!,
        ]),
        'Count': PdfInt(document._pages.length),
      }),
      pages,
    );
    final info = writer.writeInfo(document.info);
    final structure = document.tagged ? _writeStructure() : null;
    writer
      ..write(
        PdfDict({
          'Type': const PdfName('Catalog'),
          'Pages': pages,
          'Metadata': info.metadata,
          if (structure != null) ...{
            'MarkInfo': PdfDict({'Marked': const PdfBool(true)}),
            'StructTreeRoot': structure,
          },
          'Outlines': ?_writeOutline(),
          if (document._destinations.isNotEmpty)
            'Names': PdfDict({'Dests': _destinationTree()}),
          if (document._labels.isNotEmpty) 'PageLabels': _pageLabels(),
          if (document.pageMode case final mode?)
            'PageMode': PdfName(mode.pdfName),
          if (document.language case final language?)
            'Lang': PdfString.text(language),
          if (document.outputIntents.isNotEmpty)
            'OutputIntents': PdfArray([
              for (final intent in document.outputIntents)
                _outputIntent(intent),
            ]),
          if (document.openAction case final destination?)
            'OpenAction': destination._toArray(_pageRef(destination.page)),
          if (document.displayTitle || document.nonFullScreenPageMode != null)
            'ViewerPreferences': PdfDict({
              if (document.displayTitle) 'DisplayDocTitle': const PdfBool(true),
              if (document.nonFullScreenPageMode case final mode?)
                'NonFullScreenPageMode': PdfName(mode.pdfName),
            }),
        }),
        catalog,
      )
      ..close(root: catalog, info: info.info);
  }

  PdfDict _outputIntent(PdfOutputIntent intent) {
    final components = intent.components;
    if (components == null) {
      throw ArgumentError.value(
        intent.identifier,
        'intent',
        'the output profile is not an ICC profile',
      );
    }
    return PdfDict({
      'Type': const PdfName('OutputIntent'),
      'S': PdfName(intent.subtype),
      'OutputConditionIdentifier': PdfString.text(intent.identifier),
      if (intent.condition case final condition?)
        'OutputCondition': PdfString.text(condition),
      if (intent.registry case final registry?)
        'RegistryName': PdfString.text(registry),
      if (intent.info case final info?) 'Info': PdfString.text(info),
      'DestOutputProfile': writer.write(
        PdfStream(intent.profile, dict: PdfDict({'N': PdfInt(components)})),
      ),
    });
  }

  void _writePage(PdfPage page, PdfRef parent) {
    closeCanvasMarks(page.canvas);
    final data = canvasContent(page.canvas);
    final options = writer.options;
    final content = writer.write(switch (page.contentPayload) {
      (:final compress, :final level, :final length, data: final encoded)
          when compress &&
              options.compress &&
              level == options.compressionLevel &&
              length == data.length =>
        encoded == null
            ? PdfStream(data, compress: false)
            : PdfStream(
                encoded,
                dict: PdfDict({'Filter': const PdfName('FlateDecode')}),
                compress: false,
              ),
      _ => PdfStream(data),
    });
    final tagged = document.tagged;
    final annotations = <PdfRef>[];
    for (final (rect, target, element) in page._links) {
      final ref = writer.reserve();
      // (In a tagged document, each link a Link element of the element
      // whose text it is, the annotation described.)
      final key = tagged ? _structure.link(ref, page, element) : null;
      writer.write(
        PdfDict({
          'Type': const PdfName('Annot'),
          'Subtype': const PdfName('Link'),
          'Rect': rect.toArray(),
          'Border': PdfArray.numbers([0, 0, 0]),
          ..._linkEntries(target),
          if (key != null) ...{
            'StructParent': PdfInt(key),
            'Contents': PdfString.text(_describe(target)),
          },
        }),
        ref,
      );
      annotations.add(ref);
    }
    writer.write(
      PdfDict({
        'Type': const PdfName('Page'),
        'Parent': parent,
        'MediaBox': page.mediaBox.toArray(),
        'CropBox': ?page.cropBox?.toArray(),
        'BleedBox': ?page.bleedBox?.toArray(),
        'TrimBox': ?page.trimBox?.toArray(),
        'ArtBox': ?page.artBox?.toArray(),
        if (page.rotation % 360 != 0) 'Rotate': PdfInt(page.rotation % 360),
        'Resources': _resources(page.canvas),
        'Contents': content,
        if (annotations.isNotEmpty) 'Annots': PdfArray(annotations),
        if (canvasUsesTransparency(page.canvas)) 'Group': _group(null),
        if (tagged) ...{
          'StructParents': PdfInt(document._pages.indexOf(page)),
          // (Annotations in the order of the structure, as PDF/UA has
          // them.)
          if (annotations.isNotEmpty) 'Tabs': const PdfName('S'),
        },
      }),
      _pageRefs[page],
    );
  }

  _StructureTree get _structure => document._structure;

  /// What a link to [target] is, for assistive technology.
  static String _describe(LinkTarget target) => switch (target) {
    UriTarget(:final uri) => uri,
    NamedTarget(:final name) => 'Go to $name',
    _ => 'Link',
  };

  /// The structure tree, its root's reference: each element's dictionary
  /// (its role, parent, kids: elements, marked content on a page, link
  /// annotations), the parent tree from the pages' marked-content ids and
  /// the links' keys to their elements.
  PdfRef _writeStructure() {
    final structure = _structure;
    final root = writer.reserve();
    final document = _StructureNode(StructureElement('Document'));
    document.kids.addAll(structure.roots);
    final refs = <_StructureNode, PdfRef>{};
    void reserve(_StructureNode node) {
      refs[node] = writer.reserve();
      for (final kid in node.kids) {
        if (kid is _StructureNode) reserve(kid);
      }
    }

    reserve(document);
    void write(_StructureNode node, PdfRef parent) {
      final element = node.element;
      final kids = <PdfObject>[];
      for (final kid in node.kids) {
        switch (kid) {
          case final _StructureNode child:
            write(child, refs[node]!);
            kids.add(refs[child]!);
          case (final int page, final int mcid):
            kids.add(
              PdfDict({
                'Type': const PdfName('MCR'),
                'Pg': _pageRefs[this.document._pages[page]]!,
                'MCID': PdfInt(mcid),
              }),
            );
          case (final PdfRef annotation, final PdfPage page):
            kids.add(
              PdfDict({
                'Type': const PdfName('OBJR'),
                'Obj': annotation,
                'Pg': _pageRefs[page]!,
              }),
            );
        }
      }
      final attributes = element.attributes;
      writer.write(
        PdfDict({
          'Type': const PdfName('StructElem'),
          'S': PdfName(element.role),
          'P': parent,
          if (kids.isNotEmpty) 'K': PdfArray(kids),
          if (element.alt case final alt?) 'Alt': PdfString.text(alt),
          if (element.language case final language?)
            'Lang': PdfString.text(language),
          if (element.actualText case final text?)
            'ActualText': PdfString.text(text),
          if (attributes.isNotEmpty)
            'A': PdfDict({
              'O': PdfName(switch (element.role) {
                'Table' || 'TR' || 'TH' || 'TD' => 'Table',
                'L' || 'LI' || 'Lbl' || 'LBody' => 'List',
                _ => 'Layout',
              }),
              for (final MapEntry(:key, :value) in attributes.entries)
                key: value.startsWith('/')
                    ? PdfName(value.substring(1))
                    : PdfString.text(value),
            }),
        }),
        refs[node],
      );
    }

    write(document, root);
    final nums = <PdfObject>[];
    for (final (page, marks) in structure.marks.indexed) {
      nums
        ..add(PdfInt(page))
        ..add(PdfArray([for (final node in marks) refs[node]!]));
    }
    for (final (key, node) in structure.links) {
      nums
        ..add(PdfInt(key))
        ..add(refs[node]!);
    }
    writer.write(
      PdfDict({
        'Type': const PdfName('StructTreeRoot'),
        'K': refs[document]!,
        'ParentTree': PdfDict({'Nums': PdfArray(nums)}),
        'ParentTreeNextKey': PdfInt(structure.nextKey),
      }),
      root,
    );
    return root;
  }

  /// The `Dest` or `A` (action) entry for [target].
  Map<String, PdfObject> _linkEntries(LinkTarget target) => switch (target) {
    UriTarget(:final uri) => {
      'A': PdfDict({
        'S': const PdfName('URI'),
        'URI': PdfString(_asciiUri(uri)),
      }),
    },
    NamedTarget(:final name) => {'Dest': PdfString(utf8.encode(name))},
    DestinationTarget(:final destination) => {
      'Dest': destination._toArray(_pageRef(destination.page)),
    },
    _ => throw ArgumentError.value(target, 'target', 'not a PDF link target'),
  };

  PdfRef _pageRef(PdfPage page) =>
      _pageRefs[page] ??
      (throw ArgumentError('a destination is on a page of another document'));

  /// [uri] in 7-bit ASCII, as PDF wants URIs: other characters as UTF-8
  /// percent escapes.
  static List<int> _asciiUri(String uri) => [
    for (final byte in utf8.encode(uri))
      if (byte < 0x80)
        byte
      else
        ...ascii.encode('%${byte.toRadixString(16).toUpperCase()}'),
  ];

  PdfDict _resources(PdfCanvas canvas) => PdfDict({
    for (final MapEntry(key: category, value: entries) in canvasResources(
      canvas,
    ).entries)
      category: PdfDict({
        for (final MapEntry(key: name, value: resource) in entries.entries)
          name: _resource(resource),
      }),
  });

  PdfObject _resource(Resource resource) {
    switch (resource) {
      case FontResource(:final font, :final subset):
        _fonts.add(font);
        return switch (font) {
          EmbeddedFont(singleByte: true) => font.subsetReference(
            writer,
            subset,
          ),
          _ => font.reference(writer),
        };
      case ImageResource(:final image):
        _images.add(image);
        return image.reference(writer);
      case FormResource(:final form):
        return _formRef(form);
      case ImportedPageResource(:final page):
        return _importedPages[page] ??= writer.write(
          PdfStream(
            page.content,
            dict: PdfDict({
              'Type': const PdfName('XObject'),
              'Subtype': const PdfName('Form'),
              'BBox': page.box.toArray(),
              'Resources': page.resources == null
                  ? PdfDict()
                  : _copier.copy(page.file, page.resources),
              if (page.group case final group?)
                'Group': _copier.copy(page.file, group),
            }),
          ),
        );
      case ShadingResource(:final shading):
        return _shadings[shading] ??= writer.write(shadingDict(shading));
      case SeparationResource(:final name, :final alternate):
        return _separations[(name, alternate)] ??= PdfArray([
          const PdfName('Separation'),
          PdfName(name),
          const PdfName('DeviceCMYK'),
          PdfDict({
            'FunctionType': const PdfInt(2),
            'Domain': PdfArray.numbers([0, 1]),
            'C0': PdfArray.numbers([0, 0, 0, 0]),
            'C1': PdfArray.numbers(alternate.components),
            'N': const PdfInt(1),
          }),
        ]);
      case GraphicsStateResource(
        :final fillOpacity,
        :final strokeOpacity,
        :final blendMode,
        :final softMask,
        :final clearSoftMask,
      ):
        return PdfDict({
          'Type': const PdfName('ExtGState'),
          if (fillOpacity != null) 'ca': PdfReal(fillOpacity),
          if (strokeOpacity != null) 'CA': PdfReal(strokeOpacity),
          if (blendMode != null) 'BM': PdfName(blendMode.pdfName),
          if (softMask case (final form, final kind))
            'SMask': PdfDict({
              'Type': const PdfName('Mask'),
              'S': PdfName(kind.pdfName),
              'G': _formRef(form),
            }),
          if (clearSoftMask) 'SMask': const PdfName('None'),
        });
    }
  }

  PdfRef _formRef(PdfForm form) => _formRefs[form] ??= () {
    _formQueue.add(form);
    return writer.reserve();
  }();

  void _writeForm(PdfForm form) {
    writer.write(
      PdfStream(
        canvasContent(formCanvas(form)),
        dict: PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Form'),
          'BBox': form.bbox.toArray(),
          'Matrix': ?form.matrix?.toArray(),
          'Resources': _resources(formCanvas(form)),
          if (form.group case final group?) 'Group': _group(group),
        }),
      ),
      _formRefs[form],
    );
  }

  PdfDict _group(TransparencyGroup? group) => PdfDict({
    'Type': const PdfName('Group'),
    'S': const PdfName('Transparency'),
    'CS': const PdfName('DeviceRGB'),
    if (group?.isolated ?? false) 'I': const PdfBool(true),
    if (group?.knockout ?? false) 'K': const PdfBool(true),
  });

  PdfRef? _writeOutline() {
    if (document.outline.isEmpty) return null;
    final root = writer.reserve();
    final (first, last) = _writeItems(document.outline, root);
    final visible =
        document.outline.length +
        document.outline.fold<int>(0, (sum, item) => sum + item._visible);
    writer.write(
      PdfDict({
        'Type': const PdfName('Outlines'),
        'First': first,
        'Last': last,
        'Count': PdfInt(visible),
      }),
      root,
    );
    return root;
  }

  /// Writes [items] under [parent]; returns the first and last.
  (PdfRef, PdfRef) _writeItems(List<PdfOutlineItem> items, PdfRef parent) {
    final refs = [for (final _ in items) writer.reserve()];
    for (final (i, item) in items.indexed) {
      final children = item.children.isEmpty
          ? null
          : _writeItems(item.children, refs[i]);
      final count = item.open ? item._visible : -item.children.length;
      final flags = (item.italic ? 1 : 0) | (item.bold ? 2 : 0);
      writer.write(
        PdfDict({
          'Title': PdfString.text(item.title),
          'Parent': parent,
          if (i > 0) 'Prev': refs[i - 1],
          if (i < items.length - 1) 'Next': refs[i + 1],
          if (children case (final first, final last)) ...{
            'First': first,
            'Last': last,
            'Count': PdfInt(count),
          },
          if (item.target case final target?) ..._linkEntries(target),
          if (item.color case final color?)
            'C': PdfArray.numbers(color.components),
          if (flags != 0) 'F': PdfInt(flags),
        }),
        refs[i],
      );
    }
    return (refs.first, refs.last);
  }

  /// The name tree of named destinations: one node, names in byte order.
  PdfDict _destinationTree() {
    final names = document._destinations.keys.toList()
      ..sort((a, b) => _compareBytes(utf8.encode(a), utf8.encode(b)));
    return PdfDict({
      'Names': PdfArray([
        for (final name in names) ...[
          PdfString(utf8.encode(name)),
          document._destinations[name]!._toArray(
            _pageRef(document._destinations[name]!.page),
          ),
        ],
      ]),
    });
  }

  static int _compareBytes(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  PdfDict _pageLabels() {
    final indices = document._labels.keys.toList()..sort();
    return PdfDict({
      'Nums': PdfArray([
        for (final index in indices) ...[
          PdfInt(index),
          () {
            final label = document._labels[index]!;
            return PdfDict({
              'Type': const PdfName('PageLabel'),
              if (label.style.pdfName case final style?) 'S': PdfName(style),
              if (label.prefix case final prefix?) 'P': PdfString.text(prefix),
              if (label.start != 1) 'St': PdfInt(label.start),
            });
          }(),
        ],
      ]),
    });
  }
}

/// A node of the structure tree: an element, its kids in order (nodes,
/// marked content as a page index and a marked-content id, link
/// annotations as their reference and page).
final class _StructureNode {
  new(this.element);

  final StructureElement element;
  final List<Object> kids = [];
}

/// The logical structure painted on a tagged document's pages.
final class _StructureTree {
  /// Each element's node.
  final Map<StructureElement, _StructureNode> _nodes = Map.identity();

  /// The nodes begun at the top, in order.
  final List<_StructureNode> roots = [];

  /// Each page's marked content: the node of each marked-content id.
  final List<List<_StructureNode>> marks = [];

  /// The links' keys in the parent tree and their Link nodes.
  final List<(int, _StructureNode)> links = [];

  /// The next key of the parent tree (the pages' are their indices).
  int get nextKey => marks.length + links.length;

  _StructureNode _node(StructureElement element, StructureElement? parent) {
    if (_nodes[element] case final node?) return node;
    final node = _nodes[element] = _StructureNode(element);
    switch (parent) {
      case final parent? when _nodes[parent] != null:
        _nodes[parent]!.kids.add(node);
      case _:
        roots.add(node);
    }
    return node;
  }

  /// The recorder of page [index]'s structure.
  StructureRecorder page(int index) {
    while (marks.length <= index) {
      marks.add([]);
    }
    return _PageStructure(this, index);
  }

  /// A Link element for the annotation [ref] on [page], in [element] (at
  /// the top without one): the annotation's key in the parent tree.
  int link(PdfRef ref, PdfPage page, StructureElement? element) {
    final node = _StructureNode(StructureElement('Link'))
      ..kids.add((ref, page));
    switch (element) {
      case final element? when _nodes[element] != null:
        _nodes[element]!.kids.add(node);
      case _:
        roots.add(node);
    }
    final key = marks.length + links.length;
    links.add((key, node));
    return key;
  }
}

/// Records one page's structure in the tree.
final class _PageStructure implements StructureRecorder {
  const new(this.tree, this.index);

  final _StructureTree tree;
  final int index;

  @override
  void begin(StructureElement element, StructureElement? parent) =>
      tree._node(element, parent);

  @override
  int mark(StructureElement element) {
    final node = tree._node(element, null);
    final marks = tree.marks[index];
    node.kids.add((index, marks.length));
    marks.add(node);
    return marks.length - 1;
  }
}
