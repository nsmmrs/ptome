# The Tempest, set as the First Folio sets it

The showcase's Tempest in the Folio's look (`-a look=folio`,
test/showcase/tempest) is the play as the First Folio (1623) prints it,
its nineteen pages page for page and line for line: the first page's
headpiece, title, act head and initial across the page over its two
columns; the speeches with their speakers run in, the long directions
hung, the songs set in as the Folio sets each line; the words too long
for a line turned up or down after a bracket where the Folio turns
them; the acts' and the scenes' heads between rules; each page in its
frame of rules under its running head and folio, its signature and
catchword at its foot; the last page's two bands (the play's end, then
the epilogue beside the list of the actors), FINIS between rules and
the next play's catchword. The words are the Text Creation
Partnership's transcription of the Folio (EEBO-TCP A11954, CC0), laid
on the lines of the Boston Public Library copy's scan
(https://archive.org/details/mrvvilliamshakes00shak, leaves 25 to 43)
and read against it line by line. Each source line is a printed line
(`:source-lines:`), each page a section of its own. These scripts made
the text and fitted the look and the places; they are kept for the
record and to make them again. Python 3 with Pillow and NumPy;
Tesseract; Poppler's `pdftotext` and `pdftoppm`; a ptome executable
(`PTOME`, by default `~/.cache/asciidart-work/print-match/ptome`).

## The work folder

`TEMPEST_WORK` (by default `~/.cache/asciidart-work/print-match/tempest`),
not committed, made by `fetch.sh`: the transcription (`A11954.xml`), the
leaves' JPEG 2000 scans (their SHA-256 in `scans.sha256`) drawn as PNG,
and each page's two columns cut upright and read by Tesseract
(`columns.py`: `cols/`, `cols.json`). The scripts write what they derive
there too: `draft.json`, `scan.json`, `fit.json`, `build/` (the work
staged and built by `build.sh`), `overlay/`.

## Steps

1. `align.py`: the transcription's words laid on Tesseract's lines,
   letter by letter (`draft.json`); `spec.py`: a first spec from it
   (`folio.spec.draft`); `fixes.py`: `folio.spec`, the draft with the
   corrections read from the scan line by line (`fixes.txt`: lines run
   together or split, the turned words, the songs, the feet's
   signatures and catchwords, the letters the transcription marks
   illegible, the last page whole).
2. `gen.py`: `text/folio.adoc` from the spec, with `adjust.json` (each
   paragraph's margin, keyed by its first line; each line's indent and
   squeeze; each column's pitch; the paragraphs split where the paper's
   warp moves the lines) and the look's `i<tenths>` and `p<pitch>`
   roles. `build.sh` makes it and builds the PDF.
3. `scan.py`: each spec line's baseline and ends on the scan, the leaf
   set on the PDF's page by its frame of rules (`scan.json`).
4. `fitall.sh`, in order: `pitch.py` (each column's pitch), `tight.py`
   (the lines the face sets wider than the column, set closer as the
   compositor squeezed them), `headfit.py` (the first page's head and
   the last page's foot), `margins.py`, `splits.py`, `indents.py`,
   `headrules.py` (the rules about the acts' and the scenes' heads),
   and `compare.py`.
5. `compare.py`: every line of every page against the scan's
   (`--lines` lists those more than 1.5 points off); `overlay.py`: a
   page over its leaf (red the scan, blue the PDF), read by eye;
   `sheet.py`, `show.py`, `ink.py`, `count.py`, `head1.py`,
   `widths.py`: the measurements the look's sizes and the spec were
   read from.

## Where it stands

Every line is the Folio's, none set on two lines: every column has the
scan's lines (`compare.py`). Of the 2,359 lines, 2,353 have their
baselines within a point of the scan's, all within 1.7 (the last leaf
is curled); 2,128 start within 1.5 points of where the scan's start,
2,306 within 3 (the rest heads and directions the Folio centres a few
points off the middle, and lines whose first letters are worn). A line's
right end is the measure where the Folio justifies it, and its type's
otherwise: IM Fell DW Pica at 11.33 points, on the Folio's pitch of
about 12.5, stands in for the Folio's types, their widths a few percent
off the Folio's word by word.
