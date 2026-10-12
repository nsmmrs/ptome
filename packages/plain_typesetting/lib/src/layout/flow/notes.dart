part of '../flow.dart';

// Notes at the bottom of a region, and side notes beside the text.

/// A stream's notes at the bottom of a region: `before`, what was left
/// of some on the region before, set as it is, then `notes`, whole.
typedef _StreamNotes = ({List<LayoutBox> before, List<LayoutBox> notes});

/// The notes that didn't fit at the bottom of a region: the main series'
/// (with the floating boxes there), and each stream's.
typedef _WaitingNotes = ({
  List<LayoutBox> main,
  Map<String, _StreamNotes> streams,
});

/// A stream's group of notes at the bottom of a region: its `stream` and
/// its `notes`.
typedef _Group = ({String stream, _StreamNotes notes});

/// What is left of the notes at the bottom of a region, [area] placed
/// and [rest] left of it: the main series' and the floating boxes'
/// (without the main [separator]), and each stream's (its group in
/// [groups]): a group left whole, its notes as they were (to be arranged
/// again with the next region's), else what is left of its boxes but the
/// stream's separator, of [streamSeparators].
_WaitingNotes? _left(
  LayoutBox? rest,
  List<LayoutBox> area,
  Map<LayoutBox, _Group> groups, {
  required LayoutBox? separator,
  required Map<String, LayoutBox?> streamSeparators,
}) {
  if (rest == null) return null;
  final children = rest is BlockBox ? rest.children : [rest];
  final main = <LayoutBox>[];
  final streams = <String, _StreamNotes>{};
  // (The rest is what was left of the box the region ended in, then the
  // boxes after it as they were.)
  final whole = Set<LayoutBox>.identity()..addAll(area);
  for (final (i, child) in children.indexed) {
    final LayoutBox owner;
    if (whole.contains(child)) {
      owner = child;
    } else {
      final next = children.skip(i + 1).where(whole.contains).firstOrNull;
      final at = next == null ? area.length : area.indexOf(next);
      owner = area[at - 1];
    }
    switch (groups[owner]) {
      case (:final stream, :final notes) when identical(child, owner):
        streams[stream] = notes;
      case (:final stream, notes: _):
        final own = streamSeparators[stream];
        final before = <LayoutBox>[];
        for (final box in (child as BlockBox).children) {
          switch (box) {
            case _ when identical(box, own):
              break;
            case ColumnsBox(:final children):
              before.addAll(children);
            case _:
              before.add(box);
          }
        }
        streams[stream] = (before: before, notes: const []);
      case null when identical(child, separator):
        break;
      case null:
        main.add(child);
    }
  }
  return (main: main, streams: streams);
}

extension _Notes on _Pass {
  /// Sets the side notes beside their anchors on every page (see
  /// [FlowLayout.sideNotes]), the pages' text as it is: the main series
  /// in the side column, each of [FlowLayout.sideNoteStreams] in its own.
  void _placeSideNotes() {
    unsetSideNotes.clear();
    for (final page in pages) {
      page.side.clear();
    }
    final streamOf = layout.sideNoteStreamOf;
    _placeSideStream({
      for (final MapEntry(:key, :value) in layout.sideNotes.entries)
        if (!streamOf.containsKey(key)) key: value,
    }, layout.sideColumn);
    for (final stream in layout.sideNoteStreams) {
      _placeSideStream({
        for (final MapEntry(:key, :value) in layout.sideNotes.entries)
          if (streamOf[key] == stream.name) key: value,
      }, stream.column);
    }
  }

  /// Sets [notes] beside their anchors in [column] on every page.
  void _placeSideStream(
    Map<String, LayoutBox> notes,
    Rect? Function(int number, PageTemplate template)? column,
  ) {
    if (notes.isEmpty || column == null) return;
    // Each page's notes, in reading order (the left column's, then the
    // right's, as a reference Bible's center column has them).
    final byPage = <int, List<(String, double)>>{};
    for (final MapEntry(:key, :value) in anchors.entries) {
      if (notes.containsKey(key)) {
        (byPage[value.page] ??= []).add((key, value.y));
      }
    }
    // The notes waiting for room, with their names.
    var carried = <(String, LayoutBox)>[];
    for (var i = 0; i < pages.length || carried.isNotEmpty; i++) {
      // Notes still waiting when the text has ended go on pages of their
      // own, with only their margin (as long as a page takes one).
      final added = i == pages.length;
      if (added) pages.add(_newPage(null));
      final page = pages[i];
      final full = column(i + 1, page.template);
      if (full == null) {
        if (added) break;
        continue;
      }
      // (Above the page's notes.)
      final area = switch (page.notesTop) {
        final top? when top + layout.sideNoteGap > full.bottom =>
          Rect.fromEdges(
            full.left,
            top + layout.sideNoteGap,
            full.right,
            full.top,
          ),
        _ => full,
      };
      final here = byPage[i] ?? const <(String, double)>[];
      final entries = [
        for (final (name, box) in carried) (name, box, area.top),
        for (final (name, y) in here) (name, notes[name]!, y),
      ];
      carried = [];
      var cursor = area.top;
      for (final (name, box, y) in entries) {
        // After one that didn't fit, the rest wait too, in order.
        if (carried.isNotEmpty) {
          carried.add((name, box));
          continue;
        }
        final top = math.min(y, cursor);
        final room = top - area.bottom;
        // A note goes on whole to the next page (but one taller than the
        // whole column, which is split).
        final whole = _measure(box, area.width);
        if (room <= 0 ||
            (whole > room + 1e-6 && whole <= area.height + 1e-6) ||
            _minHeight(box, area.width) > room + 1e-6) {
          carried.add((name, box));
          continue;
        }
        final fit = _place(box, area.width, room, atTop: true);
        if (fit.placed == null) {
          carried.add((name, box));
          continue;
        }
        page.side.add((
          Rect(area.left, top - fit.height, area.width, fit.height),
          fit.placed,
        ));
        cursor = top - fit.height - layout.sideNoteGap;
        if (fit.rest case final rest?) carried.add((name, rest));
      }
      // A page of its own that takes none of them: they never will.
      if (added && page.side.isEmpty) {
        pages.removeLast();
        break;
      }
    }
    unsetSideNotes.addAll([for (final (name, _) in carried) name]);
  }

  /// [first] (the placing of [content] in [region]) with room made for the
  /// notes its anchors refer to, and the notes placed at the bottom: the
  /// content placed again in less height until its notes fit below it.
  /// Notes that don't fit are deferred to the next region.
  (_Fit, _Fit?) _notes(
    LayoutBox content,
    Rect region,
    _Fit first, {
    List<LayoutBox> bottom = const [],
  }) {
    final width = region.width;
    var fit = first;
    final deferred = _deferredNotes;
    // The notes of the anchors placed: the main series' (after those
    // deferred from the region before), then each stream's in turn, under
    // its separator, in its columns.
    final groups = Map<LayoutBox, _Group>.identity();
    final separators = {
      for (final stream in layout.noteStreams) stream.name: stream.separator,
    };
    List<LayoutBox> pending(_Fit fit) {
      final main = [...?deferred?.main];
      final carried = deferred?.streams ?? const {};
      final streams = <String, List<LayoutBox>>{
        for (final MapEntry(:key, :value) in carried.entries)
          key: [...value.notes],
      };
      for (final name in _Pass._anchorsOf(fit.placed)) {
        if (_notesSet.contains(name)) continue;
        final note = layout.notes[name];
        if (note == null) continue;
        switch (layout.noteStreamOf[name]) {
          case final stream?:
            (streams[stream] ??= []).add(note);
          case null:
            main.add(note);
        }
      }
      if (streams.isEmpty && carried.isEmpty) return main;
      final boxes = [...main];
      for (final stream in layout.noteStreams) {
        final before = carried[stream.name]?.before ?? const [];
        final notes = streams[stream.name] ?? const [];
        if (before.isEmpty && notes.isEmpty) continue;
        // (What was left of the stream's notes on the region before
        // first: in its columns with the new ones, or ahead of the new
        // ones run in.)
        final group = BlockBox([
          ?stream.separator,
          if (stream.runIn case final runIn?) ...[
            ...before,
            if (notes.isNotEmpty) runIn(notes),
          ] else if (stream.columns > 1)
            ColumnsBox(
              [...before, ...notes],
              count: stream.columns,
              gap: stream.columnGap,
              balance: true,
            )
          else ...[
            ...before,
            ...notes,
          ],
        ]);
        groups[group] = (
          stream: stream.name,
          notes: (before: before, notes: notes),
        );
        boxes.add(group);
      }
      return boxes;
    }

    // The bottom of the region: its floating boxes, then its notes under
    // the separator (the main series', when it has some).
    List<LayoutBox> area(List<LayoutBox> notes) => [
      ...bottom,
      if (notes.isNotEmpty && !groups.containsKey(notes.first))
        ?layout.noteSeparator,
      ...notes,
    ];
    var notes = pending(fit);
    double total(_Fit fit, List<LayoutBox> notes) =>
        fit.height + _measure(BlockBox(area(notes)), width);
    if ((notes.isNotEmpty || bottom.isNotEmpty) &&
        total(fit, notes) > region.height + 1e-6) {
      // The most content whose notes fit under it: more room places more
      // content, which refers to more notes, so the room is found by
      // halving.
      var low = 0.0;
      var high = fit.height;
      (_Fit, List<LayoutBox>)? best;
      for (var step = 0; step < 12; step++) {
        final room = (low + high) / 2;
        _floatsWaiting = 0;
        final tried = _placeRegion(content, width, room);
        final tryNotes = pending(tried);
        if (total(tried, tryNotes) <= region.height + 1e-6) {
          best = (tried, tryNotes);
          low = room;
        } else {
          high = room;
        }
      }
      // Notes taller than most of the region: as many as fit under what
      // is placed first, the rest on the next region.
      if (best case (final tried, final tryNotes)
          when tried.placed != null && tried.height >= region.height / 4) {
        fit = tried;
        notes = tryNotes;
      } else {
        _floatsWaiting = 0;
        fit = _placeRegion(content, width, region.height);
        notes = pending(fit);
      }
    }
    for (final name in _Pass._anchorsOf(fit.placed)) {
      if (layout.notes.containsKey(name)) _notesSet.add(name);
    }
    _deferredNotes = null;
    if (notes.isEmpty && bottom.isEmpty) return (fit, null);
    final room = region.height - fit.height;
    final placed = _place(BlockBox(area(notes)), width, room, atTop: false);
    if (placed.placed == null || placed.height == 0) {
      // No note fits: all of them on the next region, without a
      // separator; the floating boxes stay, as they were measured to.
      _deferredNotes = notes.isEmpty
          ? null
          : _left(
              BlockBox(notes),
              notes,
              groups,
              separator: layout.noteSeparator,
              streamSeparators: separators,
            );
      if (bottom.isEmpty) return (fit, null);
      return (
        fit,
        _place(BlockBox(bottom), width, double.infinity, atTop: false),
      );
    }
    _deferredNotes = _left(
      placed.rest,
      area(notes),
      groups,
      separator: layout.noteSeparator,
      streamSeparators: separators,
    );
    return (fit, placed);
  }
}
