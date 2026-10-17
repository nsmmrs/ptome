# The New-York Tribune, set as its pages of 16 April 1912 set it

The showcase's Tribune (test/showcase/tribune) is the paper's first two
pages of Tuesday, 16 April 1912, page for page and line for line: the
title over the folio line, the banner, the seven columns ruled apart
with their stories, heads, tallies and lists, the map and the pictures,
the ship's section and the advertisements cut from the scan. The words
are read off the Library of Congress's scans (Chronicling America,
https://www.loc.gov/resource/sn83030214/1912-04-16/ed-1/) region by
region. Each source line is a printed line (`:source-lines:`), each page
a section of its own. These scripts made the text and fitted the look
and the places; they are kept for the record and to make them again.
Python 3 with Pillow, NumPy and fontTools; Tesseract 5 with its English
model; Poppler's `pdftotext` and `pdftoppm`; a ptome executable
(`PTOME`, by default `~/.cache/asciidart-work/print-match/ptome`); the
look's fonts installed (`ptome doctor --look tribune --looksdir
test/showcase/tribune`).

## The work folder

`TRIBUNE_WORK` (by default `~/.cache/asciidart-work/print-match/tribune`),
not committed, made by `fetch.sh`: the pages' full-size scans and their
OCR (ALTO; their SHA-256 in `scans.sha256`), the OCR's lines
(`alto.py`: `alto.json`), each region's lines (`lines.py`: `lines.json`)
and each line read again by Tesseract (`tess.py`: `tess.json`). The
scripts write what they derive there too: `draft.json`, `where.json`,
`scan.json`, `fit.json`, `build/` (the work staged and built by
`build.sh`), `overlay/`.

## Steps

1. `regions.txt`: each page's regions in the scan's pixels, each a
   column of text (`text`) or a cut (`cut`).
2. `decide.py`: each region's lines decided word by word (`draft.json`),
   against the earlier transcription (`transcription/`) where it holds
   the region, else where Tesseract and the OCR agree or one of them is
   a word; `spec.py` writes a first spec (`tribune.spec.draft`), each
   line by its kind. The regions' specs (`regions/PAGE-REGION.spec`)
   were made from it and read off the scan line by line (`review.py`
   sets lines beside their crops); they are the text's source now.
3. `gen.py`: `text/pages.adoc` from the regions' specs, with
   `adjust.json` (each block's margin `top/PAGE/REGION/LINE` and pitch,
   each cut's margin `cut/NAME`) and the look's roles it writes (each
   line's size `z<hundredths>`, each region's margins, pitches,
   indents, a list's letter spacing). `build.sh` stages and builds the
   PDF, the cuts cut from the scan (`cuts.py`).
4. `scan.py`: each spec line's baseline on the scan (each region's
   lean measured, its rows' falls of ink, each line given the nearest in
   order, a head its own); `pitch.py` each paragraph's pitch, `margins.py`
   each block's and each cut's margin, a few rounds, in the order the
   pages flow.
5. `compare.py`: every line of every region against the scan's (`--lines`
   lists those more than a point off; a line not found on the PDF, or
   not the spec's, counted); `overlay.py PAGE` a page over its scan.

The spec's lines: `P ` a paragraph's first line (set in), `N ` one not
set in, two spaces a line going on, `S STYLE TEXT` a head's or a
caption's line in a style of `gen.py`'s (`@X0-X1` after it its extent
on the scan), `L TEXT | FIGURE` a tally's line, its dots led to the
figure (`L+` set in), `R ` a row of cells each where the scan's is, `F`
a line's two parts at its ends; `@role ROLE` the face of the paragraphs
after it, `@rule`.

## Where it stands

Every line is the paper's, none set on two lines: every region has the
scan's lines (`compare.py`). Of the 864 lines of the two pages, 846 have
their baselines within a point of the scan's, all within three (the
microfilmed pages lean and bow, each column its own way, so a level line
lies on the scan's only at its middle). Old Standard TT, Fira Sans
Condensed, League Gothic and Libre Franklin stand in for the paper's
types.
