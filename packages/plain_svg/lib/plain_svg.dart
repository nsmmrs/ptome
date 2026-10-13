/// plain_svg: SVG images drawn on any canvas, in pure Dart.
///
/// - `SvgImage` reads an SVG document (with its own XML reader) and draws
///   it on a plain_typesetting `Canvas`: shapes and paths, transforms,
///   nested viewports, `use` and `symbol`, fill and stroke, CSS style
///   sheets, gradients, clip paths, group opacity, text, and raster or SVG
///   images; what it doesn't draw is in its warnings.
/// - `SvgCanvas`: what a canvas offers beyond plain_typesetting's for
///   groups, gradients and masks (plain_pdf's canvas is one).
/// - `SvgPath`: SVG path data, shapes as paths, arcs as Bézier curves.
library;

export 'src/canvas.dart'
    show ColorStop, Gradient, LinearGradient, RadialGradient, SvgCanvas;
export 'src/path.dart'
    show
        CloseSegment,
        CubicSegment,
        LineSegment,
        MoveSegment,
        PathSegment,
        SvgPath;
export 'src/svg.dart'
    show SvgFontResolver, SvgImage, SvgImageResolver, SvgRasterReader;
