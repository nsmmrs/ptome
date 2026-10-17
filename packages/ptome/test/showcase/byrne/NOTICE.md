---
title: "Byrne's Euclid"
source: byrne.adoc
looks: [byrne]
compare:
  - page: 1
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n34.jpg
    note: "Book I's opening: its headpiece, \"Euclid.\" in blackletter, Proposition I (1847)"
  - page: 2
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n35.jpg
    note: "Proposition II: a line equal to a given line, from a given point (1847)"
  - page: 13
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n46.jpg
    note: "Proposition XIII: its sums of angles set as lines of symbols (1847)"
  - page: 48
    scan: https://archive.org/download/firstsixbooksofe00byrn/page/n81.jpg
    note: "Proposition XLVII, Pythagoras's theorem, its first page (1847)"
---

# Byrne's Euclid

Book I of Oliver Byrne's The First Six Books of the Elements of Euclid,
in Which Coloured Diagrams and Symbols Are Used Instead of Letters for
the Greater Ease of Learners, as William Pickering printed it in 1847,
page for page and line for line: its forty-eight propositions on the
book's pages 1 to 50. What the work shows: colour as meaning — each
proposition's diagram in red, yellow, blue and black, and the text naming
its lines, angles, triangles and figures not by letters but by small
coloured figures of them, set on its lines at the printing's own heights
(an inline image's `vertical-align`, FEAT-v2vw73); the signs Byrne sets
the same way (⊏, ⊐, ∥, ⊥, ∴); the woodcut initials; the demonstrations'
lines of symbols, some braced together.

In the PDF each page is the printing's page: each printed line is a
paragraph of its own (its margins the printing's, in tenths of a point,
its words justified to them, its letters closed up or spread where Libre
Caslon sets them wider or narrower than the printing's Caslon), and each
line, diagram and initial sits where the scan shows it (its own
`margin-top`, from the scan: `tool/byrne_1847`). The running heads are
the printing's ("BOOK I. PROP. II. PROB.") with their folios outside, in
old-style figures, the opening page unheaded; a gathering's first page
has its signature (B … H) at its foot.

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| The text | transcribed for the work from the scan below, line by line (`tool/byrne_1847/text.tsv`: each line's words and the symbols it sets, read against the Internet Archive's OCR) | |
| The scan and its OCR | https://archive.org/details/firstsixbooksofe00byrn: `…_jp2.zip` (the leaves, 300 ppi, in colour), `…_hocr.html`; Book I is leaves 35–84 | `c8be613f0916ed020fefcf19c8ccab341629cd162756dd654710460036c4c9fd`, `480ef3a368ac5a624bf99bdd56d396629eb7a7b13c7a1ed317f9a43c78a345ed` |
| `images/` | traced from the same scan by `tool/byrne_1847` (`trace.py`): each diagram, initial and symbol its own ink, separated by colour, outlined (potrace) and filled with one of the printing's four inks, sampled from the scan | |

The transcription keeps the edition's words, its abbreviations ("post.",
"const.", "pr.", "def.", "ax.") and its punctuation, and writes the round
s for its long s. Where the edition prints a figure, the text has the
figure, its alternative text naming it ("a red line", "is greater than");
a group of figures braced together is one picture.

## Licence

The book is in the public domain (published 1847; Oliver Byrne died in
1880). The transcription, its markup and the tracings are the work's own
(MIT, as the repository). The scans are not committed:
`tool/showcase.dart` fetches the pages it compares into its cache, and
`tool/byrne_1847` works from the Internet Archive's files in its work
folder.

## Fonts

Libre Caslon Text, roman and italic (SIL Open Font License 1.1), from
Google Fonts: `ptome doctor --look byrne --looksdir test/showcase/byrne`
installs it. Not committed.

## The printing the look follows

The first edition, London, William Pickering, 1847, a small quarto: the
Getty Research Institute's copy, scanned by the Internet Archive,
https://archive.org/details/firstsixbooksofe00byrn. The page is
7.4 × 9.3 in, the scan's scale 72/300 pt to its pixel.

Where the look departs from it:

- Libre Caslon Text stands in for the edition's Caslon: its letters are a
  little wider or narrower here and there, so a line's letters are spaced
  to the printing's width; it has no long s.
- The diagrams, initials, symbols, the headpiece and the blackletter
  "Euclid." are tracings of the scan in four flat inks: the printing's
  shapes, a little smoothed, without the paper, the press's unevenness or
  the colours' showing through.
- In HTML and EPUB each printed line is a paragraph, without the
  printing's measures and heights; the diagrams are as wide as the
  printed page, where the PDF sets them.
- In the excerpt test, Noto Serif stands in for Libre Caslon, so its
  lines don't fit the printing's as the work's do.
