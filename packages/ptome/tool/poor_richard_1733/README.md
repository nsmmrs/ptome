# Poor Richard, set as its facsimile sets it

The showcase's Poor Richard (test/showcase/poor-richard) is the first
Poor Richard's Almanack, for 1733, as George S. Appleton's facsimile
([1849?]) sets its pages, page for page and line for line: the title
page, the address to the reader over two pages, the anatomy, the
explanation, and the twelve months (the facsimile's 4th page, the
planets' motions, and its 6th, the table of kings, are left out with
its other tables: test/showcase/poor-richard/NOTICE.md). The Internet
Archive's scan of the University of North Carolina's copy,
https://archive.org/details/poorrichardalman00fran. Each source line
is a printed line (`:source-lines:`), each page in its frame (the
look's page backgrounds, measured from the scan), each block where the
scan has it, the folios where the facsimile sets them and numbered as
it numbers them (1, 2, 3, 5, 7…18). These scripts made the months' text
and fitted the look and the places; they are kept for the record and to
make them again. Python 3 with Pillow and NumPy; Tesseract; Poppler's
`pdftotext` and `pdftoppm`; a ptome executable (`PTOME`, by default
`~/.cache/asciidart-work/print-match/ptome`).

## The work folder

`PR_WORK` (by default `~/.cache/asciidart-work/print-match/poor-richard`),
not committed, made by `fetch.sh`: the item's JPEG 2000 scans (their
SHA-1 the item's own), the sixteen leaves the work is set after drawn as
PNG (`png/NNNN.png`, 400 ppi) and read by Tesseract (`tess/NNNN.hocr`).
The scripts write what they derive there too: `measure.json`,
`build/` (the work staged by `tool/showcase.dart` and built),
`overlay/`.

## Steps

1. `months.spec`: the months as the facsimile prints them, each line of
   a verse a line, each day of a calendar a row of seven cells, read
   against the scan; `gen.py` writes `text/NN-month.adoc` from it, with
   `adjust.json` (each verse line's indent, each month's verse and
   calendar margins and its rows' pitch) and `wraps.json`, and the
   look's `i<tenths>` and `p<pitch>` roles. `build.sh` makes them and
   builds the PDF.
2. `measure.py`: each month's leaf measured from its ink, the page
   turned upright by its frame's left rule: the frame's corner, the
   heading's baseline, the rules, the verse's lines and their ends, the
   calendar's rows (a comb of its pitch) and its rules down
   (`measure.json`); `rules.py`, the long rules on any leaf.
3. `fit.py`: each month's verse and calendar moved until their lines
   are where the scan has them (the PDF's from its text, Poppler's,
   in the same frame coordinates); `indents.py`: each verse line set in
   as far as the scan sets it; `wraps.py`: the calendar's cells the face
   would set on two lines where the printing has one, set closer
   (`tight<n>`), as the printing's compositor squeezed them.
4. `front.py`: the front pages' blocks (text/front.adoc, hand-written,
   each source line a printed line) moved to their places: each block's
   first line found among Tesseract's lines, or given in `targets.json`
   (the lines and rules it doesn't read, measured from the ink); the
   margins written into front.adoc. `widths_front.py`: the width of
   each line the printing doesn't justify, against the scan's, for the
   roles' sizes.
5. `check.py`: every month's line and row against the scan's;
   `overlay.py`: a month's page over its scan (red the scan, blue the
   PDF), read by eye.

## Where it stands

Every line is the facsimile's, none set on two lines. Of the months'
452 verse lines and calendar rows, 433 are within a point of the scan's
(`check.py`) and the rest within 5: the scan's paper is warped, a rule
across the page bending by up to 4 points, and the comb that finds a
row in a few warped places finds it a line's x-height off. The front
pages' blocks are within half a point of the scan's (`front.py
--report`); their unjustified lines within a few percent of its widths.
The type is Libre Caslon at the sizes that give the printing's line
widths (the verse and the calendar at about 10.3 points on an 11.8
point pitch); the calendar's cells keep the printing's column widths,
some squeezed as the printing's are.
