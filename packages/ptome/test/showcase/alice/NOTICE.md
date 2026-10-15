---
title: "Alice’s Adventures in Wonderland and Through the Looking-Glass"
source: alice.adoc
looks: [alice]
compare:
  - page: 6
    scan: https://archive.org/download/alicesadventu00carr/page/n16.jpg
    note: "Wonderland, Chapter I: the chapter's head and opening (Macmillan, 1867)"
  - page: 28
    scan: https://archive.org/download/alicesadventu00carr/page/n52.jpg
    note: "The Mouse's Tale, in type that shrinks down its tail (Macmillan, 1867)"
  - page: 131
    scan: https://archive.org/download/throughlookinggl01carr/page/n6.jpg
    note: "Looking-Glass: the chess problem and its moves in two columns (Macmillan, 1872)"
  - page: 148
    scan: https://archive.org/download/throughlookinggl01carr/page/n36.jpg
    note: "Jabberwocky's first stanza in mirror type (Macmillan, 1872)"
---

# Alice’s Adventures in Wonderland and Through the Looking-Glass

Lewis Carroll's two Alice books, with John Tenniel's illustrations, in a
look after Macmillan's first editions. What the work shows: illustrations
the text runs beside (a role's float, FEAT-q1x0ys), the Mouse's Tale in
type that shrinks down its tail (roles of decreasing size in a verse
block whose own size is the tip's, so that the lines tighten as they
shrink), Jabberwocky's first stanza in mirror type (the `mirror` role,
FEAT-yq6kff), and the chess problem before Looking-Glass with its moves
in two columns.

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| Alice's Adventures in Wonderland, Standard Ebooks | https://github.com/standardebooks/lewis-carroll_alices-adventures-in-wonderland_john-tenniel at `9ecdf2ffa23098e7cb3c72157d7c3031b6f59903` (the `codeload.github.com` tarball) | `79a3cdf651270c94b739dd9ef5ef8f2a2778966d4e9afb40f91b8336cc24a50f` |
| Through the Looking-Glass, Standard Ebooks | https://github.com/standardebooks/lewis-carroll_through-the-looking-glass_john-tenniel at `56b8c2b2163e7eba0bed778b9c73aa8afbe572b1` | `323fbf4b4fc0a2d01bef6f772cc8adf195f9dd3ad5c44c1f20ab1cf9c9a701b1` |
| Tenniel's illustrations (SVG, traced by Standard Ebooks from the first editions' scans) | the same repositories, listed file by file in `fetch.yml` with their SHA-256; fetched by `tool/showcase.dart`, not committed (about 300 MB) | each in `fetch.yml` |

Imported by `tool/showcase_import.dart` (each book a part: `--part
wonderland`, `--part looking-glass`), then edited by hand:

- `alice.adoc`: the two books as the parts of one, the chapters numbered
  in upper-case Roman numerals, restarting with Looking-Glass.
- Wonderland, Chapter III: the Mouse's Tale's lines given the roles
  `tale-1` (the text's size, down to "to do.") to `tale-10`, the block
  kept on one page.
- Looking-Glass, Chapter I: the image of the mirrored stanza replaced by
  the stanza itself in a `[verse.mirror.jabberwocky]` block; the poem
  itself given the `jabberwocky` role (italic, as the book sets it).
- Looking-Glass, the chess problem: its moves as a two-column table of
  White's and Red's, as the book prints them.
- The images' sizes from the production's classes: `half-page` floats
  beside the text, `three-quarter-page` at 75%, `full-page` fit to its
  page.

## Licence

The texts and illustrations are in the public domain: published in 1865
and 1871, in the United States (published before 1930) and under life
plus 70 years (Carroll died in 1898, Tenniel in 1914). Standard Ebooks
dedicates its productions, the SVG tracings and the markup included, to
the public domain (CC0 1.0). Standard Ebooks' own pages (title page,
imprint, colophon, logo) are left out; the work makes no use of its name
beyond this credit.

## Fonts

Old Standard TT (SIL Open Font License 1.1), from Google Fonts, for the
modern face Richard Clay printed the books in: `ptome doctor --look alice
--looksdir test/showcase/alice` installs it. Not committed.

## The printings the look follows

- Alice's Adventures in Wonderland, London: Macmillan and Co., 1867
  (the 1865 first edition's setting), University of Toronto's copy:
  https://archive.org/details/alicesadventu00carr
- Through the Looking-Glass, and What Alice Found There, London:
  Macmillan and Co., 1872 (the first edition, dated 1872), Duke
  University Libraries' copy:
  https://archive.org/details/throughlookinggl01carr

## Where it departs from them

- The running heads: the books split a chapter's title across a spread
  (DOWN THE / RABBIT-HOLE.); here the book's title is on the verso and the
  chapter's on the recto.
- The Mouse's Tale starts a line of its own, where the book runs it on
  from the paragraph before.
- The illustrations float to the right; the books set some at the left
  and some across, by hand.
