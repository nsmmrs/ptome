# Contributing

The bar for every change is unchanged output: Ptome must convert
documents exactly as the Asciidoctor gem built from the vendored upstream
commit (`main` at `30fb8cd5`, `packages/ptome/tool/vendor.sh`) does (ADR-0001, ADR-0017),
unless the difference is deliberate and listed in `benchmark/PARITY.md`
(a fixed upstream bug, with its test in `test/upstream_fixes/`; diagnostics, which
read like a Dart tool's).

## Layout

The repository is a pub workspace ([ADR-0018](adr/0018-ptome-and-the-plain-workspace.md)):
ptome is `packages/ptome`, and the libraries it is built on are
`packages/plain_*`, each published on its own; `packages/ptome_corpus_tools`
makes the test corpus's goldens and is not published. `dart pub get` anywhere
resolves the whole workspace. Paths and commands below are relative to a
package's folder, `packages/ptome` unless they say otherwise.
[RELEASING.md](RELEASING.md) says how each package is released.

## Setup

- Dart SDK 3.13 or later
- For the parity gates: Ruby with the gem built from upstream `main` at
  `30fb8cd5` (`gem build asciidoctor.gemspec` in a checkout of that commit,
  as CI does) and the asciimath gem, no other optional gems, and
  [bats](https://github.com/bats-core/bats-core)
- For the npm package: Node.js 20.19 or later (and Chromium for the browser
  test)

```sh
dart pub get
```

## Checks

From the repository root, the gate, one for every commit and every push:

```sh
tool/gate.sh   # about a minute here: format, analyze, every package's
               # whole suite, the public APIs, the JavaScript projection
```

The `justfile` runs it in a capped scope (12 GB, no swap) and commits and
pushes through it: `just commit MESSAGE_FILE` (the gate, then a commit of
every change), `just amend`, `just push` (a push to master, the gate run
again only if the commit isn't the tree it last passed, then CI's run
watched to its end); `just gate` alone. A gate that isn't green stops the
commit or the push, and says which files failed formatting or analysis.

CI (`.github/workflows/ci.yml`) runs only on a push to master, and runs
every test and check there: the same as the gate, the tests dealt into
shards of about the same time (`tool/shard.dart`, by `tool/test_times.txt`)
on Linux, macOS and Windows, ptome's suites on Node.js (four programs,
`tool/node_tests.dart`), each library compiled to JavaScript against the
VM, the npm package, the CLI's bats suite and the packages' publishing and
standalone resolution. Each test job holds its files to the time budget
(`tool/test_budget.txt`).

The gate and CI's shards run the test files a few to a program
(`tool/test_shard.sh`, `tool/shard.dart --programs`): a program loads once
for all its files, where `dart test` alone starts, and compiles, each
file. Each file is a group named for its path, and starts from the
package's test world (`test/support/world.dart`, where a package has
settings a file may change for the whole process: ptome's fonts, logger
and parallel nesting). So a test file changes such a setting in a `setUp`
or `setUpAll`, never while declaring its tests (the program fails to load
naming it), and keeps per-file state to itself. `dart test` alone, or on
one file, runs the same tests.

The tests run the same everywhere: in one world (`PTOME_SYSTEM_FONTS=off`,
a fixed `SOURCE_DATE_EPOCH`, `TZ=UTC`, `PTOME_FONT_PATH` unset; the gate
and CI set it, `test/hermetic_test.dart` checks it), no test looking for a
tool, a font or a file of the machine (`tool/hermetic_check.sh`). What an
outside tool (HarfBuzz, ICU, Poppler, veraPDF, a browser...) answers is
recorded with the inputs it answered for (`test/support/oracles.dart`, the
answers in each package's `test/oracles`); `ORACLES=record dart test`
asks the tools again, installed. Random checks run from fixed seeds; each
package's `tool/deep_checks.dart` runs many times their cases, by hand.
A test that fails now and then is a bug, fixed at its cause, never
retried: `tool/flake_hunt.sh [RUNS]` runs every package's tests that many
times, each in an order of its own. The rules are
[ADR-0025](adr/0025-every-test-on-every-push.md)'s.
The checks against Asciidoctor itself (the gem's CLI, the differential
harness, EPUB parity with asciidoctor-epub3, the goldens made again) are
`packages/ptome/tool/ruby_oracles.sh`, also by hand.

The corpus (`test/corpus`, `dart test -t corpus`) checks ptome against the
files the Asciidoctor command line writes for about 1,700 documents. It is
red until compatibility settings close every difference, so the gate holds
it to the cases known red (`test/corpus/red.txt`): a case that newly fails
fails the gate, and one that passes is to be taken off the list
(`dart run tool/corpus_red.dart REPORT.json --update` takes off the cases
a run's JSON report shows passing; `--add` also lists its new failures, for
a case new to the corpus). ptome's fixes of upstream bugs are tested in
`test/upstream_fixes/`.

Tests are judged by the input they feed and the output they check; no gate
measures coverage.

The command line, on a built executable:

```sh
./tool/build-exes.sh
ASCIIDOCTOR_EXE="$PWD/dist/ptome-linux-x64" bats test/e2e/
```

`ASCIIDOCTOR_EXE=test/e2e/bin/asciidoctor-ruby bats test/e2e/` runs the
same suite against the gem; both must pass.

The tests and tools set PDFs and EPUBs in the fonts vendored with
asciidoctor-pdf and asciidoctor-epub3 (`tool/vendored_fonts.dart`), so
their output doesn't depend on the fonts installed. To run the executable
on the same fonts by hand, put their folders in `PTOME_FONT_PATH`:

```sh
export PTOME_FONT_PATH=$PWD/vendor/asciidoctor-pdf/data/fonts:$PWD/vendor/asciidoctor-pdf/icons:$PWD/data/pdf-fonts:$PWD/vendor/asciidoctor-epub3/fonts
```

## Corpus check

A wider comparison with the gem over thousands of real documents (stdout,
warnings and exit codes, four modes each); see `benchmark/PARITY.md`:

```sh
tool/corpus/fetch.sh /tmp/corpus
dart run tool/corpus_parity.dart --exe-a asciidoctor \
  --exe-b dist/ptome-linux-x64 --out /tmp/corpus-results /tmp/corpus
```

Use a gem install without optional gems as `--exe-a`, and run Ptome
with `-a highlightjs-mode=client` (see `benchmark/PARITY.md`). Every
difference it finds deserves a case in the corpus (`test/corpus`).

## The npm package

```sh
./tool/build-npm.sh          # build/npm; never publishes
cd test/npm && npm ci
node --test                  # API, exports, contents, bundler, browser
npm run types                # tsc over typical usage
npm run lint                 # publint and are-the-types-wrong
cd ../.. && dart run tool/node_tests.dart && dart test -p node build/node_tests
ASCIIDOCTOR_EXE=test/e2e/bin/ptome-node bats test/e2e/
```

The browser test looks for Chromium at `/usr/bin/chromium`; set
`CHROMIUM_PATH` to use another build.

The magazine looks' screenshots (`test/look/magazine_shots_test.dart`)
are recorded comparisons: taking them again (`ORACLES=record`) needs
Chromium, Firefox (`FIREFOX_PATH`, else `/usr/bin/firefox` or
`~/.cache/asciidart-work/firefox/firefox`), ImageMagick and the looks'
faces (`ptome doctor --look magazine-1960s` and so on).

## Layout

- `lib/ptome.dart`, `io.dart`, `cli.dart`: the public libraries
  (`export ... show` lists only), backed by `lib/src/api/`, a typed layer
  over the implementation. The supported API is described in
  `doc/api.md`; a change to it updates `tool/api_surface.txt`
  (`dart run tool/api_check.dart --update`) and `test/api/`, which uses
  only the public libraries.
- `lib/src/`: the implementation (still mostly one Dart file per
  Asciidoctor source file, `parser.dart` for `parser.rb`, ...), plus the CLI
  in `lib/src/cli/`.
- `lib/src/io.dart`: the only access to files, processes and the network
  (VM and JavaScript implementations; `test/platform_seam_test.dart`).
- `lib/src/js/` and `npm/`: the JavaScript bridge and the npm package
  (ADR-0005).
- `tool/`: build scripts and the differential harness.
- `test/e2e/`: the bats suite shared with the gem; `test/corpus/`: the
  black-box corpus ([ADR-0022](adr/0022-the-corpus-is-the-gate.md)).
- `adr/`: decisions.

## Embedded data

Files taken from Asciidoctor (its stylesheets, locales, syntax reference and
test fixtures) live under `vendor/asciidoctor/`, unchanged and pinned to an
upstream revision; see `vendor/README.md`. `tool/vendor.sh` recreates them
(`--check` verifies them). Documents of our own go in the corpus.

`lib/src/data.g.dart` embeds the vendored locales and stylesheets so the
package never reads them at run time, and `lib/src/cli/help_topics.g.dart`
embeds the man page and syntax reference for `-h`. Both are generated;
`tool/vendor.sh` regenerates them. The man page is written in
`man/ptome.adoc`; after changing it, rebuild `man/ptome.1` (with
Ptome itself) and the embedded copy:

```sh
tool/build-man.sh
dart test test/cli/help_topics_test.dart
```

## Pull requests

Keep each change focused, with a test. For a behavior change, show that the
gem agrees: a corpus case (its goldens are the gem's files), or an e2e
test, makes it permanent; a fix of a bug the gem has goes in
`test/upstream_fixes/`.
