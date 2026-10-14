# PDF output

`ptome -b pdf` writes a PDF with Ptome's own PDF library, plain_pdf,
and reads asciidoctor-pdf's YAML themes unchanged (`pdf-theme`,
`pdf-themesdir`, `pdf-fontsdir`). It needs an output file, and sets text
in the fonts installed on the machine (`ptome doctor` installs the
built-in themes'; see [Fonts](#fonts)). The API makes PDFs too, on the Dart
VM, on Node.js and in a browser (see `doc/api.md`).

It lays documents out with Ptome's own typesetting, described below.
With `asciidoctor-compat` (or `-a pdf-compat`), its settings default to
asciidoctor-pdf's look instead (next section; ADR-0015).

## asciidoctor-pdf's look

With `asciidoctor-compat` naming the PDF (ADR-0015; `doc/books.md`), a
document without a theme of its own gets asciidoctor-pdf's (`default`),
and these keys default as asciidoctor-pdf sets pages, unless the theme
sets them. On asciidoctor-pdf's own test documents, the pages look the
same (`benchmark/PARITY.md`).

| Key | With `asciidoctor-compat` | Otherwise |
| --- | --- | --- |
| `block_margin_collapse` | `false`: spaces add | `true` |
| `base_line_breaking` | `segments` | `auto` |
| `base_hyphens` | `false` (unless `:hyphens:`) | justified text hyphenated |
| `prose_orphans`, `prose_widows`, `code_orphans`, `code_widows` | `1` | `2` |
| `block_split_end` | `region` | `content` |
| `code_highlight` | `none` | `colors` |
| `code_wrap_indent` | `0` | `1em` |
| `code_wrap_marker` | `none` | `arrow` |
| `footnotes_placement` | `end` | `page` |
| `toc_macro_in_section` | `false` | `true` |
| `running_content_on_openers` | `true` | `false` |
| `running_content_layer` | `over` | `under` |
| `page_layer_clip` | `page` | `none` |
| `base_glyph_widths` | `thousandths` | `exact` |
| `base_kerning_source` | `kern_table` | `font` |
| `base_text_shaping` | `right_to_left` | `full` |
| `base_font_embedding` | `simple` | `composite` |
| `url_breaks` | `delimiters` | `chicago` |
| `base_slash_breaks` | `false` | `true` |
| `index_terms_paragraph` | `line` | `none` |
| `svg_placement` | `page_origin` | `exact` |
| `table_borders` | `with-cells` | `above` |
| `table_cell_margin_top` | `keep` | `drop` |
| `example_collapsible` | `details` | `frame` |
| `stem_math` | `source` | `typeset` |

## The modern engine

Its default theme is the document's look (`doc/looks.md`), Ptome's
house look unless the document names another (`ptome`, `doc/style.md`):
asciidoctor-pdf's default with a shorter measure, more open lines,
headings in the sans, code in a tint and tables with rows only.
`pdf-theme` names a theme instead (`pdf-theme=ptome` is the house look's).
`-a pdf-theme=default` is asciidoctor-pdf's theme; a theme of your own
`extends: ptome` or `extends: default`.

Every setting has a default. Each one is a key of the theme (as written
in the YAML, `prose_orphans` is `prose: { orphans: 2 }`) or an attribute
of the document. A key that takes one of a set of values
(`image_placement`, `base_line_breaking`...) reports a value it doesn't know, once,
and is read as unset.

Text the engine generates (a heading's label, a running head, a contents
entry, a callout marker) comes from templates where a book may want it
otherwise: Mustache templates (ADR-0010), `{{name}}` for a value and
`{{#name}}...{{/name}}` for a part written only when the value is set. A
template may hold the text markup (`<font>`, `<strong>`, `<sup>`); a
newline is `\n` in a double-quoted YAML string. `<font width="0.3em">&nbsp;</font>`
sets a space of that width (a length, `em` of the text's size), which the
line breaker never stretches: a fixed gap between a heading's number and
its title.

### Paragraphs

| Key | Default | What it does |
| --- | --- | --- |
| `base_glyph_widths` | `exact` | How wide a glyph is: `exact`, its advance in the font; `thousandths`, its advance in whole 1000ths of the em, truncated, both where lines are measured and in the widths the PDF gives viewers. |
| `base_text_shaping` | `full` | Which text is shaped by its font's layout tables in full, as HarfBuzz shapes it (see "Scripts"): `full`, text with marks and every script but Latin, Greek and Cyrillic; `right_to_left`, right-to-left text alone, every other script set by its glyphs, ligatures and kerning, as Prawn sets it. |
| `base_kerning_source` | `font` | Which pairs kern text: `font`, the font's GPOS pair adjustments (its `kern` feature), else its `kern` table; `kern_table`, the first subtable of its `kern` table alone, as early font engines read it. |
| `base_font_embedding` | `composite` | How fonts with TrueType outlines are embedded: `composite`, a Type0 font a face (two bytes a glyph, by glyph id); `simple`, simple TrueType fonts of up to 256 glyphs each (a byte a glyph, the space code 32 in each, so a justified line's word spacing is the `Tw` operator's rather than adjustments between the words). Either way the text extracts through a ToUnicode map. |
| `base_line_breaking` | `auto` | How lines break: `auto` breaks justified and left-aligned text where the lines' demerits are least (Knuth and Plass's total fit with TeX's costs: even spacing, few hyphens, never two hyphens in a row if it can help it; ragged lines with even ends, as plain TeX's `\raggedright`) and centered or right-aligned text one line at a time; `optimal` optimizes any text; `greedy` fills one line at a time; `segments` fills one line at a time as Prawn's line wrap does (at every space, before and after a hyphen, a word that runs across a style change moved only from that change on, soft hyphens alone hyphenating). Otherwise a style change inside a word is never a break. |
| `base_leading` | none | Lines measured from cap height to baseline: each line's box runs from its tallest cap height to its baseline, with this space between boxes (`0.6em`, or points); a text's first line has its cap height at the top and its last line ends at its baseline, so the margins between blocks are the visible space between their text (CSS's `text-box-trim` and `text-box-edge: cap alphabetic`). In place of `base_line_height`; a category's own (`title_page_title_leading`, `code_leading`...) for its text. |
| `base_overhang` | `0` | How far a justified line's last character hangs into the margin, so the edge looks straight (margin kerning, Hàn Thế Thành's character protrusion): the line stretches into a part of the character's width, as LaTeX's microtype package's default protrusion has it (0.7 of a period; 0.5 of a comma, colon or hyphen; 0.3 of a semicolon; 0.2 of an en dash, 0.15 of an em dash; a little of some letters), times this amount. `1` (or `true`) hangs them that far, `0.5` half as far, `0` (or `false`) not at all. |
| `base_typographic_scripts` | `false` | Superscripts and subscripts (footnote references) in the font's own glyphs for them (its `sups` and `subs` features) at the text's size, when it has them for every character (true superior and inferior figures); else smaller and raised as usual. |
| `base_justify_width` | room | `widest`: justified lines are set to the width of the paragraph's widest line (an overfull line shrunk to the room), as a paragraph in a block sized to its content is (CSS's `width: fit-content`); in a quote or a section role: `quote_base_justify_width`, `section_role_<role>_base_justify_width`. |
| `base_kashida` | `0.5em` | Justified Arabic is lengthened inside its words before its spaces widen: tatweel drawn between two joined letters, each word at its best place by Microsoft's ranking for Arabic justification (after a Seen or Sad; before a final Teh Marbuta, Heh or Dal; before a final Alef, Tah, Lam, Kaf or Gaf; before a medial Beh ending in Reh or Yeh; before a final Waw, Ain, Qaf or Feh; before any final letter), never inside Lam-Alef or a Nastaliq word's cascade. The value is how far each word may be lengthened (`1em`, or a number of em); the spaces take what is left; `false` for none. The text read from the page has no tatweel. Modern engine; not under `asciidoctor-compat`. |
| `base_word_break` | `auto` | Whether a line breaks inside a word written without spaces between its letters, as CSS's `word-break`: `keep-all` breaks only at spaces and punctuation (a word wider than the line between its characters all the same), `normal` wherever UAX #14 allows (between any two Han characters, kana or Hangul syllables). `auto` keeps Korean words whole (text whose language is `ko`: KLREQ 7.1.1 leaves the choice to the author, by words the common one), the rest `normal`. Modern engine; not under `asciidoctor-compat`. |
| `base_text_align_last` | `left` | Where a justified paragraph's last line, and each line before a hard break, goes (`center`, `right`), as CSS's `text-align-last` (`table_base_text_align_last: center`: table cells justified, their last lines centered); `justify` stretches them to the measure too, so text broken line for line by hand fills each line (a mushaf, see `doc/mushaf.md`). |
| `prose_orphans` | `2` | The fewest lines of a paragraph left at the bottom of a page. |
| `prose_widows` | `2` | The fewest lines of a paragraph carried to the top of the next page. |
| `prose_text_indent` | `0` | The indent of every paragraph's first line. Numbers are points; `1.5em` is relative to the paragraph's font size, `2rem` to the base font size. |
| `prose_text_indent_inner` | `0` | The indent of the first line of a paragraph that follows another paragraph only (not the first after a heading, a list or a block), as books set it. |
| `prose_margin_inner` | none | The space between two paragraphs; `0` with `prose_text_indent_inner` for indented, unspaced paragraphs. |
| `role_<role>_text_indent`, `role_<role>_margin_bottom` | the prose's | A paragraph with the role: its first line's indent (`0` for none) and the space below it (`[.dedication]` paragraphs, unindented and spaced). |
| `role_<role>_text_emphasis`, `role_<role>_text_emphasis_position` | none, `over` | Emphasis marks on text with the role (`[.bouten]##強調##`), as CSS's `text-emphasis`: `sesame` (Japanese bouten), `dot` (Chinese), `circle`, `double-circle`, `triangle`, each `filled` (the default) or `open` (`open sesame`), or a character of the font; set over each character but spaces and punctuation, centered, just past the em box; `under` for under them (Chinese). The line makes room for them; they read as nothing when text is taken from the page. |
| `role_<role>_hyphens` | the document's | `false`: a paragraph with the role isn't hyphenated (an agency's name in capitals). |
| `role_<role>_margin_top`, `role_<role>_margin_bottom` | the block's | Any block with the role: the space above and below it, in place of its category's. |

### Space around blocks

Each kind of block has its own space above and below:
`<category>_margin_top` and `<category>_margin_bottom`, for the
categories `prose` (paragraphs), `code` (listing and literal blocks),
`image`, `media`, `table`, `quote`, `verse`, `sidebar`, `example`,
`admonition`, `list`, `description_list`, `callout_list`, `open`,
`thematic_break`, `pass` and `stem`. Below a block, the space is its own
or `block_margin_bottom` (asciidoctor-pdf's one setting for all blocks),
and at least the space the next block wants above it: adjacent margins
collapse to the larger, as in CSS, also with the space above the next
section's heading. Above the first block after a heading, what the
heading's margin below leaves; none at the start of another container,
or at the top of a page. `block_margin_collapse: false` adds them
instead, as asciidoctor-pdf does: a block's space below, then the next
heading's space above, and no `<category>_margin_top`. A block that ends with a page break ends there:
none of its space below goes to the next page.

A quote's attribution has its own space above (`quote_cite_margin_top`,
`verse_cite_margin_top`; `block_margin_bottom` by default) and alignment
(`quote_cite_text_align: right`). Inside a quote, a sidebar or a
description list, its category's keys stand for the theme's, as a section
role's do (`sidebar_prose_margin_bottom`):
`quote_base_justify_width: widest` (its lines justified to the widest, as
in a block sized to its content),
`quote_list_margin_top` for the lists in a quote. An admonition's keys
stand in the same way (`admonition_prose_margin_bottom`). A sidebar's
title has its own space below (`sidebar_title_margin_bottom`;
`heading_margin_bottom` by default).

A framed block split across pages (a sidebar, an example, a quote, a
section with a styled role) is open where it breaks: its border and
padding at the start of its first piece and the end of its last, as
asciidoctor-pdf does. `<category>_box_decoration_break: clone` gives every
piece its padding and border at both ends instead, as CSS's
`box-decoration-break: clone`.

### Contents, lists, title page

A `toc::[]` macro that opens a section (its first block) is that
section's contents: under its heading, on its page, without a title of
its own, and the section listed in itself: a Contents chapter.
`toc_macro_in_section: false` sets it as asciidoctor-pdf does instead: on
a page of its own after the heading, with its title.

| Key | Default | What it does |
| --- | --- | --- |
| `toc_entry_content` | the numbered title | A template for each contents entry: `'{{title}}'` lists titles without their numbers (also `{{number}}`, `{{numbered-title}}`). |
| `toc_entry_spacing` | the leading under `base_leading`, else none | The space between contents entries. |
| `description_list_term_display` | `block` | `inline` runs a term in before its description, in the term's font, the lines after the first hanging by `description_list_description_indent`. |
| `description_list_term_gap` | an en space | With `inline` terms, the space after the term (a length, `0.6em`). |
| `description_list_term_suffix` | none | With `inline` terms, text after each term (`':'`: a Federal Register caption, `AGENCY:`). |
| `image_float_clearance` | none | The space between a floating image (`image_placement`) and the text: below it at the top of a page, above it at the bottom (a length, `1.5em`). |
| `olist_text_align` | `list_text_align` | An ordered list's text alignment (`justify` for numbered lists justified while bullet lists stay ragged). |
| `callout_list_text_align` | `list_text_align` | A callout list's text alignment. |
| `olist_body_indent`, `olist_marker_width` | `list_body_indent`, the marker's | An ordered list's space between its numbers and its text, and the boxes its numbers are set in, at their left (`0`, `1em`: the text right after a 1em box), or `auto` for each number's own width. |
| `olist_role_<role>_<key>` | none | For an ordered list with the role (`[.plain]`), replaces `olist_<key>` (`olist_role_plain_marker_width: auto` sets its numbers at their own width). |
| `ulist_marker_nesting` | `all` | `ulist`: a bullet list's marker follows its level among bullet lists alone (a bullet list in a numbered list's item keeps the first marker); `all` counts every enclosing list, as asciidoctor-pdf does. |
| `callout_list_indent`, `callout_list_marker_width`, `callout_list_marker_text_align` | none, the marker's, `center` | A callout list set in, its markers in boxes that wide, aligned so (`12`, `1em`, `left`: callouts set as a numbered list); `callout_list_marker_font_*` (family, size, style, color, `_variant_numeric`) style them. |
| `caption_indent`, `<category>_caption_indent` | none | A caption set in from the left (`code_caption_indent: 12`: over a code block's padded code). |
| `olist_marker_font_variant_numeric` | none | An ordered list's numbers in old-style (`oldstyle-nums`) or other figures (with `olist_marker_font_family`, `_font_color`...). |
| `title_page_authors_delimiter` | `, ` | Its spaces are kept as written: `'    '` sets the authors in a row with a gap (asciidoctor-pdf collapses them to one). |
| `list_body_indent` | none | The marker at `list_indent`, the text this far after the widest marker (else the text at `list_indent`, the marker a space before it, as asciidoctor-pdf). |
| `title_page_title_skew` (also `_subtitle_`, `_authors_`, `_revision_`) | none | Degrees the text leans right, sheared as one block about its last baseline (the upper lines further right), in place of a slanted face. |
| `role_<role>_drop_lines` | none | A paragraph with the role (`[.dropcap]`) set with its own first letter as an initial that many lines deep (2 or more), sized from its cap height to the baseline of its last line; opening punctuation before the letter goes with it, hung left of the text's edge; a paragraph shorter than the initial is as deep. `role_<role>_drop_font_*` and `_drop_gap` style it as a heading's drop; `role_<role>_drop_lead_in` (a number of words) puts the words after it in the role `lead-in` (`role_lead-in_font_variant: small-caps`). Not under `asciidoctor-compat`. |
| `columns_count`, `columns_gap` | `2`, `page_column_gap` | A section or open block with the role `columns` (`[.columns]`) sets its content in that many columns (its `column-count` attribute sets its own), from where it starts on the page, balanced where it ends: the last column at most a line shorter than the first, what follows starting under them. Footnotes go to the page's foot. Not under `asciidoctor-compat`. |
| `heading_number_placement`, `heading_h<n>_number_placement` | `inline` | Where a heading's number goes, the first `[.number]` span of its title (a unit scheme's title template writes it: `[.number]#{{section}}# {{title}}`): `hang`, left of the title's edge (the title's lines start at the text's edge); `line`, on a line of its own over the title. |
| `heading_number_hang`, `heading_h<n>_number_hang` | `2.5em` | How far left of the title's edge a hung number starts (its width and half the font size, when that is more). |
| `title_page_inline`, `title_page_inline_margin_bottom` | `false`, 1.5 × the base font size | `true`: an article without a title page (no `title-page` attribute) sets the title page's slots (`title_page_recto`) at the top of its first page in place of the document title, across its columns, with that space after them: a magazine piece's kicker, head, dek and byline. Not under `asciidoctor-compat`. |
| `base_word_spacing` | `100%` | The spaces between words in the paragraphs the engine sets, as a percentage (or a fraction) of the face's own space: a dictionary's close-set entries at `72%`. They stretch and shrink in proportion. Not under `asciidoctor-compat`. |
| `base_font_expansion`, `base_hyphenate_limit_lines` | none | Microtypography for justified text: `true` (2%) or a fraction lets the line breaker set a line's letters that much wider or narrower besides its spaces, unpenalised, as pdfTeX's font expansion with microtype's 20 thousandths (Hàn Thế Thành, 2000): fewer loose and tight lines. `hyphenate_limit_lines` is the most hyphenated lines in a row (the Chicago Manual of Style's three; TeX only makes them costlier). With `base_overhang`, a justified line's first character hangs at the left too, as microtype's left protrusion: a hyphen by half its width, an opening quote three tenths, A T V W X Y a twentieth; and the line breaker counts what hangs when it chooses the breaks, as pdfTeX's `\pdfprotrudechars=2`. `base_last_line_min_width` (`33%`, or a fraction) is the least a paragraph's last line fills of its measure: a shorter one, a runt, only when there's no other way, the emergency stretch tried first. Not under `asciidoctor-compat`. |
| `<category>_letter_spacing` (`heading_h2_`, `role_<role>_`, `title_page_title_`…), `caps_letter_spacing` | none | Tracking: the space added after each letter, a length or ems (`0.05em`), half of it before the first and after the last (microtype's outer kerning), word spaces widened with it. `caps_letter_spacing` tracks every word in capitals (two letters or more) and small capitals by itself, as microtype does when it letterspaces (0.05 em): a kicker, an acronym, running heads in small capitals. A look's `tracking`. Not under `asciidoctor-compat`. |
| `note_streams`; `note_stream_<name>_*` | none | The units note streams (`note:x[…]`, `doc/units.md`) set at the foot of the page apart from the footnotes, in this order under them: each under its own separator, by its caller, styled by its own `note_stream_<name>_*` keys as the `footnotes_*` keys style the footnotes (`_font_size`, `_separator_length`, `_item_spacing`…), in `_columns` (1) `_column_gap` apart, balanced: a critical apparatus, the translators' notes of a Bible. `_arrangement: run_in` sets a page's notes of the stream one after another in one paragraph (`_run_in_separator`, an em space, between them; in a face without its characters, as many no-break spaces as make its width), as an apparatus is set. A stream's references and labels follow its own `_reference_content` and `_label_content` (`''`: none, as an apparatus has no marks in the text). A note that opens with a heading, `[.heading]#The Days of Creation#`, has it on a line of its own above it, kept with it (`_heading_*`, italic by default; `_heading_margin_top`): a study Bible's subheads among its notes; so does a footnote (`footnotes_heading_*`). Notes left over at the foot of a page go on at the foot of the next in their own stream, under its separator, in its columns (a run-in stream's notes run in with the next page's). `_column` (`left`, `right`, `outside`, `inside`) sets the stream in a margin column of its own instead, each note level with its reference (pushed down under the one before, carried to the next page when there's no room), `_column_offset` from the text and `_column_width` wide: a Talmud page's commentaries, one stream to a margin. The footnotes are numbered without them. Not under `asciidoctor-compat`. |
| `line_numbers_interval`, `_restart`, `_side`, `_gap`, `_font_*`, `_grid_pitch` | `1`, `page`, `left`, the font size, 0.8 × the font size, a body line | With the document attribute `line-numbers` (`typeset`, the default; `logical`; `grid`), the body's lines are numbered in the margin (`left`, `right`, `outer`, `inner`), every `interval`th line, counting from 1 again on each page, at each first-level section (`section`) or never (`none`): `typeset` counts the lines the text is set in (headings too, as a bill's), `logical` the source's (a verse line that wraps counts once, numbered where it starts), `grid` a fixed grid down the text area, `grid_pitch` apart (pleading paper). `line_numbers_rule` (`single`, `double`) draws a vertical line between the numbers and the text down the page, as pleading paper separates them (`_rule_width`, 0.5; `_rule_color`, the text's). `line_numbers_align` (`left`, `right`) sets the numbers flush left or right in a column `line_numbers_width` wide (two figures' room, 1.2 × their size, by default), its near edge `gap` from the text; unset, they align toward the text (as a UK bill's sit flush right in the right margin with `align: right`). Notes and the title page aren't numbered. `line_numbers_restart_units` (a units level, `section` or `stephanus.section`) starts the count again at each unit of that level and sets its label beside its first line, as Burnet's Plato counts from each Stephanus section (`2a`) and a Bekker edition from each column. Not under `asciidoctor-compat`. |
| `page_writing_mode` | the document's `writing-mode`, else `horizontal-tb` | `vertical-rl`: the body's lines run down the page, each following to the left of the one before (Japanese, Chinese); `vertical-lr`: to the right (Mongolian). See "Vertical writing". Not under `asciidoctor-compat`. |
| `page_frame_width`, `_gap`, `_color`, `_offset` | none, the thickest rule, the text's color, the font size | Rules framing the text area of every page (not a cover): a width, or widths from the outside in (`[4, 1]`, the Oxford rule's thick and thin), the gap between them, the outermost that far outside the text area. Not under `asciidoctor-compat`. |
| `footnotes_text_min_lines`; `footnotes_lag` | none | Notes in step with their text, as a study Bible's are, far longer than its verses. A page with notes keeps at least `footnotes_text_min_lines` lines of body text (by default a quarter of the page, and when even that much text's notes don't fit, the text fills the page and its notes go on after it), its notes under it as far as they go and the rest at the foot of the next pages. `footnotes_lag` (pages) is how far after its reference's page a note may start: the text of a page stops where the notes it refers to would start later than that (0: every note on its reference's page, as far as the least lines allow). They apply to the footnotes and the note streams together. Not under `asciidoctor-compat`. |
| `pagination` | `first_fit` | `optimal`: the pages' breaks chosen together over the whole document, after Plass's optimal pagination (1981): of every way to break the pages that keeps the widow, orphan and keep-together rules, the one that leaves the least room unused (the square of each page's, the last page's free), so a block kept whole that doesn't fit leaves a little room on several pages rather than one nearly empty page. A document with footnotes, blocks floating, page columns, tables taller than a page or a change of page layout is laid out first-fit. Not under `asciidoctor-compat`. |
| `base_text_engine` | `paragraph` | Who sets the modern engine's text: `paragraph`, plain_typesetting's paragraphs, for every text it sets (body paragraphs, list items, table cells, headings, captions, the table of contents, title pages, footnotes, wrapped source listings); a plain paragraph is a paragraph box the layout breaks and places itself where nothing it doesn't do yet is in play (protrusion, font expansion, `base_text_align_last`, a baseline grid, a float to run around, labels, side notes), and paragraph content the converter places otherwise. Every text it sets is the engine's: an abstract's first line in its own style (transformed, shrunk to fit), drops, cells with lines from their cap heights, fixed-width spans and notes numbered by page included. `box`, this converter's text box for all of it. Not under `asciidoctor-compat` (the text box). |
| `page_margin_canon`; `page_margin_div`, `page_margin_bcor`; `page_margin_profile`; `page_margin_whole_lines`; `page_margin_gutter` | none | Margins from a rule rather than `page_margin` (inner on a recto's left; with `media=prepress` each page's inner side): `page_margin_canon: n`, the classical canon, inner W/n, outer 2W/n, head H/n, foot 2H/n of the page's width and height (9: Van de Graaf's, Tschichold's); `page_margin_div: n`, KOMA-Script's type area, the page less `page_margin_bcor` (the binding's allowance) in n stripes each way, inner one stripe and the allowance, outer two, head one, foot two, the foot then as much larger as makes the text area hold whole body lines (as `page_margin_whole_lines: true` does for any of these); `page_margin_profile`, margins measured from books: `university-press` (6×9 in: inner 0.79, outer 0.83, head 0.88, foot 1 in), `ucl-press` (inner 0.94, outer 1.11 in), `trade` (5.5×8.5 in: the gutter 1.3 times the fore-edge). `page_margin_gutter: kdp` (with `media=prepress`): the inner margin at least KDP's for the book's page count (24–150 pages 0.375 in, to 300 0.5, to 500 0.625, to 700 0.75, more 0.875), the book laid out again when its count calls for more. With `media=prepress` a rule's inner and outer margins come before `page_margin_inner` and `_outer` (which asciidoctor-pdf's default theme sets). Not under `asciidoctor-compat`. |
| `thematic_break_content`; `thematic_break_content_display` | none; `always` | A thematic break as a mark rather than a rule: `content` a template (a dinkus `* * *`, a fleuron `❦`, an image), centered in `thematic_break_font_*`, the break's padding around it. `content_display: boundary`: the break is blank space, but a mark (`* * *` without a content of its own) where it falls at the top or the bottom of a page, where space alone wouldn't show that a part ends (Penguin's rule); on a baseline grid it keeps to the grid, one line deep. `thematic_break_margin_bottom`, when given, is the space after it in place of `block_margin_bottom`. Not under `asciidoctor-compat`. |
| `base_line_pitch` | none | The body's lines this far apart (a length), whatever the face's height: the line height that gives it, measured from the face. A pleading's double spacing is 24 pt. Not under `asciidoctor-compat`. |
| `<category>_line_pitch` (`heading_`, `heading_h<n>_`, `footnotes_`, `role_<role>_`…) | none | That category's lines this far apart, as `base_line_pitch` sets the body's: a Federal Register heading's two lines 10 pt apart in a face whose own lines are farther. Not under `asciidoctor-compat`. |
| `role_<role>_grid_line` | none | With `page_baseline_grid`, a paragraph with the role starts on that line of the page's grid (from 1), or the next one when it is past it: a pleading's court title on line 8 of its first page, whatever is above it. Not under `asciidoctor-compat`. |
| `page_baseline_grid` | none | `true` (or a length, the step): the body text's baselines keep to a grid, a body line's pitch apart, the first where a body line at the top of the page has its baseline. Each paragraph (a heading, a list item's text) starts where its first baseline falls on a line of the grid, the space before it rounded up to that (as SILE and ConTeXt do), so its lines, a body line apart, are on the grid too, in every column and on every page: lines matched on the two sides of a leaf, so that on thin paper the show-through falls between the lines (a Bible on 28–45 gsm paper). Text set larger or smaller (a lead, a note) is off the grid within itself; what follows it is back on. A look's `page: { grid: true }`. `page_baseline_grid_offset` puts the grid's first line that far below the top of the page's text instead, whatever the face (a US bill's first baseline 88 pt down the page). `page_baseline_grid_anchor: first_line` starts each page's grid at its first line instead: a US bill's page that opens with a section heading, set smaller and so higher, holds 26 numbered lines where others hold 25. Not under `asciidoctor-compat`. |
| `page_columns_balance` | `false` | `true`: the page columns of an article's last page as even as they can be, as a magazine piece ends. |
| `page_column_rule_width`, `page_column_rule_color` (also `columns_rule_*`) | none, `base_border_color` | A rule between the page's columns (or a `[.columns]` block's, which take the page's when they have none of their own) that have content, down the taller of the two. Not under `asciidoctor-compat`. |
| `title_page_recto`, `title_page_verso` | the title, subtitle, authors, revision and logo; none | The title page's slots, in order (after DocBook XSL's title page templates): a part's name (`title`, `subtitle`, `authors`, `revision`, `logo`), or a mapping of `content` (a part) or `attribute` (a document attribute's value, `copyright`), with `role` (its font from `role_<role>_*` over the part's), `margin_top`, `margin_bottom` (over `title_page_<part>_margin_*`), `before` (text before it) and `separator` (between authors, or the revision's number and date). Slots the theme lists are placed by their margins (`title_page_title_top` is the default order's); a verso is the page after the title page. A look writes them as `templates.title-page` (`doc/looks.md`). |

### Hyphenation

Justified text is hyphenated in the document's language (`lang`, else
US English), with the hyph-utf8 patterns for 72 languages
(the plain_hyphenation package). Code spans and bare links are left whole.

| Setting | What it does |
| --- | --- |
| `:hyphens!:` (or theme `base_hyphens: false`) | Turns hyphenation off, of justified text too. |
| `:hyphens:` (or theme `base_hyphens: true`) | Hyphenates all text, not only justified text, in the document's language. |
| `:hyphens: de` (or `base_hyphens: de`) | Hyphenates all text in that language. A language without patterns is reported. |

### Scripts

Text is shaped as HarfBuzz 14.6 shapes it: the font's tables for the
text's script (its OpenType script tags, as HarfBuzz picks them), the
script's shaper, normalization to what the font has (a letter and its
accents composed, or decomposed and the accents placed), then the
substitutions and positions of the font's features in their stages.
Each script below is checked glyph for glyph against HarfBuzz in Noto
fonts (plain_typesetting's `test/harfbuzz_scripts_test.dart`). A script
written right to left is always shaped right to left, so it measures as
wide as it is set.

| Script | Languages | Notes |
| --- | --- | --- |
| Latin, Greek, Cyrillic | European languages, polytonic Greek, Vietnamese, Church Slavonic | Text without marks keeps the simple path (its glyphs, ligatures and kerning, as asciidoctor-pdf sets it); with combining marks it is shaped in full. |
| Armenian, Georgian, Coptic, Ge'ez (Ethiopic) | Classical and modern Armenian, Georgian, Coptic (overlined nomina sacra), Ge'ez and Amharic | Shaped in full (contextual numerals, ligatures). |
| Arabic, Hebrew | Arabic, Persian, Urdu (in Naskh and in Nastaliq, its words' cascades set on their lines); Hebrew with points and cantillation | Joining forms, right to left (below). |
| Syriac | Classical Syriac (the Peshitta) in Estrangela, Eastern and Western | Joining forms with Alaph's and Dalath-Rish's own, vowel points, right to left. |
| Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam | Sanskrit (Vedic accents too), Pali, Hindi, Marathi, Nepali, Bengali, Punjabi, Gujarati, Odia, Tamil, Telugu, Kannada, Malayalam | HarfBuzz's Indic shaper: syllables, the base consonant, pre-base matras, reph, conjuncts and half forms; fonts of the second specification (`dev2`) and of the first (`deva`); a dotted circle where a syllable is broken or a vowel sequence is prohibited. |
| Sinhala, Tibetan, Mongolian, N'Ko, Javanese, Balinese and the other scripts of the Universal Shaping Engine | Sinhala and Pali, Tibetan, Mongolian (set across, its letters on their sides, as horizontal Mongolian is), N'Ko, Javanese, Balinese | HarfBuzz's Universal Shaping Engine: its syllables and feature groups, repha and pre-base glyphs reordered, the joining scripts' forms. |
| Khmer, Myanmar | Khmer, Burmese, Mon, Shan | Their own shapers: Coeng and Ro, kinzi, medial Ra and left vowels reordered. Lines break between words (below). |
| Thai, Lao | Thai, Lao | SARA AM decomposed, its nikhahit over the marks before it. Lines break between words (below). |
| Hangul | Korean, Middle Korean | Jamo composed into the syllable the font has, or set as conjoining jamo; tone marks before their syllable. |
| Han, Hiragana, Katakana, Bopomofo | Japanese, Chinese | Shaped by the font's tables (its `halt`, `palt` and vertical forms checked against HarfBuzz); composed as JLREQ and CLREQ have it (below). |

The text's language chooses its fonts' forms: many fonts carry several
languages' letterforms (an OpenType language system and its `locl`
substitutions), and the document's `lang`, a block's own `lang`
attribute (`[lang=zh-Hant]` above a paragraph) or a span's
(`[lang=ja]#直#`, Ptome's syntax; `[.role,lang=sr]#…#` with a role)
selects them as HarfBuzz does from the BCP 47 tag: in one Noto CJK font,
Japanese, Simplified, Traditional (`zh-Hant`, `zh-TW`) or Hong Kong
(`zh-HK`) Chinese forms; Serbian and Macedonian Cyrillic (`sr`, `mk`);
Marathi and Nepali Devanagari (`mr`, `ne`); Urdu and Sindhi digits
(`ur`, `sd`). Not under `asciidoctor-compat`, where Asciidoctor's text is
set as Prawn sets it.

The theme's `text_transform` (`uppercase`, `lowercase`) follows the
text's language where Unicode tailors case mapping: Turkish and Azeri
(`tr`, `az`) upper-case `i` to `İ` and lower-case `I` to `ı`; Lithuanian
(`lt`) keeps the dot of `i` under an accent.

Thai, Lao, Khmer and Burmese are written without spaces between words,
so a line may break between any two of a run's words, found as ICU 78.3
finds them: its word lists (plain_unicode's `dictionaryBreaks`, checked
against ICU's line breaks), the reading that lets the most words follow
chosen, a letter no word starts with joined to the word before, never a
break before a combining mark. (`base_line_breaking: segments`, as
asciidoctor-pdf, breaks only at spaces.)

Japanese and Chinese are composed as the W3C's JLREQ and CLREQ describe:
of two full-width punctuation marks in a row, one is set half wide (the
font's own half-width metrics, `halt`), so `」「` and `。」` don't leave a
full em's blank; a quarter em separates Han or kana from Latin letters
and digits (`PDF の`, `2026 年`); a justified line stretches between its
characters; and no line starts with a closing mark, a full stop, small
kana or the prolonged sound mark, nor ends with an opening bracket
(UAX #14). Thai, Lao, Khmer and Burmese lines stretch between their
words. Modern engine.

Korean wraps between words (eojeol), at its spaces, not between any two
syllables as UAX #14 allows; `base_word_break` chooses (below).

Chinese punctuation follows the document's (or block's, or span's)
region, as CLREQ describes it: in mainland Chinese (`zh`, `zh-Hans`,
`zh-CN`, `zh-SG`) marks sit in the character's corner, two in a row are
squeezed as in Japanese, and a closing mark or stop ending a line is set
half wide (GB/T 15834-2011 5.1.10); in Hong Kong (`zh-HK`, `zh-MO`,
`yue`) commas and stops sit centered and whole, only brackets squeezed;
in Taiwan (`zh-TW`, `zh-Hant`) every mark stays centered and full width.
A Noto CJK font gives each region its own forms of the marks by the
language (above). Not under `asciidoctor-compat`.

Ruby (furigana, zhuyin) is Ptome's `ruby:` macro: `ruby:漢字[かんじ]` sets
the reading over the whole base (group ruby); readings separated by
spaces, as many as the base's characters, go each over its character
(mono ruby: `ruby:東京[とう きょう]`). The reading is half the text's size,
centered on its base and resting on its em box, the base spaced out where
the reading is wider, the line as tall as it needs; the base alone is
copied from the page. HTML and EPUB write `<ruby>` (with `<rp>`
parentheses), DocBook and man pages the reading in parentheses after the
base. Under `asciidoctor-compat` (any format) the macro is text, as
Asciidoctor leaves it; `\ruby:` escapes it.

Hyphenation (`:hyphens:`, the document's `lang`) works in every script
hyph-utf8 has patterns for: Hindi, Marathi, Sanskrit, Bengali, Assamese,
Punjabi, Gujarati, Odia, Tamil, Telugu, Kannada, Malayalam, Coptic,
Georgian, Ethiopic, Thai and polytonic Greek among the shaped ones. Each
place leaves two halves that shape on their own (no conjunct divided,
no vowel sign cut from its consonant), the hyphen drawn at the line's
end; a decomposed word is hyphenated as its composed form.

### Vertical writing

With `page_writing_mode: vertical-rl`, a page's body is set as Japanese
and Chinese books set it: each line a column running down the page, the
columns following from right to left, blocks and paragraphs following
them; the book bound at the right (its pages' margins and running content
mirrored, as a right-to-left document's). Han, kana and full-width
punctuation stand upright, in their vertical forms (the font's `vert`:
the corner brackets and the full stop turned and moved; shaped top to
bottom as HarfBuzz shapes it, each glyph by the font's vertical metrics),
and Latin letters and digits lie on their side, as UAX #50 has each
character; ruby goes at the right of its base, emphasis marks too. Block
images stand upright, as wide across the page as they are, fit to the
column. `vertical-lr` sets Mongolian: its letters on their side, the
columns following from left to right. A strike-through runs down the
middle of the characters; an underline goes on the right of the column
in Japanese and Korean (their side lines, CSS's
`text-underline-position: right`), on the left in Chinese, and on the
right in Mongolian (mlreq's right line). The running heads and page numbers
stay across.

Tables, code listings and literal blocks stand upright in the text, set
across as on a horizontal page (JLREQ 4.4.2), at the head of the column,
as wide across the page as their content needs (at most the content
area's width) and no narrower than keeps them from wrapping more; the
text goes on after them. One too long for the page's height upright lies
on its side instead, its top to the page's right, and goes on over the
pages (JLREQ 2.3.2). A chronology set down the columns, as the text is
(JLREQ Fig. 285), takes the `vertical` role (`[.vertical]`), or every
table does with `table_writing_mode: vertical`.

A block can have its own writing mode, Ptome's roles: on a horizontal
page, `[.vertical-rl]` or `[.vertical-lr]` sets a block in vertical lines
(a poem, `[verse.vertical-rl]`; a sidebar in Japanese), its columns as
long as its longest line (at most the page's height), following to the
left or the right, the block as wide across the page as its columns
are; on a vertical page, `[.horizontal-tb]` sets any block across, as a
table is. Not under `asciidoctor-compat`.

A number of one or two digits standing alone stands upright in the
column (tate-chu-yoko, JLREQ 3.2.5): two digits side by side across the
column in the font's half-width forms, an em long, set as an ideograph
is (no quarter em beside it); a lone digit in its full-width form.
Longer numbers, decimals (`2.5`), numbers with separators (`1,000`) and
digits in words (`A4`) lie on their side. `base_text_combine_upright`
says how many digits: `digits 2` (the default), `digits 3` (in the
font's third-width forms, where it has them), or `none`. Ptome's `tcy`
role sets any short text across the column (`[.tcy]#!?#`), in the
narrowest forms the font has for its length.

A combining mark stays in the font of the letter it is on: with
`font_fallbacks`, a Coptic letter from Noto Sans Coptic keeps its
overline even where the base font has one too.

### Right-to-left text

Arabic and Hebrew are shaped by the font's OpenType tables (joining
forms, ligatures, vowels and points placed on their letters), and a
line's text is put in reading order by the Unicode Bidirectional
Algorithm, in any document. A document written right to left says so
with `:dir: rtl` (as HTML's `dir`): its paragraphs, headings, captions
and table cells are set from the right, their indents there, and the
theme's alignments are mirrored (`left`, the start, is the right; a
justified paragraph's last line ends at the right). The table of
contents is mirrored too: each title at the right, its page number at
the left. So are its pages, the theme's left read as the start: the
page margins and the running content's margins and columns (a recto's
folio at its outer edge, its left), a book for print bound at the right
(`media=prepress`: a recto's inner margin and gutter at its right, a
verso's at its left), a note stream's column and line numbers, lists
marked at the right and tables with their first column at the right.
The theme picks a font that has the script (`base_font_family`, or
`font_fallbacks` for a few words).

### Fonts

Ptome compiles no fonts in: a theme names the fonts it wants, and they
come from the machine. A `font_catalog` file is looked up in
`pdf-fontsdir` (by default the theme's folder), then among the installed
fonts, those of the folders in `PTOME_FONT_PATH` (separated as `PATH`
is) and then this user's and the system's font folders: by the file's
name, then by the family and style its catalog entry gives. `GEM_FONTS_DIR`
names the built-in themes' fonts wherever they are installed, M PLUS 1
Code and M PLUS 1p (their successors on Google Fonts) stand in for
asciidoctor-pdf's M+ 1mn and M+ 1p, and a `font_family` that isn't in the
catalog names any installed family (`base_font_family: Inter`).

WOFF and WOFF2 fonts are found like TrueType and OpenType ones (and
embedded as the fonts they wrap). Through the API, fonts can also be given
as bytes, and in a browser the page's web fonts are used too (see
`doc/api.md`).

Chinese, Japanese and Korean text that neither the theme's fonts nor its
`font_fallbacks` have is set in the installed Noto CJK face of the text's
language's region: Noto Serif CJK beside a serif font, Noto Sans CJK
beside the others, in its SC cut for `zh`, `zh-Hans` and `zh-CN`, TC for
`zh-TW` and `zh-Hant`, HK for `zh-HK`, `zh-MO` and `yue`, KR for `ko`, JP
for `ja` and any other language (another region's cut where that one
isn't installed: each has every region's forms, chosen by the language).
The text's language is the document's `lang`, a block's or a span's.
Ptome bundles no CJK font: without one installed, the warning about
missing characters says to install Noto CJK. Not under
`asciidoctor-compat`, where only the theme's fonts are tried, as
asciidoctor-pdf tries them.

A font that isn't installed is replaced by a built-in PDF font (Courier
for a monospace family, Times for a serif one, else Helvetica), with one
warning; an icon set whose font is missing shows its icons as text, and
math with no math font installed is shown as its source.

`ptome doctor` lists the fonts of the built-in themes (Noto Serif,
Noto Sans, M+ 1mn, the M+ 1p and Noto Emoji fallbacks, Noto Sans Math and
the Font Awesome, Foundation and Payment icon fonts), where they are
found, and offers to download the missing ones from their official
sources into this user's font folder (`--yes` without asking, `--check`
to only check).

| Key | Default | What it does |
| --- | --- | --- |
| `base_font_ligatures` | `normal` | `none` sets text without the font's standard ligatures (fi, fl...). Fixed-pitch fonts are never ligated. |
| `base_emphasis_inversion` | `true` | Emphasis inside italic text is upright (and emphasis inside that, italic again). `false` sets all emphasis in italic. |
| `base_font_variant_numeric` | none | `oldstyle-nums` sets numbers in old-style figures (`onum`), when the font has them; also `lining-nums`, `tabular-nums`, `proportional-nums`. |
| `role_<role>_font_variant` | none | `small-caps` sets text with the role (`[.sc]#Text#`) in small capitals (`smcp`), or in smaller capitals when the font has none. `role_<role>_font_variant_numeric` takes the numeric values above. |

Text is kerned by the font's OpenType (GPOS) pairs. A style the font
catalog lacks for a family (a display face with no italic) is made from
one it has: an italic slanted, a bold stroked (asciidoctor-pdf stops with
an error).

### Footnotes

Footnotes are at the bottom of the page their reference is on, under a
short rule, numbered from 1 in each chapter (or page, or through the
document); one that doesn't fit goes on at the bottom of the next page.

| Setting | Default | What it does |
| --- | --- | --- |
| `footnotes_placement` (theme) | `page` | `end` sets them at the end of each chapter (or of the document), as asciidoctor-pdf does. `column`, with an article's `page_columns`, makes the columns the page's own, each with its notes at its foot, under the column the reference is in (the Federal Register's); the columns are then neither balanced nor ruled. |
| `footnotes_numbering` (theme) | `chapter` | From 1 in each `chapter` (asciidoctor-pdf's), on each `page` (footnotes at the bottom of the page: references and notes numbered where they land), or through the whole `document`. |
| `footnotes_separator_width`, `_color`, `_length` (theme) | `0.5`, the base border color, `33.33%` | The rule above them. |
| `footnotes_reference_content` (theme) | `[{{number}}]` | A template for a reference, raised in the text; the number links to the note. `'{{number}}'` gives a plain superscript number. Without the key, the document's `footnote-reference-template` (as in HTML and EPUB); likewise `footnote-label-template` for the label. |
| `footnotes_label_content` (theme) | `[{{number}}] ` | A template for the label before a note; the number links back to the reference. |
| `footnotes_margin_top` (theme) | the font size | The space between the text and the rule. |
| `footnotes_indent` (theme) | none | How far each note's first line is set in (a length, `1em` of the notes' size). |
| `footnotes_label_gap` (theme) | none | The space after a note's label (a length). |
| `footnotes_item_spacing` (theme) | none | The space above each note (at least half the notes' size between the rule and the first). Under `base_leading` the rule takes no room. |
| `:show-link-uri: footnote` | | A link's URI in a footnote (print books), not after the link text in brackets (`show-link-uri` set, or print media). A bare link shows its URI already. |

Side notes: a phrase whose role the theme sets beside the text
(`role_<role>_display: side`) leaves its line and is set level with it in
a side column, in the role's style, each under the one before it where they
crowd, above the page's footnotes; what doesn't fit goes on at the top of
the next page's column. A reference Bible's cross-references,
`[.xref]##*34:6* ^a^{nbsp}<<v-psa-86-15,Ps 86:15>>##` after a verse
number, fill its center column this way.

| Key | Default | What it does |
| --- | --- | --- |
| `role_<role>_display` | | `side`: phrases with the role are side notes. Their text is aligned by `role_<role>_text_align` (`left`). `none`: they are left out of the text (their anchors kept), as a critical edition leaves out the Stephanus labels its margin sets beside the line numbers. |
| `side_notes_column` | `center` in columns, else `outside` | `center`: the gap between the middle columns (make `page_column_gap` wide enough); `outside`: the outer margin (the right one, or on a verso page of a `prepress` book the left one); `inside`: the inner one (a study Bible's reference column). |
| `side_notes_padding` | `0.5em` | The space kept on each side of the column. |
| `side_notes_item_spacing` | `0.25em` | The space between two notes. |

### Listings

| Key | Default | What it does |
| --- | --- | --- |
| `code_orphans` | `2` | The fewest lines of a listing left at the bottom of a page. |
| `code_widows` | `2` | The fewest lines of a listing carried to the top of the next page. |
| `block_split_end` | `content` | Where the piece of a framed block (code, sidebar, example, admonition...) that a page's end cuts off ends: `content`, under its last line; `region`, at the page's bottom margin, its background and border with it. |
| `url_breaks` | `chicago` | Where a link's URL may break across lines: `chicago`, at The Chicago Manual of Style's points (before a slash, a period, a hyphen..., after `://`), `www.` links too; `delimiters`, after `/`, `?`, `&` and `#` only, never leaving a single character, links with a scheme only. |
| `index_terms_paragraph` | `none` | A paragraph of hidden index terms alone (`(((term)))` on a line of its own): `none`, it takes no room (its anchors go with the block after it); `line`, it is an empty line, as any paragraph. |
| `base_slash_breaks` | `true` | Whether a line may break after a slash in prose (`and/or`), as the Unicode line breaking algorithm allows. |
| `svg_placement` | `exact` | Where an SVG image is placed when it's scaled: `exact`, at its box; `page_origin`, as one drawn at its own size and scaled about the page's origin, with the scale and the translation each to five decimals (a hundred-thousandth of a point or so off). |
| `code_highlight` | `colors` | With `source-highlighter=highlight.js`: `colors`, the tokens colored as the `highlightjs-theme` colors them; `none`, the code as plain text. |
| `code_wrap_indent` | `1em` | How far past its own indentation a code line that is too long goes on, on the next line. |
| `code_wrap_marker` | arrow | `none` leaves out the return arrow drawn past the end of a line that wraps. |
| `code_role_<role>_<key>` | none | For a code block with the role (`[source.bare]`), replaces `code_<key>` (`code_role_bare_padding: 0`); its margins come from `role_<role>_margin_top` and `_bottom`. |

With `code_wrap_indent: 0` and `code_wrap_marker: none`, a long code line wraps as prose does: at the line breaking algorithm's opportunities (spaces, after a slash), as many words on a line as fit, the next line at the left.

With `source-highlighter=highlight.js`, source blocks are highlighted by
plain_highlighting (the highlighter the HTML backends use) and their tokens set in the
colors, weights and styles of the highlight.js theme `highlightjs-theme`
names (`github` by default; any of highlight.js 11.12.0's themes). The
block's background stays the PDF theme's.

A caption stays with the block it is above. Callout markers aren't part
of the text when code is copied, and link to their callout list item,
which links back. They may be text rather than circled numbers:
`conum_glyphs: '[{{number}}]'` (a template), in `conum_font_style` and
`conum_font_variant_numeric` (`oldstyle-nums`), and a callout list's
markers their own (`callout_list_marker_content: '{{number}}.'`).

### Math

AsciiMath (`stem:[]`, `asciimath:[]`, `[stem]` blocks with `:stem:` or
`:stem: asciimath`) is typeset: converted to MathML (the same as the
DocBook and EPUB backends', ADR-0014), then laid out by plain_pdf's math
layout in a font with an OpenType `MATH` table, by its rules (scripts,
fractions, radicals, limits, accents, delimiters that grow with what they
enclose, larger operators in display style). Inline formulas stand on the
baseline at the text's size, in its color; a block is in display style.
Copied, a formula gives its source.

LaTeX math (`latexmath:[]`, `:stem: latexmath`) is typeset the same way,
converted to MathML by ptome: math mode as documents use it (KaTeX's
and MathJax's common commands: `\frac`, `\sqrt[n]`, `\left`...`\right`,
scripts and limits, Greek and symbols, function names and
`\operatorname`, accents and braces, `\text` and the `\math...`
alphabets, `\color`, `\boxed`, spaces, the `matrix` environments,
`cases`, `array`, `aligned`). A command it doesn't know is shown as
written, and reported. Parentheses written plainly keep their size, as in
TeX; `\left` and `\right` grow them.

| Key | Default | What it does |
| --- | --- | --- |
| `math_font_family` | Noto Sans Math (bundled) | The font formulas are set in: a family of the font catalog whose font has a `MATH` table (STIX Two Math, Libertinus Math, New Computer Modern Math...). A character it lacks comes from the base font. |
| `stem_font_size`, `stem_font_color` | the base font's | A STEM block's size and color. |
| `stem_text_align` | `center` | Where a STEM block's formula goes: `left`, `center`, `right`. A formula wider than the room is scaled down to fit it. |

### Images

| Key | Default | What it does |
| --- | --- | --- |
| `image_placement` | `here` | An image (with its caption) floats, as figures do in books: when it doesn't fit the rest of the page, to the top of the next page, the text after it filling the room; when it fits, to the top (`top`) or the bottom (`bottom`) of its page, or the nearer of the two (`auto`), the text flowing around it, or it stays (`next`). Never past a heading or a page break; an image in a list, table, sidebar or other block stays there. An image's own `placement` attribute chooses for it (`image::x.png[placement=bottom]`; `none` keeps it in the flow). |
| `image_scope`, `image_role_<role>_scope` | `column` | `page`: in columns, an image (with its caption) spans them, floating across the top or the bottom of its page (the nearer, or as its placement says): a map in a two-column book. An image's own `scope` attribute chooses for it (`page` or `parent`). |
| `image_text_font_family`, `_font_size`, `_font_color`, `_leading` | the code font's | The font of a text file shown as an image (below). |

An image whose target is a text file (`image::diagram.txt[]`, ASCII art)
is set as its text: every line as it is, in the code font (or
`image_text_*`), the block as wide as its longest line and aligned,
captioned and floated as an image. A book can show a picture in HTML and
the text in print with an attribute:
`:diagram-ext: svg` and `ifdef::backend-pdf[:diagram-ext: txt]`, then
`image::diagram/http-get.{diagram-ext}[]`.

### Tables

| Key | What it does |
| --- | --- |
| `stem_math` | `typeset` | How math (`stem`, `latexmath`, `asciimath`) is set: `typeset`, as a formula; `source`, its source, in a code block or as code inline (as asciidoctor-pdf sets it without a math renderer). |
| `table_borders` | `above` | When a table's cell borders are painted: `above`, after every cell's content, so nothing covers them; `with-cells`, each cell's before its content. |
| `table_cell_margin_top` | `drop` | The margin above the first block in a cell (an AsciiDoc cell's heading): `drop`, the block starts at the cell's padding, as at the top of a page; `keep`, the cell keeps it, as CSS's table cells contain their content's margins. |
| `table_role_<role>_<key>` | For a table with the role (`[.wide]`), replaces `table_<key>`: every table with the role is styled once, in the theme. |
| `table_base_<key>` | In the modern engine, the base keys inside an AsciiDoc cell (`table_base_text_align_last: center`). |
| `table_cell_role_<role>_background_color`, `_font_color`, `_font_style`, `_font_size`, `_font_family`, `_text_align` | Style a cell whose whole text is a phrase with the role (`\|[.paid]#Paid#`). |

AsciiDoc has no syntax for a cell's role, so a cell takes the role of its
text. In HTML, the same cells can be styled with CSS:
`td:has(> p > span.paid:only-child) { background: #dfd; }`.

### Index

| Key | Default | What it does |
| --- | --- | --- |
| `index_pagenum_text_align` | `left` | `right` sets each entry's page numbers in a column at the right, in tabular figures, as books do; `left` follows the term with them. |
| `index_layout` | `indented` | `run-on` sets a term's subterms in its own paragraph after semicolons, Chicago's run-in style ("term, 23; subterm, 46"; "term: subterm, 46" when the term has no pages of its own; a subterm's subterms in parentheses after it), as scholarly books set their indexes; `indented` gives each subterm a line of its own. Not under `asciidoctor-compat`. |
| `index_category_headings` | `true` | `false` leaves out the letter heading above each group of terms. |
| `index_font_family`, `_font_size`, `_font_color`, `_font_style` | the base font | The index's font. |

Each page is listed once (`hypermedia, 13, 20`); the
`index-pagenum-sequence-style` attribute chooses otherwise as in
asciidoctor-pdf (`range` joins consecutive pages, `term` lists a page for
each use, which is asciidoctor-pdf's default). With `media` other than
`screen`, consecutive pages are joined, unless the attribute is `page`.

### Pages

| Key | Default | What it does |
| --- | --- | --- |
| `page_measure` | none | The text block's width (`66ch`: 66 zeros of the text face at the text size; `30em`; a length): the left and right margins center it, the top and bottom are `page_margin`'s. A look's `tokens.measure` sets it when the look gives no page margins (`doc/looks.md`); `pdf-page-margin` overrides it. |
| `running_content_on_blank_pages` | `false` | A blank page (the verso before a chapter that starts on a recto page) has no header or footer unless this is `true`. |
| `:folio-start:` (document) | `1` | The number of the first page after the front matter, the pages after it numbered on from it: a journal's article or a Federal Register document numbered within its volume (`47855`). Recto and verso stay the sheet's own sides. Not under `asciidoctor-compat`. |
| `running_content_layer` | `under` | Whether the header is painted `under` the page's content (content reaching into the top margin, a large title's ascenders, covers its rule) or `over` it, as the footer always is. |
| `page_layer_clip` | `none` | `page` clips the page's foreground image and the running content's background and border to the page, as asciidoctor-pdf's stamps are clipped by their bounding box (what reaches the page's edge ends a hair differently). |
| `running_content_on_openers` | `false` | A page that opens a part or chapter has no header or footer unless this is `true`. |
| `section_role_<role>_running_content_on_openers` | | `true` keeps the running content on the first page of a part or chapter with that role (a foreword set as an ordinary heading). |
| `header_title_style`, `footer_title_style` | `document` | As in asciidoctor-pdf (`document`, `toc`, `basic`). |
| `running_content_marks` | | A prefix of anchor ids (`v-`): those anchors are the pages' marks, and running content may refer to `{page-first-mark}` and `{page-last-mark}`, the reference text of the first and last on the page (a page without one has the last one before it): a Bible's running head, `EXODUS 33:14`, from `[[v-exo-33-14,Exodus 33:14]]`. |
| `units_<level>_label_font_color`, `_font_style`, `_display`, `_hang` | | A document in units: the labels of a level's units (`verse`) in that colour (a reference Bible's light verse numbers), `bold`, or with `display: none` left out of the text (a reader's edition), the space after them with them. `_hang` (a list of block roles, `[poetry]`, or `true` for any block): in a block with one of them, each label hung left of its line, a third of an em from the text (a poem's verse numbers in the gutter, a UK bill's subsection numbers). Not under `asciidoctor-compat`. |
| `units_<level>_margin_left`, `_margin_top` | | A document in units: a unit of the level that is blocks (`break: block`) indented that far inside the unit it is in, with that space above it (a US bill's paragraphs 2 em inside their subsection). Not under `asciidoctor-compat`. |
| `running_content_units` | | A level of a document in units (`verse`, or `bible.verse`; see `doc/units.md`): running content may refer to `{page-first-unit}` and `{page-last-unit}`, the first and last unit of that level on the page as its scheme cites them, and `{page-units}`, the range they make, what its ends share said once (`Gen 2:20–3:7`, `Gen 47:17–30`; `{page-units-long}`: `Genesis 2:20–3:7`): a single piece left always shortens, several only where they couldn't be read as a reference from the top level (`Ps 23:6–24:2`, but `3.1.89–3.2.4`). For a form of its own, `{page-first-<level>}` and `{page-last-<level>}` are each level's label at the page's first and last unit (`{page-first-chapter}:{page-first-verse}`). A page without one has the last one before it. |

Running content may be a template: `'{{#chapter-numeral}}{{chapter-numeral}}. {{/chapter-numeral}}{{chapter-title}} · {page-number}'`
writes `3. A Web 1.0 Application · 71`, and on an unnumbered chapter's
pages `Introduction · 15` (the numeral part left out, where a line that
refers to a missing `{attribute}` is dropped). `{{top-title}}` and
`{{top-numeral}}` are the last part or chapter that started before the
page (on a page where a chapter starts, the one before it), else the
document's title: a head that names what the page continues (TeX's
`\topmark`). With `title_style: basic`,
the titles come without their numbers.

A part or chapter with the `noheader` or `nofooter` option (as
asciidoctor-pdf reads them on the `toc` macro) has no header or footer on
its pages: `[colophon%notitle%noheader%nofooter]` for a copyright page.

`page_columns` (with `page_column_gap`) sets an article's body in columns,
as asciidoctor-pdf does, and a book's too: each chapter's heading across
the page, its content in the columns under it, which are balanced where
the chapter ends, so that the next chapter starts under its shorter
column (with `heading_chapter_break_before: auto`). The asciidoctor-pdf
compatibility setting keeps a book in one column, as the gem does.

In columns, a block floating to a side floats in its column, a share of
the column's width: one that doesn't fit in the room left in its column
starts the next, and one taller than a column is set in the flow. An
image floated by its `float` attribute that would leave the text beside it
narrower than 12 ems is set across its column instead. A heading kept with
what follows it (`heading_min_height_after: auto`) keeps with an image
whole.

### Sidebars, callouts and banners

A block whose role the theme floats goes to the left or the right of the
page, the blocks after it beside it: each one beside it whole, narrowed, or,
where it doesn't fit beside it, below it at full width (a section's blocks
each so). Where the floating block doesn't fit on its page, the rest goes on
at the top of the next one, before anything else there, what is set there
going around it too: a report's sidebar that runs from one page into the
next, through the banner at the top of the second. A page break waits for
it, and the repeated headings of its section (`heading_h<n>_repeat`) are set
beside it.

| Key | Default | What it does |
| --- | --- | --- |
| `role_<role>_float` | | `left` or `right`: blocks with the role (an open block, a sidebar, a quote, an image) float to that side. `top`, `bottom`, `auto` (the nearer) or `next` (only when it doesn't fit): they float to the top or the bottom of the page (or column), above its notes; with `role_<role>_float_scope: page`, across the page's columns: a study Bible's feature article between the text and the notes. Not under `asciidoctor-compat`. A paragraph beside one runs around it: its first lines beside it as far as they go, the rest set again at the full width below it; other blocks beside it go below it unless they fit beside it whole. |
| `sidebar_columns`, `sidebar_column_gap` | `1`, the font size | A sidebar's body (under its title) in that many balanced columns; per role, `sidebar_role_<role>_columns`. Not under `asciidoctor-compat`. |
| `role_<role>_float_width` | a third of the text's width | Its width: a length or a percentage of the page's text width (in columns, the column's). |
| `role_<role>_float_gap` | the font size | The space between it and the blocks beside it. |
| `role_<role>_float_shape` | | `alpha`: an image floating by the role has its outline, the edge of its opaque pixels (those above `_float_shape_threshold`, 0.5, of opacity), not its box: a paragraph beside it runs around the outline line by line (CSS's `shape-outside`), `_float_shape_margin` (0) from it. An image's `shape=alpha` attribute does the same, and an image with it and `float=left` or `right` floats so (`image_float_gap`, `image_float_shape_margin`, `image_float_shape_threshold`), as on the web. A PNG with alpha; other images keep their box. |
| `example_collapsible` | `frame` | A collapsible example block (`[%collapsible]`), which print can't collapse: `frame`, as any example block; `details`, as an open details element shows: its title (else "Details") after a ▼, as a caption, over its content set in by the marker's width, with no frame. |
| `example_role_<role>_<key>`, `sidebar_role_<role>_<key>`, `quote_role_<role>_<key>`, `verse_role_<role>_<key>` | | For an example block, a sidebar, a quote or a verse with the role (`[.callout]`, `[.pullquote]`), replaces `example_<key>`, `sidebar_<key>`, `quote_<key>` or `verse_<key>`; `_link_font_color` and `_link_text_decoration` style the links in it (a pill-shaped link). |
| `<category>_shadow_color` | | A shadow under a framed block (`example`, `sidebar`, their roles' keys): `_shadow_offset` (right and down, `[0, 2]`), `_shadow_blur` (`4`), `_shadow_opacity` (`0.3`). |
| `<category>_background_image` | | An image over a framed block's background, clipped to it: `image:stripes.svg[fit=contain,position=right top]`, as `page_background_image`. |
| `sidebar_title_rule_width` | | A rule under a sidebar's title, as `heading_h<n>_rule_*`. |

`test/pdf/fixtures/report` lays out a personal report with them: banners
over each page of a category, a gauge floated beside the first paragraph, a
callout with a shadow and stripes, and a gray sidebar of two boxes that goes
on at the top of the next page.

### Headings

| Key | Default | What it does |
| --- | --- | --- |
| `heading_h<n>_content` | the numbered title | A template for the heading's text, with `{{title}}`, `{{numbered-title}}`, `{{number}}` (`1.2.`, a part's `I`), `{{numeral}}` (`1`, `I`) and `{{signifier}}` (`Chapter`, `Part`). A chapter's label on a line of its own, in gray: `"{{#numeral}}<font color=\"#8C8C8C\">{{signifier}} {{numeral}}</font>\n{{/numeral}}{{title}}"` (markup attributes in double quotes). |
| `heading_float_barrier` | `true` | A heading starts after the floating images waiting for the next page; `false` lets it pass them. |
| `heading_min_height_after` | asciidoctor-pdf's | `auto`: a heading moves to the next page unless the block after it can start under it (as much of it as may start a page: a paragraph's first `prose_orphans` lines): a sticky heading; a length works as in asciidoctor-pdf. |
| `heading_h<n>_leading` | the base leading | Under `base_leading`, the space between the heading's lines (a part's title: `5`). |
| `heading_h<n>_vertical_align` | `top` | `middle` or `bottom`: a heading that starts its page (a part's title page) in the middle or at the bottom of it. |
| `heading_h<n>_background_color` | | A fill behind the heading and its padding, rounded by `heading_h<n>_border_radius`: a banner. |
| `heading_h<n>_margin_left`, `_margin_right` | `0` | The heading's side margins; negative ones reach out past the text's edges. Beside a block floating to a side, a heading reaches no nearer it than the float's gap. |
| `heading_h<n>_repeat` | `false` | `true`: the heading is set again at the top of each page its section goes on to (a report's category banner and subject, under one another), and on the page a sidebar of the section goes on to. |
| `heading_h<n>_rule_width` | | A rule under the heading, as a box of its own (beside a block floating to a side, the heading may be set beside it and the rule under it): `_rule_color`, `_rule_margin_top`, `_rule_margin_bottom`; `_rule_dash`, lengths of dashes and gaps in turn, and `_rule_cap` (`round` or `square`) for a rule of rounded bars. |
| `heading_h<n>_display` | | `margin`: the heading left out (its anchor and running content stay) and its text from `heading_h<n>_margin_content` (`{{numeral}}`; `{{title}}`, the section's attributes as `{{attr-<name>}}`) hung in the margin left of the first line of the section's first paragraph (past those with a role of `_margin_skip_roles`), in `heading_h<n>_margin_font_*`: a reader's edition's chapter numbers. Not under `asciidoctor-compat`. |
| `heading_h<n>_drop_lines` | | `2` or more: the heading set as a drop beside that many first lines of the section's first paragraph (a Bible's chapter number, an initial), its capitals from the first line's to the last line's baseline, the heading itself left out (its anchor and running content stay). `_drop_content` is a template for its text (`{{numeral}}` by default; `{{title}}`, and the section's attributes as `{{attr-<name>}}`: `[number=34]` gives `{{attr-number}}`); `_drop_font_family`, `_font_style`, `_font_color`; `_drop_gap` (`0.3em`) after it; `_drop_skip_roles` the roles of paragraphs it passes (a psalm's title). |
| `heading_h<n>_initial_lines` | | `2` or more (modern engine): the section's first paragraph opens with its own first letter as an initial that many lines deep, as a novel's chapter does, the heading kept; styled as a role's initial (`role_<role>_drop_lines`) by `heading_h<n>_initial_font_*` and `_initial_gap`; `_initial_lead_in` (a number of words) puts the words after it in the role `lead-in`. Not with `_drop_lines`. |

A section with a role the theme styles is set in a box, as a sidebar is:
`section_role_<role>_background_color`, `_border_color`, `_border_width`
(one width, or one per side), `_border_radius`, `_padding`, `_margin_top`,
`_font_family`, `_font_size`, `_font_color` and `_font_style`, and its
heading's `_heading_font_family`, `_heading_font_size`,
`_heading_font_color`, `_heading_font_style`, `_heading_margin_top` and
`_heading_margin_bottom` (`[.html-note]` and
`section: { role: { html-note: { background-color: F5F5FF } } }`). It
stays a section: it is numbered, and listed in the contents.
`_vertical_align: middle` (or `bottom`) sets a section that starts a page
and fits on it in the middle (at the bottom) of the page: a dedication. Any other key of the theme
under the role's (`section_role_<role>_prose_margin_bottom`) takes the place
of that key (`prose_margin_bottom`) inside the section.

A section whose role has page keys is set on pages of its own, laid
out by the role's page template (a magazine's feature on tinted pages
with wider margins), and what follows it starts a page of the layout's
again (modern engine): `section_role_<role>_page_margin` (as
`page_margin`), `_page_background_color`, `_page_background_image` (as
`page_background_image`), `_page_running_content: none` (no header
or footer on its pages) and `_page_columns` (its content in that many
balanced columns under its heading). Its pages keep the layout's size.

A part on a page of its own is asciidoctor-pdf's
`heading_part_break_after: always`; a title lower on its page,
`heading_h2_padding: [3in, 0, 0, 0]`.

A column too narrow for even one character keeps its text (set past its
edge, with a warning), where the gem leaves the table out.

### Print

| Setting | What it does |
| --- | --- |
| `page_bleed` (theme) | How far backgrounds run past the page for trimming (`0.125in`): the page is the `TrimBox`, the sheet (`MediaBox`, `BleedBox`) grows by the bleed on every side. |
| `-a pdf-standard=PDF/X-4` | Writes PDF/X-4: PDF 1.6, an output intent, `Trapped`, the PDF/X identification in the information and XMP, a `TrimBox` on every page. |
| `-a pdf-output-intent=FILE` | The ICC profile of the printing condition (the printer gives it); PDF/X-4 needs one. |
| `-a pdf-output-condition=NAME` | The printing condition's identifier (`Custom` by default). |
| `-a pdf-layout-report=FILE` | Writes, next to the PDF, each block that breaks across pages, with its source line and pages (`book.adoc: line 66: listing on pages 2-3`), for proofreading. |
| `-a pdf-page-map=FILE` | Writes, next to the PDF, a JSON map of its pages: their labels, and each block's source line with the pages it is on. An EPUB of the same source reads it (`epub-page-map`) to mark the print edition's pages. |

Preflight messages report what keeps a PDF/X-4 from conforming: a font
that isn't embedded (a built-in PDF font in the theme), a profile that
isn't an output profile, and content in RGB with a CMYK printing
condition (Ptome's colors are RGB: use an RGB output profile, or
convert the PDF to the printer's CMYK).

### Accessibility

`-a pdf-ua` makes a tagged PDF that conforms to PDF/UA-1 (ISO 14289-1),
for screen readers and reflow. Its structure tree records what the
content is: headings (`H1` for the title, `H2`… for the sections, by
their level), paragraphs, lists (`L`, `LI`, `LBody`), tables (`Table`,
`TR`, header cells `TH` with their scope, `TD`), figures with their
alternate text (an image's `alt`), and links (`Link`, each annotation
described). Running heads, page numbers, backgrounds and borders are
artifacts, and the document's language (`:lang:`, `en` by default) and
title are given. veraPDF finds the Hypermedia Systems book conforming.

A character the font lacks reads as U+FFFD, the replacement character;
give a fallback font that has it. Tagging adds about a sixth to a
book's PDF and a few percent to the time it takes, so it is not on by
default. Inline images are read as part of their paragraph's text, and
a figure's caption is a paragraph of its own.

### Cores

The work that doesn't depend on the order of the pages runs on the
machine's other cores while the document is walked and laid out: PNG
images with transparency (or interlaced) are encoded again, and the
pages' content streams compressed. Object numbers, page numbers and the
order of everything in the file are decided on the main isolate, so the
PDF is the same, byte for byte, with any number of workers (ADR-0016;
`tool/jobs_check.dart` checks it on the PDF fixtures, the gem's examples
and a book).

| Setting | What it does |
| --- | --- |
| `-a jobs=N` | Uses N workers; `1` for none. By default, one for each physical core. |

The command line and the asynchronous API (`convertFileAsync`,
`convertToTargetAsync`) use them; the synchronous API converts on one
core, as do the files of a `-j` batch (each on a core of its own) and
JavaScript. An EPUB compresses its files on the workers the same way.

### Messages

Layout warnings name the file and line of the block they are about
(`doc.adoc: line 6: table column 1 is too narrow for its text`): `-b pdf`
keeps every block's source location. `--progress` reports each phase of
a conversion as it finishes, and `-v` how many pages were laid out.

`:quotation-lint:` reports quotations set otherwise than The Chicago
Manual of Style sets them (13.9): one of a hundred words or more run in
(between double quotation marks) rather than set off as a block
quotation, and a block quotation shorter than five lines once laid out
(one that goes on to another page is long enough). An editor's check for
a book that follows Chicago, as the `scholarly-monograph` look does; not
under `asciidoctor-compat`.
