# Babbage's logarithms, set as the 1831 printing sets them

The showcase's Babbage (test/showcase/babbage) is twenty pages of
Charles Babbage's Table of the Logarithms of the Natural Numbers, from
1 to 108000, the numbers 10,000 to 19,999, as the 1831 printing (B.
Fellowes, London, stereotyped from the 1827 edition) sets them, page for
page and row for row: the printing's pages 6 to 25 and their folios.
Oxford's copy, scanned by Google, from the Internet Archive:
https://archive.org/details/tablelogarithms00babbgoog (the page images
n30 to n49). The logarithms are computed (gen.py, to forty places, then
rounded to seven) and set as the printing sets them: each row's number
whole every tenth row; the first column's logarithm whole where its
first three figures change; a figure put up by rounding dotted under; an
entry past a change of its first three figures with its first figure
set small; the arcs whose seconds the number counts at the left; the
differences and their proportional parts in the column at the right,
where the printing has them (diff.spec, read against the scan). These
scripts made the pages and fitted the look; they are kept for the record
and to make them again. Python 3 with Pillow and NumPy; Tesseract;
Poppler's `pdftotext` and `pdftoppm`; a ptome executable (`PTOME`, by
default `~/.cache/asciidart-work/print-match/ptome`).

## The work folder

`BABBAGE_WORK` (by default
`~/.cache/asciidart-work/print-match/babbage`), not committed, made by
`fetch.sh`: the twenty page images (their SHA-256 in `scans.sha256`;
the 20th page's Google gave at a quarter of the others' resolution),
each page turned upright by its thick rule and its frame found
(`frame.py`: `upright/`, `frame.json`). The scripts write what they
derive there too: `build/` (the work built by `build.sh`), `overlay/`,
`ocr/`, `diff/`.

## Steps

1. `frame.py`: each page's table on its scan, the thick rule left of
   Num. traced for the page's lean, the rules under the heads and over
   the figures at the foot; the scan set on the PDF's page by them.
2. `gen.py`: `text/pages.adoc` (each page a section, its table and its
   head, tagged `page-N` for the excerpt), each page's rules as a frame
   (`images/frame-N.svg`) and the look's frame roles. The geometry
   (`common.py`): the columns' widths, the rules' places and the rows'
   pitch, 9.9 points and 4.9 more between fives, measured on the scans.
3. `diffscan.py`: a first reading of each page's column of differences
   by Tesseract; `diff.spec` read against the scan from it, page by page
   (each difference's side, its row, its parts, the parts that go on at
   the top of the next page).
4. `diffit.py`: the column's items set on the rows diff.spec gives,
   from how its blocks stack and a fitted margin each; `refine.py`: the
   rows moved to where the scan's figures are, the PDF's figures slid
   over the scan's (`run.sh` fits and compares).
5. `compare.py`: every row's baseline and every figure's right end
   against the scan's; `ocrcheck.py`: each row's figures as Tesseract
   reads them against the computed table's; `overlay.py`: a page over
   its scan (red the scan, blue the PDF), read by eye.

## Where it stands

Every row is the printing's and its figures are the computed table's:
Tesseract reads 931 of the 1,000 rows as computed; the others, read
by eye on two pages (7 and 10), differ only where it misreads a rule as
a 1 or a small figure as another, and the marks under the figures are
the printing's. Every row's baseline is within a point of the scan's;
of the 11,000 figures' right ends, 10,906 are within half a point of
the scan's (each scan registered across by its figures: Google's scans
are stretched across by up to a quarter of a percent). The differences
and their parts stand where the printing has them, within a point or
two. Old Standard TT Bold stands in for the printing's figures (its
3, 4, 5, 7 and 9 descend, 6 and 8 at full height; no free face has
those), at the size that gives the printing's widths.
