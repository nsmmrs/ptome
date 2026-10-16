---
title: "Alice’s Adventures in Wonderland and Through the Looking-Glass"
source: alice.adoc
looks: [alice]
compare:
  - page: 5
    scan: https://archive.org/download/alicesadventu00carr/page/n8.jpg
    note: "Wonderland's title page (Macmillan, 1867, the sixth thousand)"
  - page: 13
    scan: https://archive.org/download/alicesadventu00carr/page/n16.jpg
    note: "Chapter I: its cut above the heading, its first word's initial, its lines (Macmillan, 1867)"
  - page: 20
    scan: https://archive.org/download/alicesadventu00carr/page/n23.jpg
    note: "Page 8: a cut the text runs beside, line for line (Macmillan, 1867)"
  - page: 49
    scan: https://archive.org/download/alicesadventu00carr/page/n52.jpg
    note: "Page 37: the Mouse's Tale, each line where the printing sets it (Macmillan, 1867)"
  - page: 198
    scan: https://archive.org/download/alicesadventu00carr/page/n201.jpg
    note: "Page 186: the King, the text beside his throne and the table across the page (Macmillan, 1867)"
  - page: 207
    scan: https://archive.org/download/throughlookinggl01carr/page/n6.jpg
    note: "Looking-Glass: the chess problem and its moves in two columns (Macmillan, 1872)"
  - page: 231
    scan: https://archive.org/download/throughlookinggl01carr/page/n36.jpg
    note: "Jabberwocky's first stanza in mirror type (Macmillan, 1872)"
---

# Alice’s Adventures in Wonderland and Through the Looking-Glass

Lewis Carroll's two Alice books, with John Tenniel's illustrations.
Wonderland is set as Macmillan printed it in 1867 (the sixth thousand,
Richard Clay's setting of 1865), page for page and line for line: its
text transcribed from the University of Toronto's copy, each paragraph's
source lines the printing's (`:source-lines:`), every page starting and
ending with the printing's words, its lines broken and its words divided
where the printing breaks and divides them; each cut as wide, as tall
and where the printing sets it, beside the text or across the page or
above a chapter's heading; each chapter opening as far down its page;
the Mouse's Tale in type that shrinks down its tail, each line's size and
place from the scan; the verse in its stanzas' sizes; the running titles
divided across the spread; the printer's signatures at the feet of the
gatherings; the front matter (half-title, frontispiece, title page, the
prefatory poem, the contents) and the folios from chapter I. Looking-Glass
follows in the same look, its text Standard Ebooks', with Jabberwocky's
first stanza in mirror type (the `mirror` role, FEAT-yq6kff) and the chess
problem's moves in two columns. In the PDF, 192 of Wonderland's 192
pages agree with the printing's line for line (`tool/alice_1867/compare.py`).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| Wonderland's text: transcribed from the 1867 printing, the University of Toronto's copy (ABBYY's OCR of the Internet Archive's scans aligned with Standard Ebooks' text, each disagreement settled against the scan; `tool/alice_1867`) | https://archive.org/details/alicesadventu00carr: the scans `alicesadventu00carr_jp2.zip`, the OCR `alicesadventu00carr_hocr.html` | `adee3138fbf3f09a4a542f8e9fcedaa26aac7d7c898e0f1a50e810d78d3d1c81`, `c24ab8426c9d1390448bc8c6438064ad5cf38090ebb55a580fd8e853e03f08d1` |
| Alice's Adventures in Wonderland, Standard Ebooks (the text aligned with, its quotation marks, spellings and markup where the printing agrees) | https://github.com/standardebooks/lewis-carroll_alices-adventures-in-wonderland_john-tenniel at `9ecdf2ffa23098e7cb3c72157d7c3031b6f59903` (the `codeload.github.com` tarball) | `79a3cdf651270c94b739dd9ef5ef8f2a2778966d4e9afb40f91b8336cc24a50f` |
| Through the Looking-Glass, Standard Ebooks | https://github.com/standardebooks/lewis-carroll_through-the-looking-glass_john-tenniel at `56b8c2b2163e7eba0bed778b9c73aa8afbe572b1` | `323fbf4b4fc0a2d01bef6f772cc8adf195f9dd3ad5c44c1f20ab1cf9c9a701b1` |
| Tenniel's illustrations (SVG, traced by Standard Ebooks from the first editions' scans) | the same repositories, listed file by file in `fetch.yml` with their SHA-256; fetched by `tool/showcase.dart`, not committed (about 300 MB) | each in `fetch.yml` |
| `images/blank.svg` | drawn for the work: the PDF's spacers (a page the printing leaves blank, the room a cut's lower part takes) | |

Wonderland's chapters, its poem, title page and contents are made by
`tool/alice_1867` (its README): the 1867 text on the printing's lines;
of its 2,119 disagreements with Standard Ebooks, 1,653 settled by rule
(923 of them italics found by the slant of their strokes) or by a second
reading, 466 by review against the scan
(`tool/alice_1867/decisions/wonderland.tsv`); the printing's readings
kept where they differ from Standard Ebooks' text ("to-day", "any one",
"I've", its italics and its capitals, its poems as 1867 prints them,
shorter in places than the later editions Standard Ebooks follows); its
divided words marked where it divides them (`{shy}`, `{zwsp}`). Looking-Glass was imported by
`tool/showcase_import.dart --part looking-glass`, then edited by hand:

- `alice.adoc`: the two books as the parts of one, the chapters numbered
  in upper-case Roman numerals, restarting with Looking-Glass.
- Looking-Glass, Chapter I: the image of the mirrored stanza replaced by
  the stanza itself in a `[verse.mirror.jabberwocky]` block; the poem
  itself given the `jabberwocky` role (italic, as the book sets it).
- Looking-Glass, the chess problem: its moves as a two-column table of
  White's and Red's, as the book prints them.
- Looking-Glass's images' sizes from the production's classes:
  `half-page` floats beside the text, `three-quarter-page` at 75%.

## Licence

The texts and illustrations are in the public domain: published in 1865
and 1871 (Wonderland's text here as printed in 1867), in the United
States (published before 1930) and under life plus 70 years (Carroll died
in 1898, Tenniel in 1914). The Internet Archive's scans of the University
of Toronto's copy are of a public-domain book. Standard Ebooks dedicates
its productions, the SVG tracings and the markup included, to the public
domain (CC0 1.0). Standard Ebooks' own pages (title page, imprint,
colophon, logo) are left out; the work makes no use of its name beyond
this credit.

## Fonts

Old Standard TT (SIL Open Font License 1.1), from Google Fonts, for the
modern face Richard Clay printed the books in, and UnifrakturMaguntia
(SIL Open Font License 1.1), from Google Fonts, for the title page's
blackletter "London:": `ptome doctor --look alice --looksdir
test/showcase/alice` installs them. Not committed.

## The printings the look follows

- Alice's Adventures in Wonderland, London: Macmillan and Co., 1867, the
  sixth thousand (the 1865 first edition's setting), University of
  Toronto's copy: https://archive.org/details/alicesadventu00carr
- Through the Looking-Glass, and What Alice Found There, London:
  Macmillan and Co., 1872 (the first edition, dated 1872), Duke
  University Libraries' copy:
  https://archive.org/details/throughlookinggl01carr

## Where it departs from them

- Old Standard TT for Clay's modern: its letters a little wider, three
  of Wonderland's verse lines are tracked in a hair (`[.tight]`) to keep
  their lines; the Tale's lines stand within a point or two of the
  printing's places.
- The title page: the 1867 title leaf is taller than the text pages; its
  lines keep their sizes and widths, their gaps closed in proportion to
  fit the text area. The half-title follows the volume's own title page,
  so it falls on a verso; the binder's blank leaves and the half-title's
  full stop are left out.
- The printer's imprint on the last page stands 3 pt higher than the
  printing's, at the foot of the text area.
- The illustrations are Standard Ebooks' tracings, not the engravings:
  their proportions differ from the printed cuts by up to a few percent,
  each drawn at the printed cut's width.
- Looking-Glass is not yet transcribed from its printing: its text flows
  in the look.

## In HTML and EPUB

- Wonderland's text is the 1867 text in all three formats; its lines are
  the PDF's alone (in HTML and EPUB each paragraph flows), and its
  spacers, page breaks, title page and contents are the PDF's alone
  (`ifdef::backend-pdf[]`).
- The Mouse's Tale shrinks down its tail and Jabberwocky's stanza is
  mirrored in all three formats (the look's CSS for HTML and EPUB), and
  the chess problem's moves are in two columns in each. The illustrations
  the text runs beside float to their side in HTML; an EPUB sets each in
  its place across the text, as a reader's narrow page would anyway.
