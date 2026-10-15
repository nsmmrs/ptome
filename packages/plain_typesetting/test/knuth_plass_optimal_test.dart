// The Knuth-Plass line breaker finds the least demerits there are: on
// small random paragraphs, justified or ragged, with no two hyphenated
// lines in a row or with font expansion, with lines of one width or
// narrow first lines (an indent, a drop), the demerits of its breaks are
// the least of every way to break them within its tolerance, found by
// trying them all.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

void main() => optimal();

/// The optimality tests over [scale] times their random paragraphs
/// (tool/deep_checks.dart runs many times as many).
void optimal({int scale = 1}) {
  test('the least demerits of every way to break the paragraph', () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
      ),
    );
    final run = TextRun('', TextStyle(font, 10));
    var checked = 0;
    for (var seed = 0; seed < 100 * scale; seed++) {
      final random = math.Random(seed);
      final items = <LineItem>[];
      for (var i = 0, n = 4 + random.nextInt(11); i < n; i++) {
        items.add(BoxItem(run, 'word', 8 + random.nextDouble() * 30));
        if (random.nextInt(5) == 0) {
          items
            ..add(BoxItem(run, 'ing', 5 + random.nextDouble() * 10))
            // (A hyphen of no width: a way to the breaks is given up once
            // a line from it is overfull, which a hyphen's width can make
            // it at one break and not at the next.)
            ..add(PenaltyItem(0, 50, flagged: true, run: run));
        }
        items.add(GlueItem(run, ' ', 3, 1.5, 1));
      }
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
      final width = 40 + random.nextDouble() * 80;
      final narrow = random.nextInt(4);
      final cut = 10 + random.nextDouble() * 30;
      double widths(int line) => line < narrow ? width - cut : width;
      final opportunities = [
        for (var i = 0; i < items.length - 1; i++)
          if (switch (items[i]) {
            GlueItem() => i > 0 && items[i - 1] is BoxItem,
            PenaltyItem(:final penalty) => penalty < PenaltyItem.never,
            BoxItem() => false,
          })
            i,
      ];
      for (final breaker in const [
        KnuthPlassLineBreaker(),
        KnuthPlassLineBreaker(raggedStretch: 20),
        KnuthPlassLineBreaker(maxHyphenRun: 1),
        KnuthPlassLineBreaker(expansion: 0.02),
        KnuthPlassLineBreaker(lastLineMin: 0.4),
      ]) {
        var best = double.infinity;
        for (var mask = 0; mask < 1 << opportunities.length; mask++) {
          final breaks = [
            for (var b = 0; b < opportunities.length; b++)
              if (mask & (1 << b) != 0) opportunities[b],
            items.length - 1,
          ];
          best = math.min(best, breaker.demeritsOf(items, widths, breaks));
        }
        // (No way within the tolerance: the later passes, which the
        // demerits here don't count.)
        if (best.isInfinite) continue;
        checked++;
        final found = breaker.breakItems(items, widths);
        expect(
          breaker.demeritsOf(items, widths, found),
          closeTo(best, best * 1e-9),
          reason:
              'seed $seed, ragged ${breaker.raggedStretch}, '
              'run ${breaker.maxHyphenRun}, expansion ${breaker.expansion}, '
              'last line ${breaker.lastLineMin}',
        );
      }
    }
    expect(checked, greaterThan(60 * scale));
  });

  test('no more hyphenated lines in a row than the limit, the least else', () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
      ),
    );
    final run = TextRun('', TextStyle(font, 10));
    // Every word hyphenable, hyphens costing nothing more in a row: the
    // breaker without a limit sets runs of them, the one with sets none.
    const free = KnuthPlassLineBreaker(flaggedDemerits: 0);
    const limited = KnuthPlassLineBreaker(flaggedDemerits: 0, maxHyphenRun: 1);
    int longest(List<LineItem> items, List<int> breaks) {
      var most = 0;
      var run = 0;
      for (final at in breaks) {
        final item = items[at];
        run = item is PenaltyItem && item.flagged ? run + 1 : 0;
        most = math.max(most, run);
      }
      return most;
    }

    var runs = 0;
    for (var seed = 0; seed < 60 * scale; seed++) {
      final random = math.Random(seed);
      final items = <LineItem>[];
      for (var i = 0, n = 4 + random.nextInt(8); i < n; i++) {
        items
          ..add(BoxItem(run, 'word', 8 + random.nextDouble() * 20))
          ..add(PenaltyItem(0, 0, flagged: true, run: run))
          ..add(BoxItem(run, 'ing', 8 + random.nextDouble() * 20))
          ..add(GlueItem(run, ' ', 3, 1.5, 1));
      }
      items
        ..add(const GlueItem.fill())
        ..add(PenaltyItem(0, PenaltyItem.forced, run: run));
      final width = 30 + random.nextDouble() * 40;
      double widths(int line) => width;
      if (longest(items, free.breakItems(items, widths)) > 1) runs++;
      final found = limited.breakItems(items, widths);
      final demerits = limited.demeritsOf(items, widths, found);
      if (demerits.isInfinite) continue;
      expect(longest(items, found), lessThanOrEqualTo(1), reason: 'seed $seed');
      final opportunities = [
        for (var i = 0; i < items.length - 1; i++)
          if (switch (items[i]) {
            GlueItem() => i > 0 && items[i - 1] is BoxItem,
            PenaltyItem(:final penalty) => penalty < PenaltyItem.never,
            BoxItem() => false,
          })
            i,
      ];
      var best = double.infinity;
      for (var mask = 0; mask < 1 << opportunities.length; mask++) {
        best = math.min(
          best,
          limited.demeritsOf(items, widths, [
            for (var b = 0; b < opportunities.length; b++)
              if (mask & (1 << b) != 0) opportunities[b],
            items.length - 1,
          ]),
        );
      }
      expect(demerits, closeTo(best, best * 1e-9), reason: 'seed $seed');
    }
    expect(runs, greaterThan(20));
  });

  test('protrusion counted: a line whose end hangs fits the wider measure', () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
      ),
    );
    final run = TextRun('', TextStyle(font, 10));
    // 30 + 5 + 20 = 55 wide, 1 of shrink: too wide for 50, unless the
    // last box's period hangs 6 into the margin.
    final items = <LineItem>[
      BoxItem(run, 'aaaa', 30),
      GlueItem(run, ' ', 5, 1, 1),
      BoxItem(run, 'bb.', 20),
      GlueItem(run, ' ', 5, 1, 1),
      BoxItem(run, 'cc', 30),
      const GlueItem.fill(),
      PenaltyItem(0, PenaltyItem.forced, run: run),
    ];
    const breaker = KnuthPlassLineBreaker();
    expect(breaker.breakItems(items, (_) => 50).first, 1);
    expect(
      breaker
          .breakItems(
            items,
            (_) => 50,
            protrudeRight: (i) =>
                (items[i] as BoxItem).text.endsWith('.') ? 6 : 0,
          )
          .first,
      3,
    );
  });

  test('a runt costs more: the last line not short of the least', () {
    final font = OpenTypeShaper(
      OpenTypeFont.parse(
        File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
      ),
    );
    final style = TextStyle(font, 10);
    final paragraph = Paragraph([
      TextRun(
        'The quick brown fox jumps over the lazy dog and runs off into '
        'the woods beyond the hill near the farm, far away from home today',
        style,
      ),
    ], align: TextAlign.justify);
    double lastWidth(KnuthPlassLineBreaker breaker, double width) =>
        breaker.breakLines(paragraph, (_) => width).last.width;
    // Across measures, the ones that leave a runt (a last line under 40%
    // of the measure) leave fewer with a least of 40%.
    var runts = 0;
    var mended = 0;
    for (var width = 100.0; width <= 260; width += 4) {
      if (lastWidth(const KnuthPlassLineBreaker(emergencyStretch: 20), width) >=
          0.4 * width) {
        continue;
      }
      runts++;
      final kept = lastWidth(
        const KnuthPlassLineBreaker(emergencyStretch: 20, lastLineMin: 0.4),
        width,
      );
      if (kept >= 0.4 * width) mended++;
    }
    expect(runts, greaterThan(0));
    expect(mended, greaterThan(0));
  });
}
