/// The state of the substitutions applied to a text, held by a run from
/// the call of `applySubs` (or the tracking of its inline elements) to its
/// return: the passthroughs stashed for the node, and whether an outer
/// call on it holds them; the mask of the characters its texts hold; and
/// the inline elements' tracking. Runs nest as the calls do (a macro's
/// text substituted within a paragraph's), the innermost
/// `SubstitutionRun.current`.
library;

import 'package:ptome/src/abstract_node.dart' show AbstractNode;
import 'package:ptome/src/inline_tree.dart' show InlineRun;
import 'package:ptome/src/presence.dart';
import 'package:ptome/src/substitutors.dart' show Passthrough;

/// The passthroughs stashed for a node while substitutions run on it, and
/// whether the outermost call on it, which clears them, holds them.
final class PassthroughStash {
  /// The passthroughs, in the order their placeholders number them.
  final List<Passthrough> passthroughs = [];

  /// Whether an outer call on the node holds the stash (only it clears
  /// it: placeholders can move around).
  bool locked = false;
}

/// A run of substitutions: on [node] (none for one that only tracks inline
/// elements), within the run it was started in.
final class SubstitutionRun {
  new _(this.node, this._outer) : inline = _outer?.inline;

  static SubstitutionRun? _current;

  /// The innermost run under way, if any.
  static SubstitutionRun? get current => _current;

  /// The node the substitutions run on.
  final AbstractNode? node;

  final SubstitutionRun? _outer;

  /// The run this one is within, if any.
  SubstitutionRun? get outer => _outer;

  /// The inline elements' tracking under way, inherited from the run
  /// around (see [InlineRun.track]).
  InlineRun? inline;

  /// The characters of the texts the run asks about.
  final Mask mask = Mask();

  PassthroughStash? _stash;

  /// The passthroughs stashed for [node]: the nearest run's around this
  /// one on the same node, else this one's own.
  PassthroughStash get stash {
    if (_stash case final stash?) return stash;
    for (var run = _outer; run != null; run = run._outer) {
      if (identical(run.node, node)) {
        if (run._stash case final stash?) return _stash = stash;
      }
    }
    return _stash = PassthroughStash();
  }

  /// Runs [body] as a run on [node], within the run under way.
  static T run<T>(AbstractNode? node, T Function(SubstitutionRun run) body) {
    final outer = _current;
    final run = _current = SubstitutionRun._(node, outer);
    final outerMask = activeMask;
    activeMask = run.mask;
    try {
      return body(run);
    } finally {
      _current = outer;
      activeMask = outerMask;
    }
  }

  /// Runs [body] within the run under way, or a run of its own (on no
  /// node) where there is none.
  static T within<T>(T Function(SubstitutionRun run) body) =>
      switch (_current) {
        final run? => body(run),
        null => SubstitutionRun.run(null, body),
      };
}
