# resvg's reference-render cases

The SVG files of resvg's reference-render tests
(https://github.com/linebender/resvg, `crates/resvg/tests/tests`, at commit
77b12f4951a7b75d759c42e8c9497cff7c839c3c) that plain_pdf draws as resvg
does, under resvg's licence (MIT or Apache-2.0: LICENSE-MIT,
LICENSE-APACHE). `cases.txt` lists each with the size and SHA-256 of
resvg's PNG of it; the PNGs aren't committed, so test/resvg_test.dart's
comparisons are recorded (test/oracles/resvg.json.gz).

The whole suite, to find cases that have come to be drawn alike:
`tool/fetch_resvg_tests.sh`, then `dart run tool/resvg_suite.dart`, which
lists them; copy a new one here (and its line into `cases.txt`) and record
the comparisons again (`ORACLES=record dart test test/resvg_test.dart`).
