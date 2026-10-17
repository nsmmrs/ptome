# Punch, set as its first volume sets it

The showcase's Punch (test/showcase/punch) is three issues of Punch's
first volume (17 July, 14 and 21 August 1841) as the volume prints them,
its pages 1 to 12 and 49 to 72 page for page and line for line: each
page under its running head and folio in two columns ruled apart, the
pieces' heads, the short rules between the pieces, the cuts where the
volume sets them, the footnotes at a column's foot, the tables, the
plates on pages of their own and the Synopsis of Voting set sideways.
The words are Project Gutenberg's transcriptions of the issues
(test/showcase/punch/text/issue-*.adoc), laid on the lines of the
Internet Archive's scan of the volume
(https://archive.org/details/sim_punch_1841_1, leaves 4 to 15 and 52 to
75, the printed page the leaf less three) and read against it line by
line. Each source line is a printed line (`:source-lines:`), each page
a section of its own. These scripts made the text and fitted the look
and the places; they are kept for the record and to make them again.
Python 3 with Pillow, NumPy and fontTools; Tesseract; Poppler's
`pdftotext`, `pdftoppm` and `pdftohtml`; a ptome executable (`PTOME`,
by default `~/.cache/asciidart-work/print-match/ptome`).

## The work folder

`PUNCH_WORK` (by default `~/.cache/asciidart-work/print-match/punch`),
not committed, made by `fetch.sh`: the scan's JPEG 2000 leaves drawn as
PNG and its page images (their SHA-256 in `scans.sha256` and
`pages.sha256`), its OCR (`ocr.json`), page 3 turned to read and read by
Tesseract (`p3/ocr.hocr`), and each leaf turned upright and measured
(`geometry.py`: the paper, the lean, the double rule under the running
head, the rule between the columns; `upright/`, `geometry.json`). The
scripts write what they derive there too: `draft.json`, `cuts.json`,
`scan.json`, `fit.json`, `build/` (the work staged and built by
`build.sh`), `overlay/`.

## Steps

1. `align.py`: the transcription's words laid on the OCR's lines,
   letter by letter (`draft.json`); `cuts.py`: the cuts on each page,
   the ink left when the lines of text are blanked (`cuts.json`), and
   `plates.py` the plates' engravings, the alphabet's strips of cuts and
   the cavatina's score; `spec.py`: a first spec (`punch.spec.draft`);
   `fixes.py`: `punch.spec`, the draft with the corrections read from
   the scan (`fixes.txt`); `fetchyml.py`: the showcase's `fetch.yml`,
   each cut's crop of its page image.
2. `gen.py`: `text/pages.adoc` from the spec, with `adjust.json` (each
   paragraph's margin and pitch, keyed by its first line; each cut's
   margin and its foot, `cut/ID`, `foot/ID`) and the look's roles it
   writes (`p<pitch>`, `m<indent>`, `s<size>`). `build.sh` stages and
   builds the PDF (`ONLY=PAGE` a page alone).
3. `scan.py`: each spec line's baseline and ends on the scan, its words'
   ink falling off under them, the leaf set on the PDF's page by its
   rules (`scan.json`).
4. `page.sh PAGE` fits a page alone: `pitch.py` (each paragraph's pitch,
   a short one its column's), `margins.py` (each paragraph's and each
   cut's margin, a few rounds, a block floating to a side first), then
   `compare.py` and `wraps.py`; `allpages.sh` every page; `feet.py` each
   floated cut's foot; `reset.py PAGE` forgets a page's margins.
5. `compare.py`: every line of every page against the scan's (`--lines`
   lists those more than a point off; a line that is not the spec's is
   counted); `wraps.py`: where a column's lines first part from the
   spec's; `sbs.py PAGE`: the spec beside the PDF there; `overlay.py`: a
   page over its leaf (red the scan, blue the PDF), read by eye;
   `review.py`: a page's lines the alignment didn't place, with their
   crops.
6. `p3.py`: page 3, the Synopsis of Voting, drawn as an SVG
   (`images/synopsis.svg`) from Tesseract's reading of the leaf turned
   to read, each line the transcription's (`p3-fixes.txt` the lines read
   off the scan), its size and spacing the scan's, its rules the scan's
   long dark runs.

The spec's lines: `@page N leaf L [plate|blank|drawn]`, `@column`, a
line by its kind (`H` a piece's head, `h` a head within it in small
capitals, `K` one in roman capitals, `P` a paragraph's first line, `N`
one not set in, two spaces a line going on, `V` a verse's line, `C` a
centred line or caption, `F` a footnote, `T` a table's row, its cells
between ` | `, ` // ` a cell's second line, ` :::` dots led to its end),
`@rule`, `@cut ID [left|right|center]`, `@float right WIDTH GAP` …
`@end` (a block floating at the column's side, its lines a column of
their own), `@box left WIDTH [framed]` … `@end` (the column's lines kept
to a width, floated, ruled round), `@size POINTS` … `@size`, `@table
ROLE COLS GRID`; ` @WORDS` at a line's end sets them flush right.

## Where it stands

Every line is the volume's, none set on two lines: every column has the
scan's lines (`compare.py`). Of the 4,257 lines of the 36 pages, 4,239
have their baselines within a point of the scan's, all but three within
two (the alphabet's last line, which the volume sets a little apart,
and two lines under a cut or a table). The plates are the scan's
engravings with their titles and captions in place; the blank backs of
the plates are blank. Old Standard TT at 6.9 points, its letters let
widen or narrow by up to six percent in a justified line
(`base_font_expansion`), stands in for the volume's Scotch roman.
