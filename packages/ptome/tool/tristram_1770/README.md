# Tristram Shandy, Vol. I, set as Dodsley's 1770 printing sets it

The showcase's Tristram Shandy (test/showcase/tristram) is the first
volume of The Life and Opinions of Tristram Shandy, Gentleman as J.
Dodsley printed it in London in 1770 (the eighth edition), page for page
and line for line: Hogarth's frontispiece and the title page, the
dedication to Mr. Pitt in its larger type, and the 227 pages of the text,
Book I and Book II to the end of the volume's chapter XXXVI, each under
its number in brackets, "( 6 )"; the chapters running on under "C H A P.
I.", each opening with an initial two lines deep; a quotation's every
line opening with its marks; the marriage settlement's black letter; the
footnotes in the smaller size, one running on to the page after; Yorick's
epitaph in its frame of rules; the black page both sides of its leaf;
the signature, the volume's direction line, the press figure and the
catchword at the foot. The words are read off the Internet Archive's
scan of the Bayerische Staatsbibliothek's copy
(https://archive.org/details/10931855bsb, leaves 7 to 290, the pages the
copy binds in twice left out) against Standard Ebooks' text
(`transcription/`, the chapters this volume holds) and decided line by
line. Each source line is a printed line (`:source-lines:`), each page a
section of its own. These scripts made the text and fitted the look and
the places; they are kept for the record and to make them again. Python
3 with Pillow, NumPy and fontTools; Tesseract 5 with its English model;
Poppler's `pdftotext`, `pdftoppm` and `pdfinfo`; a ptome executable
(`PTOME`, by default `~/.cache/asciidart-work/print-match/ptome`); the
look's fonts installed (`ptome doctor --look tristram --looksdir
test/showcase/tristram`).

## The work folder

`TRISTRAM_WORK` (by default `~/.cache/asciidart-work/print-match/tristram`),
not committed, made by `fetch.sh`: the scan's JPEG 2000 leaves and the
Archive's hOCR (their SHA-256 in `scans.sha256`), the leaves drawn grey
(`png/`), the hOCR read (`ocr.json`), the leaves in the book's order
(`leaves.py`: `leaves.json`), the lines ABBYY's OCR missed read by
Tesseract (`fill.py`: `ocr2.json`), every leaf read again by Tesseract
(`tess.py`: `tess.json`). The scripts write what they derive there too:
`draft.json`, `choice.json`, `lineread.json`, `where.json`, `scan.json`,
`fit.json`, `build/` (the work staged and built by `build.sh`).

## Steps

1. `choose.sh`: `decide.py` aligns each page's OCR words with the
   transcription's and decides each word (the transcription's letters
   where they are the scan's, the printing's own spelling where it
   differs only so (`shew`, `tho’`, `Hobby-Horse`), the long s read as
   the round, a word the line divides divided where the scan divides it,
   the running quotes, the footnotes read on to the page after, a word no
   rule decides flagged), each leaf from the reading (ABBYY's or
   Tesseract's) that leaves fewer flagged (`choice.json`); `confirm.py`
   and `lineread.py` settle a flagged line the other reading, or
   Tesseract reading the line alone, reads as one of its choices;
   `quotes.py` gives a line its running quote where the scan has one
   (`quotes.txt` where it misreads). `review.py` makes sheets of the
   lines still flagged, each its crop of the scan over the draft's text;
   `fixes.tsv` has the lines read off them (a kind before `|` where the
   scan sets the line otherwise), `pages/` the pages read whole by hand
   (the dedication, the first page, the title page, the page of the
   tinted paper and two the OCR could not read).
2. `spec.py`: `tristram.spec`, each page's printed lines by kind, each
   kind by where the scan's ink sets the line against the text's edges
   about it (the leaf curls); the heads and the signatures as the
   printing's gatherings give them, each catchword the next page's first
   word (`CATCH` where the printing sets another); each line's box on the
   scan to `where.json`.
3. `gen.py`: `text/pages.adoc` from the spec, with `adjust.json` (each
   block's margin `top/PAGE/LINE`, its pitch, where a paragraph is
   parted `split/PAGE/LINE`, a signature's place `sig/PAGE`) and the
   look's roles it writes; the black pages and the first page's rule
   drawn where the scan's are. `build.sh` stages and builds the PDF, the
   frontispiece cut from the scan as `fetch.yml` has it.
4. `scan.py`: each spec line's baseline, its ink's ends and top on the
   scan, the leaf set on the PDF's page by its text's left edge and its
   head (`scan.json`); `pitch.py` each paragraph's pitch, `margins.py`
   each block's margin, a few rounds, a paragraph whose lines lie
   unevenly on the scan parted where they do.
5. `compare.py`: every line of every page against the scan's (`--lines`
   lists those more than a point off; a line that is not the spec's is
   counted, a page with more or fewer lines than the spec's named).

## Where it stands

Every line is the printing's, none set on two lines: every page has the
scan's lines (`compare.py`). All 4,934 lines of the 231 pages have their
baselines within a point of the scan's. Libre Caslon Text at 10.4 points
on the octavo's 16.73-point pitch (21 lines and the head and foot to the
page), its letters let widen or narrow by up to four percent in a
justified line, stands in for Caslon's English; the dedication at 12
points, the footnotes at 8.8 on 14; UnifrakturMaguntia at 18 points for
the settlement's black letter; the title page's lines each sized and
spaced from the scan.
