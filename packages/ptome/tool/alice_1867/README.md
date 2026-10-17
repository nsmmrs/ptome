# Wonderland and Looking-Glass, transcribed from their printings

The showcase's Alice (test/showcase/alice) keeps Wonderland's text as
Macmillan printed it in 1867, the sixth thousand, the University of
Toronto's copy: https://archive.org/details/alicesadventu00carr. Each
paragraph's source lines are the printing's lines (`:source-lines:`), its
pages fall where the printing's do, and each cut, stanza and chapter
opening is set where the scan shows it. These scripts made that text and
the measurements in the look and the text's attributes; they are kept for
the record and to make them again. Python 3 with Pillow, NumPy and
fontTools; Tesseract 5 for the second readings; Poppler's `pdftotext` and
`pdftoppm`.

## The work folder

`ALICE_WORK` (by default `~/.cache/asciidart-work/alice-match`), not
committed:

- `dl/`: the item's files from the Internet Archive:
  `alicesadventu00carr_hocr.html` (ABBYY's OCR, each word's box),
  `_jp2.zip` (the scans, 650 ppi), `_page_numbers.json`; their SHA-256 in
  NOTICE.md. `alicesadventu00carr/` is the zip unpacked;
  `alicesadventu00carr.ocr.json` the OCR as pages of lines
  (`python3 -I hocr.py dl/alicesadventu00carr_hocr.html
  alicesadventu00carr.ocr.json`).
- `se/text/wonderland/`: Standard Ebooks' text as the work imported it,
  before the transcription (the files of `test/showcase/alice/text/` at
  commit 769620f15).
- `vocab.json` (`vocab.py`), `pg/` (its Gutenberg texts).
- `build/alice/images/`: the work's images, as `tool/showcase.dart`
  stages them.

## Steps

1. `transcribe.py wonderland --tesseract`: aligns the OCR's words with
   Standard Ebooks' (difflib, on their letters): where they agree, Standard
   Ebooks' word (its quotation marks, its markup) on the printing's line;
   where they don't, a choice, settled by a rule (a misread word the
   vocabulary lacks; a dash read as two), by a second reading of the
   word's crop by Tesseract, or by review: `decisions/wonderland.tsv`,
   each choice's id and its text (`line:LEAF:N` a line given whole). The
   printing's italics are found by the slant of each word's strokes
   (`slant.py`); its capitals kept; its divided words marked where it
   divides them (`{shy}`, `{zwsp}`). The cuts are measured on the scan
   (`cuts.py`: ABBYY's image regions, grown to the drawing's connected
   ink) and placed beside or between the lines they stand by, with their
   widths, heights, gaps and offsets; each stanza's size from its line
   pitch, its spaces from the scan; each chapter's first word in small
   capitals; the Mouse's Tale from `tale.py`, each line's size from its
   letters' height and its place from its left edge. Writes
   `out/wonderland/*.adoc` and `out/wonderland/lines.tsv`.
2. `sheets.py wonderland`: review sheets for the choices still open, each
   line's scan with the choice boxed and its readings below;
   `decide.py wonderland FILE` records the decisions (`N s|o|x|i|r|=TEXT`).
3. `openings.py wonderland`: each chapter's opening, as the look's
   `opening<n>` roles.
4. `front.py`: the title page and the contents (PDF only), each line's
   size from its letters' height, its letter-spacing from its width, its
   place corrected against the PDF.
5. `compare.py wonderland PDF 13`: each printed page against the PDF's
   page (chapter I is the PDF's 13th): its first and last words, its
   lines; `cutcheck.py wonderland PDF`: each cut's place against the
   scan's; `missing.py wonderland`: lines the OCR missed.

The drafts are copied into `test/showcase/alice/text/wonderland/`.

## Looking-Glass

The same steps make Through the Looking-Glass from its 1872 printing
(`BOOK` `looking-glass`, Duke University's copy,
https://archive.org/details/throughlookinggl01carr), its settings in
`common.py`:

0. `rescale.py looking-glass`: its 400 ppi scan and OCR resampled to
   Wonderland's 650 ppi (`ALICE_WORK/throughlookinggl01carr_650/`), so the
   measures tuned on Wonderland's hold; `pitch.py looking-glass` each
   leaf's line pitch, `cuts.py looking-glass` its cuts.
1. `transcribe.py looking-glass --tesseract`, `sheets.py`, `decide.py`
   as above (`decisions/looking-glass.tsv`); `linediff.py looking-glass
   --sheets` the lines whose words still differ from Standard Ebooks',
   beside their scans; `decisions/looking-glass.patches` the blocks a
   line's words can't make (the sum, the mirrored stanza, the plates'
   pages); `decisions/looking-glass-breaks.txt` the lines after which the
   printing ends a page early (compare.py reports them, `EARLY`).
2. `iterate.sh`: the draft copied into the work, the look's leaded
   stanzas' roles written (`leads.py`), the work built (`build.sh`) and
   compared page by page; `side.sh LEAF PDF-PAGE OUT` one page beside its
   scan.
3. `front_lg.py`: the front matter, each printed line a paragraph of its
   own size and measure where the scan has it (text/looking-glass/front.adoc
   and the look's `lgf-*` roles).
