# Johnson's Dictionary, set as its first edition sets it

The showcase's Johnson (test/showcase/johnson) is three pages of Samuel
Johnson's A Dictionary of the English Language as the first edition
sets them (W. Strahan for J. and P. Knapton and others, 1755, volume II,
LEVEL to LICENTIOUSLY): the Wellcome Collection's copy, scanned by the
Internet Archive, https://archive.org/details/b30451541_0002, leaves
n44–n46. Each source line is a printed line (`:source-lines:`), each
column the printing's (`[.column]` `<<<`), each line set in as far as
the printing sets it, each block where the scan has it (its own
`margin-top`), the heads over the columns, the folio, the signature and
the catchword where the printing sets them. These scripts made the text
and fitted the look and the margins; they are kept for the record and to
make them again. Python 3 with Pillow and NumPy; Tesseract; Poppler's
`pdftotext` and `pdftoppm`; a ptome executable (`dart compile exe
bin/ptome.dart`, `PTOME`, by default the work folder's parent's
`ptome`).

## The work folder

`JOHNSON_WORK` (by default `~/.cache/asciidart-work/print-match/johnson`),
not committed, made by `fetch.sh`: the three leaves' JPEG 2000 scans
(their SHA-256 in fetch.sh and the work's NOTICE.md), drawn as PNG
(`0046.png`…, 300 ppi), Tesseract's hOCR of each, the item's own OCR
(`djvu.txt`) and its lines on the three pages (`lines.tsv`). The scripts
write what they derive there too: `draft.tsv`, `scan.json`, `fit.json`,
`build/` (the work staged and built), `overlay/`.

## Steps

1. `fetch.sh`; `draft.py`: the OCR's lines with the long s read as
   round s where that makes a word (`draft.tsv`), a draft read against
   the scan by eye, line by line, into `johnson.spec`: each printed line
   a line, marked as an entry, a sense, a quotation in prose or in verse
   or a line going on, its headword, its words in italic, its author.
2. `gen.py`: the work's text, `test/showcase/johnson/text/pages.adoc`,
   from `johnson.spec`, with `margins.json`'s margins and `indents.json`'s
   spans (and their roles in the look); `build.sh` makes it and builds
   the PDF (`JOHNSON_WORK/build/johnson.pdf`).
3. `scan.py`: each printed line's baseline and ends on the scan
   (`scan.json`): the columns levelled strip by strip, each line found by
   its x-height's ink, its ends its words' and its ink's.
4. `compare.py`: each line of the PDF against the scan's, after mapping
   the scan's page onto the PDF's (an affine map, by least squares: the
   scans are cut, turned and stretched a little differently): its words
   the transcription's, its baseline, its ends. `widths.py`: the type's
   size and its spaces from the words' widths and the unjustified lines'.
5. `fit.py`: each block's margin moved until its lines are where the
   scan has them (`margins.json`); `indents.py`: the lines the scan sets
   further in than the PDF, each its span (`indents.json`; `--roles`, how
   far the look's indents are off); `furniture.py --fit`: the heads and
   the foot, the foot's blocks moved to the scan's (`margins.json`).
6. `overlay.py`: each page of the PDF over its scan, the scan in red,
   the PDF in blue (`JOHNSON_WORK/overlay/`), read by eye.

## Where it stands

Every line's words are the transcription's, none set on two lines and
none run together (`compare.py`: 553 lines). Each line's baseline is
within 1.6 pt of the scan's; each line's left end within about 2 pt (the
scan bows a little near the gutter and the foot), the half lines of verse
and the other lines the printing sets in further by their own spans. The
justified lines end at the measure, as the printing's; the unjustified
lines are as wide as the printing's on the whole (`widths.py`), each
within a few points, the headwords' small capitals, made from the
lowercase, a little narrower than the printing's. The heads sit where the
printing's sit on the three pages taken together, each page's within
about 7 pt across and 4 pt up and down (the printing places them by hand
a little differently on each); the folio, the signature and the
catchword on their baselines.
