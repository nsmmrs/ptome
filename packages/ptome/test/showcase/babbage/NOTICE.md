---
title: "Table of Logarithms of the Natural Numbers from 10,000 to 19,999"
source: babbage.adoc
looks: [babbage]
compare:
  - page: 3
    scan: https://archive.org/download/tablelogarithms00babbgoog/page/n30.jpg
    note: "The table's first page: rows in fives, columns ruled apart (Babbage's table, 1831 printing)"
---

# Table of Logarithms of the Natural Numbers from 10,000 to 19,999

A table of seven-place logarithms in a look after Charles Babbage's
_Table of Logarithms of the Natural Numbers, from 1 to 108000_ (1827).
What the work shows: a large numeric table (1,000 rows, 33 pages) — its
rows in fives with a space between them (`table_row_group_size`,
FEAT-kskwtx), figures of one width in centred columns ruled apart, the
heads of the columns repeated at the top of every page, the first and
last numbers a page holds in its head (the rows' anchors as running
marks), and a tinted page.

## Sources

The values are computed, not copied: `tool/showcase_babbage.dart` writes
`text/table.adoc` (and the excerpt's `text/excerpt-table.adoc`), the
logarithms of the numbers from 10,000 to 19,999 to seven places
(`log(n) / ln 10`, rounded), laid out as Babbage lays his out. The
advertisement is written for the work. Nothing is copied from a
source, so there is no source file and no SHA-256; the scan below is
what the look follows, not a source of the text.

## Licence

The work's own (MIT, as the repository). The table it follows is in the
public domain (published 1827).

## Fonts

Old Standard TT (SIL Open Font License 1.1), its figures set tabular,
from Google Fonts: `ptome doctor --look babbage --looksdir
test/showcase/babbage` installs it. Not committed.

## The printing the look follows

Table of the Logarithms of the Natural Numbers, from 1 to 108000, by
Charles Babbage, London: B. Fellowes, 1831 (stereotyped from the 1827
edition): https://archive.org/details/tablelogarithms00babbgoog

## Where it departs from it

- The range: 10,000 to 19,999, not 1 to 108,000.
- Babbage's page has columns of the arcs whose sines and tangents the
  logarithms are, and of proportional parts; here only the numbers, the
  logarithms and the differences.
- Babbage sets the logarithm's first three figures once, where they
  change, in a column of their own; here the first column of each row
  holds them.
- The head gives the numbers the page holds, where Babbage's gives the
  logarithm's first figures and the number ("Log. 000. N. 100.").
- His face is a heavy modern; here Old Standard TT.

## In HTML and EPUB

- In HTML and EPUB the table is one table: its rows in fives (the
  look's CSS spaces each fifth) and its figures in lining, tabular
  numerals, but its heads once at the top and no page range over each
  page (a web page or an EPUB has no pages of its own); the tint is the
  HTML page's background, not the EPUB's.
