# The Second Reader, set as its 1920 printing sets it

The showcase's McGuffey (test/showcase/mcguffey) is the first forty-eight
pages of McGuffey's Second Eclectic Reader as the American Book Company
printed them in 1920: https://archive.org/details/mcguffeysseconde0000unse.
Each paragraph's source lines are the printing's lines
(`:source-lines:`), each page's last line the printing's, and each block
— a lesson's heading, its words, its woodcut, its title, its first
paragraph or stanza — has its own `margin-top`, fitted so that the PDF
sets it where the scan shows it. These scripts made the text and fitted
those margins; they are kept for the record and to make them again.
Python 3 with Pillow and NumPy; Poppler's `pdftotext`, `pdftohtml` and
`pdftoppm`; a ptome executable (`dart compile exe bin/ptome.dart`).

## The work folder

`MCG_WORK` (by default `~/.cache/asciidart-work/print-match`), not
committed:

- `mcguffey/`: the item's files from the Internet Archive
  (`mcguffeysseconde0000unse_hocr.html`, `_jp2.zip` unpacked, their
  SHA-256 in the work's NOTICE.md), `ocr.json` (the OCR as pages of lines,
  `tool/alice_1867/hocr.py`), `pg14668.html` (Project Gutenberg's text),
  `gimg/` (its woodcuts); `out/blocks.json` (`blocks.py`).
- `build/mcguffey/`: the work staged by `tool/showcase.dart --out
  build mcguffey` (its woodcuts edited by `fetch.yml`).
- `ptome`: the executable `fit.py` sets the PDF with.

## Steps

1. `mcg_lines.py`: Project Gutenberg's words on the scan's OCR lines, a
   draft of each page's lines; checked against the scan by eye, the
   printing's readings where Project Gutenberg's differ (NOTICE.md).
2. `blocks.py mcguffey 5 … 52 --json=…/out/blocks.json`: each page's
   lines (their baselines, from the ink), its words' places and its
   pictures' boxes, in points; `inkx.py` the ink along a line where the
   OCR missed words (a lesson's words around its woodcut).
3. The specs here (`title-page.spec`, `preface.spec`, `contents.spec`,
   `introduction.spec`, `lessons.spec`): the work's AsciiDoc, each page
   marked (`// page N`), each lesson's words as rows of `X word` (`@words`,
   X their left edges on the scan) and the key's tables as their cells
   (`@key`, `@subs`).
4. `build.py SPECS OUT margins.json`: the text, `test/showcase/mcguffey/
   text/*.adoc`: the word tables with their columns where the printing's
   are, a page break where the printing starts a page between blocks,
   and each block's `margin-top` from `margins.json`; `fit.json`, each
   block's place on the scan (found by its first words on its page, or
   given, `at=`, `top=`), moved by its page's offset (its running head's
   baseline against the PDF's).
5. `fit.py`: sets the PDF, reads where each block is (Poppler), moves its
   margin by how far it is off less how far the block before it on its
   page is, again until every block is within a few tenths of a point;
   writes `margins.json`.
6. `compare.py`: each page's lines against the scan's OCR, its first and
   last lines; the side-by-side pages are read by eye.

`blanks.py` finds the words printed around a woodcut in Project
Gutenberg's scan of it (the ink apart from the picture), for `fetch.yml`'s
`blank`.
