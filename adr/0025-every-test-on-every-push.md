# ADR-0025: Every Test on Every Push; Slim, Hermetic Tests

**Status:** Accepted on 2026-10-15. Supersedes
[ADR-0022](0022-the-corpus-is-the-gate.md) decision 7. From
EPIC-0mhqkk.

## Context

The gate had two tiers and a nightly run (ADR-0022 decision 7): a fast
tier on every commit, a full tier before a push that ran every test under
coverage and held ptome to a coverage floor, the slow tests on macOS and
Windows and the libraries' `nightly` tests once a night. A push took over
twenty minutes. Tests asked outside tools (HarfBuzz, ICU, Poppler, qpdf,
veraPDF, EPUBCheck, a browser...) and skipped without them; some read the
machine's fonts, date and time zone; some converted whole books (the
Qur'an's 604 pages, 26 whole units documents); some ran random cases from
a new seed each time; some failed now and then.

The user's rules (2026-10-14 and 15): CI runs every test we have, and
only when something is merged into master; the tests are slim, fast and
reliable, "no flakiness AT ALL", small documents that exercise the
features rather than 400-page books; coverage doesn't matter, only input
and output; the tests run the same in every environment, with no
branching test config.

## Decision

1. **CI runs on a push to master, and only then** (`.github/workflows/
   ci.yml`): no pull requests, no schedule, no other branch. It runs
   every check and every test of every package each time: Linux, macOS
   and Windows, ptome's suites on Node.js, the npm package, the CLI's bats
   suite on the compiled executable, each library compiled to JavaScript
   against the VM, publishing and standalone resolution. The release
   check and the publish workflows stay as they are.
2. **One gate** (`tool/gate.sh`, through `just commit` and `just push`):
   formatting, the workspace's analysis, the oracle and hermetic checks,
   every package's whole suite (`tool/test_shard.sh`, as one of CI's
   shards runs its part), the API and JavaScript snapshots. `just push`
   doesn't run it again for a tree it passed, then watches CI's run.
3. **One world for the tests**: `PTOME_SYSTEM_FONTS=off` (only the fonts
   a test names, never the machine's), a fixed `SOURCE_DATE_EPOCH`,
   `TZ=UTC`, `PTOME_FONT_PATH` unset; the gate and CI set it,
   `test/hermetic_test.dart` checks it. Nothing branches on the
   environment or the system at run time: a test of one system's
   behavior states the system in its name and runs there (`testOn`). A
   test that needs another environment or time zone runs the code in a
   zone that gives it (`io.withWorld`), not in a process of its own.
4. **No test asks an outside tool.** What a tool answered is recorded
   with the inputs it answered for (each package's `test/oracles`,
   `test/support/oracles.dart`); `ORACLES=record` asks again, with the
   tool installed. No test spawns a process: the CLI's tests run its
   entry function, the compiled executable is the bats suite's.
5. **Small documents, never books.** Each feature by the smallest
   document that shows it; whole works only in hand-run tools
   (`tool/showcase.dart`, `tool/mushaf.dart --check`, the units corpus's
   whole documents, the throughput benchmarks).
6. **Nothing random varies between runs**: property, scan and fuzz checks
   from fixed seeds (a hash of the text, the same on every platform) and
   bounded counts. Each package's `tool/deep_checks.dart` runs many times
   the cases by hand; what it finds becomes a committed case.
7. **Zero flakes.** A test that fails now and then is a bug, fixed at its
   cause, never retried or skipped. `tool/flake_hunt.sh` runs the whole
   workspace many times, each in an order of its own.
8. **A time budget** (`tool/test_budget.dart`, `tool/test_budget.txt`):
   any one test, test file and package run in a CI shard, at about twice
   the worst the runners have shown, so a slow runner passes and a test
   grown several times slower fails.
9. **Coverage never gates.** No coverage run, floor or check.
10. **Test files run a few to a program** (`tool/shard.dart --programs`):
    a program loads and warms up once for its files, where `dart test`
    starts an isolate for each. Each file is a group named for its path
    and starts from its package's test world (ptome's
    `test/support/world.dart`: fonts, logger, parallel nesting); a file
    that changes it while declaring its tests fails the program's load.

## Consequences

- The gate takes about a minute here (55 s, the suites the long part),
  where the two tiers took over twenty.
- CI runs about twice as long as the gate: green in 98 to 115 s, every
  job under its two or three minutes. It doesn't reach a minute. Every
  suite runs on three systems and on Node.js, the account runs twenty
  jobs at once, and a Windows job spends 45 to 60 s before its first test
  (the checkout, the SDK, the pub cache: its tar is slow). A minute would
  take running the platform-sensitive suites only on macOS and Windows,
  or larger runners.
- Node.js's test runs waited ~40 ms a test on package:test's socket
  (Nagle's algorithm): `packages/ptome/tool/node_no_delay.cjs`, from
  `dart_test.yaml`, sets the socket's `noDelay`.
- Port-era placeholder tests are gone: upstream's tests with no
  counterpart in ptome are listed in `benchmark/PARITY.md`.
- The corpus's cases where Asciidoctor's own output has a defect ptome
  doesn't reproduce stay listed skips (ADR-0022): they are the corpus's,
  not a test missing.
