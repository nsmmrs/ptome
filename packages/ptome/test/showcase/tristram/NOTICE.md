---
title: "The Life and Opinions of Tristram Shandy, Gentleman"
source: tristram.adoc
looks: [tristram]
compare:
  - page: 37
    scan: https://archive.org/download/10931855bsb/page/n12.jpg
    note: "Vol. I, Chap. I: its head and initial (London, 1770)"
  - page: 74
    scan: https://archive.org/download/10931855bsb/page/n82.jpg
    note: "Yorick's epitaph, in its frame (1770)"
  - page: 75
    scan: https://archive.org/download/10931855bsb/page/n84.jpg
    note: "The black page (1770)"
---

# The Life and Opinions of Tristram Shandy, Gentleman

Laurence Sterne's novel, whole, in a look after its first edition. What
the work shows: typographic play — the black page (both sides of a leaf
printed black after Yorick's epitaph), the marbled page (both sides of a
leaf), the two chapters of Volume IX that are only their heads (each a
page of its own), the rows of asterisks, the plot-line diagrams of
Volume VI, the Latin and the Greek — and Sterne's dashes of many lengths:
the two- and three-em dashes (U+2E3A, U+2E3B), which Caslon's revival
lacks, set as two and three em dashes run together (FEAT-4lj836).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| Tristram Shandy, Standard Ebooks | https://github.com/standardebooks/laurence-sterne_the-life-and-opinions-of-tristram-shandy-gentleman at `89676643cb7dee3b46aba13868f3d92f9897998c` (the `codeload.github.com` tarball) | `8167210a2d173d0fe5903d53cc3a5584800fa696bd0926ccda50937906015d68` |
| The marbled page (JPEG) and the plot lines and flourish (SVG), Standard Ebooks | the same repository, in `fetch.yml` with their SHA-256 | in `fetch.yml` |
| `images/black-page.svg` | drawn for the work | |

Imported by `tool/showcase_import.dart`, then edited by hand:

- The chapters headed as the first edition heads them, "Chap. I.".
- The black page: Standard Ebooks' tombstone drawing replaced by two
  pages printed black (`images/black-page.svg`, filling the type area),
  after the second "Alas, poor YORICK!", where the first edition prints
  them; the epitaph framed (`[quote.yorick]`).
- The marbled page set on both sides of its leaf.
- Volume IX's chapters XVIII and XIX, which are only their heads, each
  on a page of its own.

## Licence

The novel is in the public domain (published 1759–67). Standard Ebooks
dedicates its production, the images included, to the public domain (CC0
1.0); its own pages and logo are left out, and its name is used only in
this credit. The black page is the work's own (MIT, as the repository).

## Fonts

Libre Caslon Text, and Noto Serif for the Greek (both SIL Open Font
License 1.1), from Google Fonts: `ptome doctor --look tristram
--looksdir test/showcase/tristram` installs them. Not committed.

## The printing the look follows

The Life and Opinions of Tristram Shandy, Gentleman, Vol. I, London: J.
Dodsley, 1770 (a later printing of the first edition's setting), the
Bayerische Staatsbibliothek's copy: https://archive.org/details/10931855bsb

## Where it departs from it

- The text is Standard Ebooks' (the first edition's, its spelling
  modernized where Standard Ebooks does); the first edition's long s and
  its catchwords at the foot of each page are not set.
- Each volume is a part of one book; the first edition's nine volumes
  each have their own title page.
- Yorick's epitaph's frame is the width of the text; the book's is
  narrower.

## In HTML and EPUB

- In HTML and EPUB the black and marbled pages are their images across
  the page, the chapters of headings alone each a section of its own,
  and Sterne's two- and three-em dashes the characters themselves
  (U+2E3A, U+2E3B), which the reader's fonts draw where they have them;
  the PDF alone sets them as em dashes run together in Caslon, which
  lacks them.
