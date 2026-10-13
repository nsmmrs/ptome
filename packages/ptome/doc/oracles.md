# Oracle comparisons

What the free paged-media engines make of the things a book asks for,
next to Ptome's (TASK-s6bbsz). `tool/oracle_compare.dart` sets one
fixture in each engine: the same three chapters, footnotes, a table of
contents and a two-column ending, on an A5 page with 20 mm margins and
10 on 13 text. It then reads the PDFs back with poppler:

```sh
dart run tool/oracle_compare.dart --ptome <ptome> --typst <typst> --keep <dir>
```

An engine that isn't installed is left out. WeasyPrint is the best free
CSS Paged Media oracle (it passes every print-css-rocks feature tested).
Paged.js drops leaders and miscounts `target-counter`, so it isn't used.

## Results (2026-10-12)

Ptome at f4f40555; WeasyPrint 70.0; Typst main (d7dfb34a, 0.15.1, the
same as the 0.15.1 release); ConTeXt LMTX 2026.09.10.

| Engine | Leaders: numbers aligned (spread), dots | Running heads: the chapter | Heads on chapter openers | Footnotes on their page | Columns balanced (lines apart) |
| --- | --- | --- | --- | --- | --- |
| Ptome | 0.00 pt, dots | 3 of 3 pages | 0 of 3 | 5 of 5 | 2.4 |
| WeasyPrint | 0.00 pt, dots | 3 of 3 pages | 3 of 3 | 5 of 5 | 0.6 |
| Typst | 0.00 pt, dots | 3 of 3 pages | 3 of 3 | 5 of 5 | one column |
| ConTeXt | 0.00 pt, dots | 3 of 3 pages | 0 of 3 | 5 of 5 | 0.9 |

- **Leaders.** All four line up the contents' page numbers at the right
  and lead to them with dots. Ptome's `toc_dot_leader_*`, CSS's
  `leader('.') target-counter()`, Typst's `outline` fill and ConTeXt's
  list alternative `c` agree.
- **Running heads.** Every continuation page carries its chapter's
  title in all four: Ptome's `{chapter-title}`, GCPM's
  `string-set`/`string()`, a Typst `query` and ConTeXt's
  `\setupheadertexts[chapter]`. On a chapter's opening page Ptome drops
  the head by default (`running_content_on_openers`, the book
  convention), and so does ConTeXt as configured here (`header=empty`).
  WeasyPrint shows it, as CSS does unless `@page :first`-style rules
  say otherwise, and so does Typst as configured here.
- **Footnotes.** Every note is at the foot of its reference's page in
  all four. CSS's `float: footnote` in WeasyPrint is the closest to
  Ptome's. Ptome numbers notes from 1 in each chapter, as
  asciidoctor-pdf does; the others number them through the book.
- **Column balancing.** WeasyPrint (`column-fill: balance`) and ConTeXt
  (`balance=yes`) end the two columns within a line of each other.
  Typst's `columns` doesn't balance: the first column fills, and the
  last two lines go on to a page of their own. Ptome's two columns end
  two lines apart. The four paragraphs keep their widows and orphans (two
  lines), and the only splits that do are 10 and 8 lines, or 8 and 10
  with the second column the longer, which Ptome never makes. How
  WeasyPrint and ConTeXt get closer (other split rules, or space between
  paragraphs that gives) wasn't examined.

The comparison found no defect in Ptome. Its differences are
deliberate: no heads on chapter openers, footnotes numbered by chapter,
and balance within the widow and orphan rules.
