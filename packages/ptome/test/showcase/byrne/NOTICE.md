---
title: "Byrne's Euclid"
source: byrne.adoc
looks: [byrne]
compare:
  - page: 2
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n34.jpg
    note: "Book I, Proposition I: the equilateral triangle (1847)"
  - page: 3
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n35.jpg
    note: "Proposition II: a line equal to a given line, from a given point (1847)"
  - page: 6
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n38.jpg
    note: "Proposition V: the angles at the base of an isosceles triangle (1847)"
---

# Byrne's Euclid

The first five propositions of Book I of Oliver Byrne's The First Six
Books of the Elements of Euclid, in a look after its first edition
(1847). What the work shows: colour as meaning — each proposition's
diagram in red, yellow, blue and black, redrawn as SVG from its
construction, and the text naming the lines, circles, triangles and
angles not by letters but by small coloured figures of them set inline,
as Byrne set them (inline SVG images, their alt text naming them); the
diagram floated beside the enunciation, which opens with a large
initial (BUG-qqz54w: an initial beside a floated image was lost); the
steps of each demonstration each on a line, and their references to
the definitions, postulates and propositions (FEAT-6fmfl5).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| `text/book-1.adoc` | transcribed for the work from the facsimile of the first edition, https://archive.org/details/firstsixbooksofe00byrn (pages 1–5 of Book I, scans n34–n38) | |
| `images/` | drawn for the work by `tool/showcase_byrne.dart`, each diagram from its construction (an equilateral triangle on a line, a circle about a point through another) after the edition's, each symbol from its diagram; the edition's colours sampled from the scans | |

The transcription keeps the edition's words, spelling, abbreviations
("post.", "const.", "pr.", "def.", "ax.") and punctuation; it writes the
round s for the edition's long s. Where the edition prints a coloured
figure, the text has the figure: `text/symbols.adoc` names the lines
(`{red}`, `{red-blue}`...), the equals sign and the sign for
therefore, the rest are named where they are used.

## Licence

The book is in the public domain (published 1847; Oliver Byrne died in
1880). The transcription and the drawings are the work's own (MIT, as
the repository). The scans are not committed: `tool/showcase.dart`
fetches the pages it compares into its cache.

## Fonts

Libre Caslon Text, roman and italic (SIL Open Font License 1.1), from
Google Fonts: `ptome doctor --look byrne --looksdir test/showcase/byrne`
installs it. Not committed.

## The printing the look follows

The first edition, London, William Pickering, 1847: the Getty Research
Institute's copy, scanned by the Internet Archive,
https://archive.org/details/firstsixbooksofe00byrn.

Where the look departs from it:

- Libre Caslon Text stands in for the edition's Caslon; the sign of
  equality and the sign for therefore are drawn, as its face hasn't the
  one and the edition's other is long.
- The initials are the text's capitals, not the edition's woodcut
  initials, white on a black ground of ornament; the headpiece over
  Book I and the blackletter "Euclid." are left out.
- Each proposition is headed with its number and kind, as the edition
  heads only the first; the running head names it in full ("BOOK I.
  PROPOSITION II. PROBLEM.", where the edition abbreviates "BOOK I.
  PROP. II. PROB.").
- The diagrams are drawn exactly from their constructions; the symbols
  in the text are lines of one length, where the edition's vary, and a
  few, the triangles of Proposition II, are upright as the edition sets
  them rather than as their diagram has them.
- In HTML, the symbols are scaled with the text by CSS `zoom`; in EPUB
  they are at their own size, which a reader's larger text outgrows.
