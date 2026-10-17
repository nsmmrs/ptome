# Byrne's Euclid, set as its 1847 printing sets it

The showcase's Byrne's Euclid (test/showcase/byrne) is Book I of Oliver
Byrne's Euclid as William Pickering printed it in 1847, page for page and
line for line: the Internet Archive's scan of the Getty Research
Institute's copy, https://archive.org/details/firstsixbooksofe00byrn,
leaves 35–84 (the book's pages 1–50). Every printed line is a paragraph
at the printing's margins, every diagram, woodcut initial and coloured
symbol is traced from the scan, and every block has its own
`margin-top`, from the scan, so that the PDF sets it where the scan shows
it. These scripts made the work and make it again. Python 3 with Pillow,
NumPy, SciPy and fontTools; potrace; Poppler's `pdftotext` and
`pdftoppm`; a ptome executable (`dart compile exe bin/ptome.dart`).

## The work folder

`BYRNE_WORK` (by default `~/.cache/asciidart-work/print-match`), not
committed:

- `byrne/`: the item's files from the Internet Archive
  (`firstsixbooksofe00byrn_jp2.zip` unpacked into `…_jp2/`,
  `…_hocr.html`; their SHA-256 in the work's NOTICE.md), `ocr.json` (the
  OCR as pages of lines, `tool/alice_1867/hocr.py`);
- `byrne/masks/rest-LEAF.png`: each leaf's ink outside its text, what the
  pictures are traced from (`seg.py --masks`);
- `byrne/svg/`, `byrne/traced.json`: the tracings (`trace.py`);
- `byrne/build/`: the work's PDF and its pages; `byrne/rev/`: the sheets
  and comparisons below.

`venv/` there has the Python packages (`PYTHON` names another Python),
`ptome` the executable (`PTOME`).

## The steps

1. `seg.py` divides each leaf into its running head, its words (the
   OCR's, cut to their letters) and the components of the ink outside
   them, each counted by ink: yellow, red, blue and black, by hue
   (`classify`). `group.py` groups the components into lines' symbols,
   diagrams and the woodcut initial. Their outputs, frozen once the
   transcription began, are `seg-frozen.json` and `groups-frozen.json`
   (each line keyed by its baseline in the scan's pixels);
   `inks.json` recounts the components' inks by the present `classify`
   (`inks.py`), `heads.json` measures each running head from its ink
   (`heads.py`).
2. `review.py LEAF…` draws a sheet of each leaf's lines, their symbols
   numbered (`byrne/rev/sheet-LEAF.png`), and prints a draft of each
   line; `comps.py LEAF…` numbers every component on the page
   (`comps-LEAF.png`), `band.py` and `inkbox.py` list what is where.
3. `text.tsv` is the work's text: each line's words as the printing has
   them and its pictures, decided by eye against the sheets and the scan
   (its header and `pieces.py` give the notation: `{n}` the line's n-th
   symbol, `{c4+c9}` components, `{#x0,y0,x1,y1=alt}` all the ink in a
   box, `@skip`, `@at`, a diagram's `@drop`, a leaf's `initial`, a line
   the grouping missed).
4. `run.sh [LEAF…]` traces the pictures (`trace.py`), generates the work
   (`gen.py`: `text/book-1.adoc`, `images/` and `byrne-look.yml` from
   `look-base.yml` with each line's margin and tracking roles), builds the
   PDF and compares each page with its scan (`compare.py`: the scan, the
   page and their blend, `cmp-LEAF.png`, and in colour, `cmpc-LEAF.png`),
   and checks that every line is set on one line where it should be
   (`check.py`).

`overlay.py`, `words.py`, `blends.py` and `stale.py` are aids for the
same review.
