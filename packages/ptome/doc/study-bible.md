# A study Bible page: acceptance against the RSB samples

The spike EPIC-sblfjj asked whether ptome sets a study Bible's page
natively, from units source, as the Reformation Study Bible (RSB) sets
Genesis 1 and Mark 1. This is the answer, from the corpus's study
edition (`test/units/corpus/bible/bsb-study/study.adoc`: the BSB with
OpenBible.info's cross-references and Tyndale Open Study Notes, made by
`tool/import_study_bible.dart`) set with
`test/units/corpus/themes/rsb-study-theme.yml`:

```sh
cd test/units/corpus/bible/bsb-study
ptome -b pdf -a look=reference-bible -a media=prepress \
  -a pdf-theme=../../themes/rsb-study-theme.yml study.adoc
```

The six RSB sample images are not open data: they stay out of the
repository, and so do the contact sheets made from them.

## Measured from the samples

In proportion to the page (541 px wide in the images), sized for a
6.5 in trim (the images' ratio gives 9.56 in):

| | RSB | Theme |
| --- | --- | --- |
| Text | one justified column, 363 pt; 9.5 on 11.25 (13 px pitch) | Crimson Pro 9.5, `base_line_pitch` 11.25 |
| Cross-references | inner column 37 pt, 11 pt from the text; 6 on 7.8 (9 px) | `side_notes_column: inside`, Fira Sans Condensed 6 |
| Study notes | three sans columns, 9 pt gutters; 7 on 8.65 (10 px) | note stream `sn`, 3 columns, Fira Sans Condensed 7 |
| Translators' notes | run in under the text, small | note stream `tn`, run in, 6.5 |
| Margins | outer 30 pt, head 54 pt to the first baseline, foot 23 pt | as measured, the inner 79 pt holding the reference column |
| Running heads | first verse (verso) and last (recto) on the outer edge, folio centred | `running_content_marks: v-`, capitals, letterspaced |

## The pages beside the samples

| Sample | Ours | What matches | What doesn't |
| --- | --- | --- | --- |
| Genesis 1:1–5 (p. 11) | p. 7 | drop numeral, bold verse numbers, reference column keyed by verse, notes under the text | our book introduction (Tyndale's, long) comes first; the RSB's is elsewhere |
| Genesis 1:6–25 (p. 12) | p. 9 | layout of text, references, notes | ours carries less text: Tyndale's notes are longer per verse, and the notes start on their verse's page |
| Genesis 1:26–28, feature (p. 13) | p. 11 | the feature article: a tinted box across the page between the text and the notes, its title, a drop initial, two balanced columns | the RSB's title is a dark banner in capitals; ours is centred bold |
| Mark 1:6–15 (p. 1734) | p. 24 | section heads in letterspaced capitals, the parallel passages small | our section heads have more space around them |
| Mark 1:16–34 (p. 1735) | p. 26 | as above | as above |

## Metrics (Genesis 1–3 and Mark 1, 28 pages)

- **Notes lag:** every one of the 100 study notes starts on the page of its
  verse (lag 0: 100 %), with `footnotes_lag: 0` and
  `footnotes_text_min_lines: 8`.
- **Shortest text block:** 7 lines (a page under the end of the book
  introduction); the median is 17. The RSB's pages carry about 25: its
  notes are shorter.
- **Box placement:** of the seven feature articles, two are on their
  verse's page, one on the page after, and four a page or two *before*
  their verse (BUG-3llqq1: the text, shortened for its notes after the box
  was pinned at the bottom, moves on to the next page without it).
- **Layout time:** 2.3 s for the 28 pages (compiled, this machine), notes
  in step and all.

## Verdict: what a whole study Bible needs

The engine sets the RSB's page from open data: one text column, the
reference column on the inner side, the translators' notes run in, the
feature articles across the page above the notes, the study notes in
three columns starting on their verse's page, the running heads. What
it needs for a whole Bible:

1. **Floats after their text** (BUG-3llqq1): a box pinned to the bottom
   must move on with its text when the notes shorten the text.
2. **"Chapter n" over the references** (FEAT-000j3n), so the entries can
   give the verse alone, as the RSB's do.
3. **A heading banner**: a sidebar title on a dark bar in capitals
   (`sidebar_title_background_color` or the like).
4. **Tighter section heads**: the theme's heading spacing, measured from
   the samples, not the look's.
5. **The faces installed**: these pages fall back to Times and Helvetica
   here (`ptome doctor` installs Crimson Pro and Fira Sans Condensed).
6. **Notes as dense as the RSB's**: Tyndale's notes are longer per verse
   than the RSB's, so the pages carry less text; a whole Bible from them
   runs longer. The NLT excerpts are kept as they are (TASK-dptk0f).
7. **Time**: 2.3 s for four chapters; a whole Bible of 1,189 chapters, at
   that rate, about 11 minutes, so the layout of the books in parallel
   (each book from a page boundary) is worth having.
