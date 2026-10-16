# Wonderland, transcribed from its 1867 printing

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
