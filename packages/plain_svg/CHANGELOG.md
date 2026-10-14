# Changelog

## 0.1.0-dev (unreleased)

- An image is clipped to its viewport again, as before, except where it
  is placed as prawn-svg places it (`scalesAboutPageOrigin`): the resvg
  cases `embedded-jpeg-luma` and `embedded-png-luma` are drawn alike
  again (BUG-cttrlc).
- An `<image>` is clipped to its viewport only when it reaches past it
  (`slice`): a clip on an edge the image ends on anyway changed how
  renderers smooth that edge. With `scalesAboutPageOrigin`, the viewport
  is clipped by a path, as prawn-svg clips it.
- SVG images (`SvgImage`) and path data (`SvgPath` and its segments),
  moved from plain_pdf with their history, now drawn on any
  plain_typesetting `Canvas`. `SvgCanvas`: what a canvas offers beyond
  it (transparency groups, `LinearGradient` and `RadialGradient` with
  their `ColorStop`s, luminosity masks); on another canvas a group's
  opacity goes to each element and a gradient is drawn in its first
  color. Fonts through `SvgFontResolver` (any `Font`; none by default),
  raster images through `SvgRasterReader`.
- Its own XML 1.0 reader instead of package:xml: namespaces as Namespaces
  in XML 1.0 has them, the internal subset's general entities expanded
  (Illustrator's styles in entities are drawn), line breaks and attribute
  white space normalized; errors with their line and column. Checked
  against package:xml on 3,000 random documents and the workspace's SVG
  files.
- Fixed: path data with numbers after a close path (`z 6 5`) no longer
  makes the reader loop forever; a clip path that clips itself and an
  image that shows itself no longer recurse without end; path data that
  doesn't begin with a move draws nothing (SVG 2, 9.5.1) instead of
  failing.
- The same drawing compiled to JavaScript as on the Dart VM.
