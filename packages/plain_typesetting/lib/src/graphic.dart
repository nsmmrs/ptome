/// Graphics that are drawn into a rectangle: raster images and SVG
/// images alike.
library;

import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/geometry.dart';

/// Something with an intrinsic size that is drawn into a rectangle.
abstract interface class Graphic {
  /// The natural width, in points.
  double get intrinsicWidth;

  /// The natural height, in points.
  double get intrinsicHeight;

  /// Draws the graphic into [rect].
  void paint(Canvas canvas, Rect rect);
}

/// A piece of something drawn as one with the pieces of it beside it on a
/// line, which the line may break between: the parts of a cutting note
/// set in two lines within the line (warichu, JLREQ 3.4), each part on a
/// line balanced across the room its pieces there take.
abstract interface class SplitGraphic implements Graphic {
  /// What the pieces have in common: the pieces of one [group] next to
  /// one another on a line are drawn as one.
  Object get group;

  /// Draws [pieces], this graphic's group's beside one another on a line
  /// (this one first), into their rectangles.
  void paintPieces(Canvas canvas, List<(SplitGraphic, Rect)> pieces);
}
