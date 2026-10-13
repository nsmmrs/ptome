/// What a canvas offers SVG beyond plain_typesetting's `Canvas`: groups
/// composited as one, gradients, and masks.
library;

import 'package:meta/meta.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// A canvas that also paints transparency groups, gradients and soft
/// masks (as PDF does, ISO 32000-2, 11 and 8.7).
///
/// An `SvgImage` draws on any `Canvas`;
/// on one that isn't an [SvgCanvas] it paints a group's children one by
/// one, a gradient in its first color and stop opacities not at all, and
/// says so in its warnings.
abstract interface class SvgCanvas implements Canvas {
  /// Paints what [draw] paints as one transparency group, composited with
  /// the current state (its opacity, say) as a whole; [bounds] encloses
  /// it, in the current coordinates.
  void group(Rect bounds, void Function(SvgCanvas canvas) draw);

  /// Paints [gradient] over the whole clipping region, in the current
  /// coordinates.
  void gradient(Gradient gradient);

  /// Masks what is painted next (until the state is restored) by the
  /// luminosity of what [draw] paints, as a group within [bounds].
  void luminosityMask(Rect bounds, void Function(SvgCanvas canvas) draw);
}

/// A color at an offset along a gradient.
@immutable
final class ColorStop {
  /// [color] at [offset] (0 to 1).
  const new(this.offset, this.color);

  /// Where along the gradient, from 0 to 1.
  final double offset;

  /// The color there.
  final Color color;
}

/// A gradient: colors blended between stops, padded past the ends.
@immutable
sealed class Gradient {
  const new(this.stops);

  /// The stops, by offset.
  final List<ColorStop> stops;
}

/// A gradient along the line from ([x1], [y1]) to ([x2], [y2]).
final class LinearGradient extends Gradient {
  /// A gradient from ([x1], [y1]) (offset 0) to ([x2], [y2]) (offset 1).
  const new(this.x1, this.y1, this.x2, this.y2, super.stops);

  /// The start.
  final double x1;

  /// (See [x1].)
  final double y1;

  /// The end.
  final double x2;

  /// (See [x2].)
  final double y2;
}

/// A gradient between two circles: the focal one at ([fx], [fy]) of
/// radius [fr] (offset 0) and the one at ([cx], [cy]) of radius [r]
/// (offset 1).
final class RadialGradient extends Gradient {
  /// A gradient from the focal circle to the outer one.
  const new(this.fx, this.fy, this.fr, this.cx, this.cy, this.r, super.stops);

  /// The focal circle's center.
  final double fx;

  /// (See [fx].)
  final double fy;

  /// The focal circle's radius.
  final double fr;

  /// The outer circle's center.
  final double cx;

  /// (See [cx].)
  final double cy;

  /// The outer circle's radius.
  final double r;
}
