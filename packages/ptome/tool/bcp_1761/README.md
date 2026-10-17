# The Book of Common Prayer, set as Baskerville's 1761 printing sets it

The showcase's Book of Common Prayer (test/showcase/bcp) is the
Calendar, the Order for Morning Prayer, the Litany and the Psalter as
John Baskerville printed them at Cambridge in 1761 (the octavo of 1760
reissued), page for page and line for line: each page of text in its
frame of printers' flowers under its running head, the day's number
flush right on a recto and flush left on a verso; the psalms' titles,
the offices' heads and the parts of psalm cxix.; each verse numbered in
its first line, the first of a psalm opening with an initial two lines
deep; the rubrics in a smaller italic, their ¶ hung; the versicles and
responses set in where the printing sets them; the signature and the
catchword at the foot; and the Calendar's twelve months, each a ruled
table on a page of its own. The words are read off the Internet
Archive's scan of the Bayerische Staatsbibliothek's copy
(https://archive.org/details/10904662bsb, leaves 23 to 34, 45 to 61, 78
to 86 and 415 to 642), against the units corpus's Prayer Book
(test/units/corpus/liturgy/bcp-1662) and the King James Bible's words,
and decided line by line. Each source line is a printed line
(`:source-lines:`), each page a section of its own. These scripts made
the text and fitted the look and the places; they are kept for the
record and to make them again. Python 3 with Pillow, NumPy and
fontTools; Tesseract 5 with its English model; Poppler's `pdftotext`,
`pdftoppm` and `pdfinfo`; a ptome executable (`PTOME`, by default
`~/.cache/asciidart-work/print-match/ptome`); Baskervville installed
(`ptome doctor --look bcp --looksdir test/showcase/bcp`).

## The work folder

`BCP_WORK` (by default `~/.cache/asciidart-work/print-match/bcp`), not
committed, made by `fetch.sh`: the scan's JPEG 2000 leaves (their
SHA-256 in `scans.sha256`), each drawn as PNG, turned upright by its
frame's lean and measured (`geometry.py`: the frame's outer rule;
`png/`, `upright/`, `geometry.json`), read by Tesseract (`ocr.py`:
`tess.json`), and the Calendar's pages measured (`calgeo.py`: their
rules across and down, the baselines of their lines; `cal.json`). The
scripts write what they derive there too: `draft.json`, `where.json`,
`origin.json`, `scan.json`, `fit.json`, `build/` (the work staged and
built by `build.sh`).

## Steps

1. `decide.py`: each leaf's words (Tesseract's) aligned with the
   corpus's (`corpus.py`: a part's words in order, the psalms' titles
   and verse numbers as the printing prints them, the Litany's
   responses after each petition), each word decided: the corpus's
   letters where they are the scan's, the printing's own spelling where
   it differs only so (`lyes`, `wholsome`, `scepter`), the long s read
   as the round (f, l, t, i read as s against the vocabulary), words run
   together parted, a word no rule decides flagged (`draft.json`); the
   flagged words read off the scan (`sheets.py` their sheets,
   `readings.tsv` the readings, `read.py` to add them).
2. `spec.py`: a first spec (`bcp.spec.draft`) and each of its lines'
   place on the scan (`where.json`): the running heads and the feet as
   the printing sets them, each line's kind by its indent, the psalms'
   titles in their order with the printing's Latin (`LATIN` where it
   is not the corpus's), the offices' heads in their order, psalm
   cxix.'s parts, the verses' first lines found by reading each psalm's
   lines against its verses, the specks of the frame and the paper
   dropped. `fixes.py`: `bcp.spec`, the draft with the lines read off
   the scan (`fixes.tsv`: a leaf, its draft line, the scan's) and the
   pages written whole by hand (`pages/`: Morning Prayer, the Litany,
   the Psalter's title page), the verses numbered once more, each foot's
   signature the one the octavo's collation gives (`origin.json` maps
   each line back to the draft's). `review.py`: sheets of lines, each
   its crop of the scan over the spec's text, to read them by.
3. `calendar.spec`: the Calendar's months read off the scan, a day a row;
   `months.py` sets them: each month's rules drawn where the scan's are
   (`images/cal-LEAF.svg`), its tables' columns the scan's, a cell's rule
   a leader of rules, a name the printing set closer drawn together.
4. `gen.py`: `text/pages.adoc` from the spec and the Calendar, with
   `adjust.json` (each block's margin `top/LEAF/LINE` and pitch, a
   month's rows' pitch `calpitch/LEAF`) and the look's roles it writes.
   `build.sh` stages and builds the PDF (`ONLY=LEAF` a page alone).
5. `scan.py`: each spec line's baseline on the scan, the leaf set on the
   PDF's page by its frame (`scan.json`); `pitch.py` each paragraph's
   pitch, `margins.py` each block's margin, a few rounds; `page.sh LEAF`
   fits a page alone.
6. `compare.py`: every line of every page against the scan's (`--lines`
   lists those more than a point off; a line that is not the spec's is
   counted, a page with more or fewer lines than the spec's named).

`frame.py` traced the frame of flowers (`images/frame.svg`) from leaf
417; `slant.py` tells italic from roman by the shear of a word's ink.

## Where it stands

Every line is the printing's, none set on two lines: every page has the
scan's lines (`compare.py`). Of the 8,376 lines of the 266 pages, 8,346
have their baselines within a point of the scan's, all but thirteen
within two (lines on leaves that curl, where the scan's lines are not
evenly spaced within a paragraph). Baskervville, the ANRT's revival of
Baskerville's types, at 14.6 points (Great Primer) on the octavo's
17.3-point pitch, its letters let widen or narrow by up to four percent
in a justified line, stands in for Baskerville's own; the Calendar in
it at 10.2 points (Long Primer).
