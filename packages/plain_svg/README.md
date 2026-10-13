# plain_svg

SVG images in pure Dart, drawn on any canvas: shapes and paths,
transforms, nested viewports, `use` and `symbol`, fill and stroke (dashes,
caps, joins), CSS style sheets and presentation attributes, linear and
radial gradients, clip paths, group opacity, text, and raster or SVG
images. What an image uses that isn't drawn (masks, filters, markers,
patterns...) is listed in its `warnings`, never thrown.

```dart
import 'package:plain_svg/plain_svg.dart';

final svg = SvgImage.parse(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 60">'
  '<rect x="5" y="5" width="90" height="50" rx="8" fill="teal"/></svg>',
);
svg.paint(canvas, Rect(72, 600, svg.width, svg.height));
```

- `SvgImage.parse` reads the document with the package's own XML 1.0
  reader: namespaces, the internal subset's entities (Illustrator's
  `style="&st0;"`), line breaks and attribute white space normalized; it
  throws a `FormatException` with the line and column when the document
  isn't well formed. `fonts` chooses a font for each `font-family`
  (then `fallbackFontFamily`, then `sans-serif`); `images` reads the
  images an SVG refers to and `rasters` turns a PNG or JPEG into a
  graphic; `pixelSize` is a user unit in points.
- An `SvgImage` is a plain_typesetting `Graphic`: it draws on any
  `Canvas`. On an `SvgCanvas`, which also paints transparency groups,
  gradients and luminosity masks, it draws all of it; on another canvas,
  a group's opacity goes to each element and a gradient is drawn in its
  first color, and its warnings say so.
- `SvgPath` reads SVG path data (SVG 2, 9.3) into absolute segments,
  arcs as Bézier curves, and makes shapes as paths.

[plain_pdf](https://github.com/nsmmrs/ptome/tree/master/packages/plain_pdf)'s
`PdfCanvas` is an `SvgCanvas` (groups as forms, gradients as shadings,
masks as soft masks), and its `standardSvgFont` and `readSvgRaster` give
an SVG the standard fonts and PDF images. SVG drawn in a PDF is checked
against resvg's reference renders, nightly.

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace, where it draws a document's SVG images in its PDFs.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE).
