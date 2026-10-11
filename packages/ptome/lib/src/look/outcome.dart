/// What an output's look compiler made of each item of a look (ADR-0023
/// decision 4): `ptome look explain` prints them, and a drop that isn't by
/// design is also the compiler's warning, so the two can't disagree.
library;

import 'package:ptome/src/look/model.dart';

/// What a compiler made of one item of a look.
sealed class LookOutcome {
  /// An outcome of [item].
  const new(this.item);

  /// The item, as the look's file names it: `tokens.color.link`,
  /// `styles.heading.font`, `css`.
  final String item;
}

/// [item] became [result]: a theme key and its value, a custom property,
/// or a declaration with its selector; in [medium] alone when the output
/// tells media apart (HTML's print rules).
final class Became extends LookOutcome {
  /// [item] became [result], in [medium] alone if given.
  const new(super.item, this.result, {this.medium});

  /// The theme key and value, or the CSS.
  final String result;

  /// The medium it applies in; null for every medium the output has.
  final Medium? medium;
}

/// [item] is left out of the output, [why]; [warned] when that is a
/// warning, not a choice of the output's design (an e-book's measure is
/// the reader's).
final class Dropped extends LookOutcome {
  /// [item] left out, [why].
  const new(super.item, this.why, {this.warned = true});

  /// Why, as a phrase after the item: `has no effect in the PDF`.
  final String why;

  /// Whether the compiler warns of it.
  final bool warned;
}
