---
title: "Babbage's Table of Logarithms"
source: babbage.adoc
looks: [babbage]
compare:
  - page: 1
    scan: https://archive.org/download/tablelogarithms00babbgoog/page/n30.jpg
    note: "Page 6, the first of five-figure numbers: Log. 000. N. 100., the rows 1000 to 1049 (1831)"
  - page: 2
    scan: https://archive.org/download/tablelogarithms00babbgoog/page/n31.jpg
    note: "Page 7: the arcs at the left reaching 3°, the differences two abreast at the right (1831)"
  - page: 16
    scan: https://archive.org/download/tablelogarithms00babbgoog/page/n45.jpg
    note: "Page 21: every difference with its proportional parts, in one column (1831)"
---

# Babbage's Table of Logarithms

Twenty pages of Charles Babbage's Table of the Logarithms of the Natural
Numbers, from 1 to 108000, the numbers 10,000 to 19,999, as its 1831
printing sets them, page for page and row for row (`tool/babbage_1831`).
What the work shows: a large numeric table, a thousand rows of ten
logarithms, its rows in fives with a space between them
(`table_row_group_size`), its figures of one width in columns as wide as
the printing's, ruled apart, the rules heavier where the printing's are
(each page's frame, `section_role_<role>_page_background_image`); the
logarithm's first three figures where they change, a figure put up by
rounding dotted under, the first figure of an entry past a change set
small; the arcs at the left; the differences and their proportional parts
in a column of their own, two abreast or one under another, running past
the foot of the table and on at the top of the next page; the head
giving the logarithm's and the number's first figures, the folio under
the arcs.

## Sources

The logarithms are computed, not copied: `tool/babbage_1831/gen.py`
writes `text/pages.adoc` (and each page's frame, `images/frame-N.svg`),
the logarithms of the numbers 10,000 to 19,999 to seven places
(`ln(n) / ln 10` to forty places, rounded), the marks, the arcs and the
heads by the printing's rules, and the differences' column from
`tool/babbage_1831/diff.spec`, its places read from the scan. Read
against the scan by Tesseract, row by row, the computed figures are the
printing's (`tool/babbage_1831/README.md`). Nothing is copied from a
source, so there is no source file and no SHA-256; the scans below are
what the work is set after.

## Licence

The work's own (MIT, as the repository). The table it follows is in the
public domain (published 1827).

## Fonts

Old Standard TT (SIL Open Font License 1.1), its bold, from Google
Fonts: `ptome doctor --look babbage --looksdir test/showcase/babbage`
installs it. Not committed.

## The printing the work follows

Table of the Logarithms of the Natural Numbers, from 1 to 108000, by
Charles Babbage, London: B. Fellowes, 1831 (stereotyped from the 1827
edition), the University of Oxford's copy, scanned by Google:
https://archive.org/details/tablelogarithms00babbgoog, its pages 6 to
25 (the Internet Archive's n30 to n49).

## Where it departs from it

- The range: the printing's pages 6 to 25, the numbers 10,000 to
  19,999, not 1 to 108,000.
- The face: Babbage's figures are a heavy modern whose 3, 4, 5, 7 and 9
  descend and whose 6 and 8 stand at full height; here Old Standard TT
  Bold's lining figures, at the size that gives the printing's widths
  (a little shorter than his).
- The places: each row within a point of the scan's, each figure's end
  within half a point; the differences and their parts within a point or
  two (`tool/babbage_1831/README.md`).

## In HTML and EPUB

- In HTML and EPUB each page is one table: its rows in fives (the
  look's CSS spaces each fifth) and its figures in lining, tabular
  numerals, but no rules, no frame and the differences' column as its
  last cells (a web page or an EPUB has no pages of its own).
