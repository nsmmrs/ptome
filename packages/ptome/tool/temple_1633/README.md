# The Temple, set as its 1633 printing sets it

The showcase's Temple (test/showcase/herbert) is George Herbert's The
Temple as Thomas Buck and Roger Daniel printed its second edition
(Cambridge, 1633), page for page and line for line, from the title page
to the titles of the poems at the end: the Internet Archive's scan of the
British Library's copy on Early English Books microfilm,
https://archive.org/details/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633.
The words are the Text Creation Partnership's transcription of the first
edition (EEBO-TCP A03058, CC0), read against the scan line by line and
corrected where the second edition prints otherwise. Each source line is
a printed line (`:source-lines:`), each page the printing's (`<<<`), each
line set in as far as the printing sets it (its own `i<tenths>` span) and
each block — a title, a stanza, a rule, a band of ornament, a page's foot
line — has its own `margin-top`, fitted so that the PDF sets it where the
scan shows it. These scripts made the text and fitted those margins; they
are kept for the record and to make them again. Python 3 with Pillow,
NumPy and fontTools; Tesseract (settle.py); Poppler's `pdftotext`,
`pdftohtml` and `pdftoppm`; a ptome executable (`dart compile exe
bin/ptome.dart`).

## The work folder

`TEMPLE_WORK` (by default `~/.cache/asciidart-work/print-match`), not
committed (`TEMPLE_HERBERT` is the work in the repository, by default
`../../test/showcase/herbert` from this folder):

- `herbert/`: the item's files from the Internet Archive (`…_hocr.html`,
  `…_jp2.zip` unpacked, their SHA-256 in the work's NOTICE.md),
  `ocr.json` (the OCR as pages of lines, `tool/alice_1867/hocr.py`),
  `A03058.xml` (the TCP's TEI, https://github.com/textcreationpartnership/A03058),
  `pagejpg/` (the page images `fetch.yml` cuts from). `paper.json` here:
  each leaf's paper on the film.
- `build/herbert/`: the work staged by `tool/showcase.dart` (its images
  cut by `stage_images.py` as `fetch.yml` cuts them); `ptome`, the
  executable `tfit.py` sets the PDF with.

The scripts write what they derive (`stream.json`, `placed.json`,
`pages.json`, `fit.json`, `ink.json`…) beside themselves; run them from a
copy of this folder in the work folder.

## Steps

1. `align.py`, `stream.py`: the TCP's lines against the scan's OCR, leaf
   by leaf; `variants.py`, `settle.py`: the words where they differ, the
   gaps filled, the rest read again by Tesseract; `sheets.py`: review
   sheets of what is left, decided by eye in `decisions.tsv` (all 371);
   `choices.json` the settled ones. `overrides.json`: lines the review
   missed (an order of words, an `▪` the TCP couldn't read, a line's
   first letter), by record.
2. `words.py` (`placed.json`): each TCP word on its scan line;
   `pages.py` (`pages.json`): each leaf's lines, their baselines from the
   ink, its running head and foot; `ornaments.py`, `rules.py`
   (`rules.json`): the bands of ornament and the rules over the poems.
3. `turns.py` (`turns.json`): the lines the printing turns up or down
   after a bracket; `catchwords.json`: the catchwords it sets otherwise
   than the next page's first word (`¶ Un-`, `§ The`).
4. `gen.py OUT margins.json`: the text, `test/showcase/herbert/text/
   temple.adoc`, and `fit.json`, each block's place on the scan; the
   pages `manual/` holds set by hand (the title page, the Printers to the
   Reader, the Dedication, the Church-porch's and the Church Militant's
   openings with their woodcut capitals, The Altar, Easter-wings, the
   Dialogue-Antheme, the titles of the poems — `index.py` writes these
   three); each line's indent where its letters' ink starts on the scan
   against the page's own edge (the film's skew and the page's curl bend
   it), a stanza's indents the poem's other stanzas' of its shape where
   the scan's are unclear; the look's indent and pitch roles.
5. `tfit.py N`: sets the PDF, reads where each block is (Poppler), moves
   its margin by how far it is off less how far the block before it on
   its page is, again until every block is within a tenth of a point
   (a rule's and a picture's within a rasterized page's half point);
   `seed_index.py` starts the index's columns near their places.
6. `compare.py`, `wraps.py`, `indents_check.py`: each page's lines against
   the scan's OCR (their places), the lines the PDF doesn't set whole,
   the indents against the scan's; `sbs.py` and `sheets_all.py`, the
   pages beside the scan, read by eye.

`index_rules.py` cuts the index's column rules from the scan in straight
pieces (their `fetch.yml` entries).
