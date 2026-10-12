# Typography: the print traditions as parameters

This is ptome's design document for typography. It condenses three rounds of research into print traditions (books, technical manuals, Bibles and other addressed texts, law, magazines) into what the engine and its themes need to know. It follows [ADR-0021](../../../adr/0021-typography-from-research.md): layout rules come from the typographic literature, standards and measured documents, never from another engine's output.

The finding that shapes everything below is that every tradition is one small numeric canon with a few dials turned. Rules measured against real documents turn into distributions: a US bill carries 25 numbered lines on most pages and 26 on some; a drop initial is two lines deep in one tradition and three in another; a university-press gutter is about as wide as its fore-edge. So ptome expresses a tradition as a **parameter file** (a look or a theme) with a measured default and a documented range, never as a preset or a mode.

Sources: the free primary texts are linked. Robert Bringhurst's *The Elements of Typographic Style* (pagination of version 3.0, 2004) and Jan Tschichold's *The Form of the Book* (1991) are cited by printed page, without links.

## The numeric canon

### Margins

The "medieval canon" is a 1950s reconstruction. On a 2:3 page, Tschichold's reconstruction gives the inner margin one ninth of the page's width, the outer two ninths, the head one ninth of its height and the foot two ninths, with the text block as tall as the page is wide (Tschichold, "Consistent Correlation Between Book Page and Type Area", in *The Form of the Book*, pp. 36ff.). Van de Graaf's construction, "Villard's diagram" and Rosarivo's module all reach the same ninths. Bringhurst generalises it to "any proportion of page and textblock, so long as the two remain in unison", and with Tschichold calls twelfths "fuller and more efficient" (p. 172).

Measured modern books ignore the canon's 1:2 ratios:

| Source | Inner | Outer | Head | Foot |
| --- | --- | --- | --- | --- |
| Nine 6 × 9 in university-press books (medians) | 0.79 in | 0.83 in | 0.875 in | 1.0 in |
| UCL Press, Royal (6.14 × 9.21 in) | 0.94 in | 1.11 in | about 0.67 in | about 1.2 in |
| A small press at 5.5 × 8.5 in | 0.82 in | 0.63 in | 0.53 in | 0.61 in |

Printers set floors rather than norms. KDP's least gutter grows with the page count, from 0.375 in for 24–150 pages to 0.875 in for 701–828 ([KDP](https://kdp.amazon.com/en_US/help/topic/GVBQ3CMEQW3W2VL6)); IngramSpark asks for at least 0.5 in all round. KOMA-Script's type area (DIV stripes, a binding correction BCOR, the foot snapped to whole lines) is the most exact free construction ([KOMA-Script guide](https://mirrors.ctan.org/macros/latex/contrib/koma-script/doc/scrguide-en.pdf)).

In ptome: `page_margin_canon`, `page_margin_div` with `page_margin_bcor` and whole lines, `page_margin_profile` (`university-press`, `ucl-press`, `trade`) and `page_margin_gutter: kdp` (doc/pdf.md).

### Measure and leading

The craft norm is **45 to 75 characters a line, 66 ideal**, 40 to 50 in columns; most books carry 30 to 45 lines a page and 60 to 66 characters a line (Bringhurst, rule 2.2.3, p. 38). The reading research is thin and does not move that default: 55 characters a line was rated easiest on screen ([Dyson 2004](https://stu.westga.edu/~ssynan1/literacy/Dyson.pdf)); justified text read a little faster than ragged ([TUGboat 37:2](https://tug.org/TUGboat/tb37-2/tb116akhmadeeva.pdf)), but **justification without hyphenation was read much slower** ([TUGboat 38:2](https://tug.org/TUGboat/tb38-2/tb119veytsman-justify.pdf)). Hence a rule: a language without hyphenation patterns falls back to ragged right, never to unhyphenated justification.

Leading has routine values (9/11, 10/12, 11/13, 12/15) and qualitative reasons for more: a longer measure, a darker or larger-bodied face, sans, many capitals or superscripts (Bringhurst, rule 2.2.1, pp. 36–37). Every departure from the text should take an even multiple of the leading (rule 2.2.2), which is what a baseline grid enforces. For beginning readers, 30 pt on 19 pt type (a ratio near 1.6) is normal, and line spacing between 1.1 and 2.0 made no difference to reading errors ([*Visible Language* 40(3)](https://journals.uc.edu/index.php/vl/article/download/5784/4648)).

### Book parts

- **Paragraphs.** An indent of at least an en, usually an em or a line, never more than three ems; none after a heading (Bringhurst, rules 2.3.1–2.3.2, pp. 39–40). Indent and blank line tie as paragraph signals in the one controlled print study ([Hartley et al. 1978](https://journals.uc.edu/index.php/vl/article/download/5255/4119)), so the signal is a genre default.
- **Headings.** Springer: section heads 36 pt above and 24 below on 10/12 text, subsections 30 and 18 ([Springer spec](https://cs.nyu.edu/~shasha/papers/svtypspec6x9.PDF)). LaTeX's book class: 50 pt before a chapter head and 40 after; its section skips in ex do not land on a 12 pt grid ([classes.dtx](https://mirrors.ctan.org/macros/latex/base/classes.dtx)).
- **Chapter openers.** A small-caps lead-in, a fleuron or a versal; a drop initial about three and a half lines deep on 10/12 text (Bringhurst, rules 4.1.3–4.1.4, pp. 62–64). Software splits on depth: lettrine and Typst's droplet use two lines, ConTeXt and SILE three ([lettrine](https://mirrors.ctan.org/macros/latex/contrib/lettrine/doc/lettrine.pdf)).
- **Notes.** Sidenotes preferred; footnotes short and infrequent, never running onto a second page; endnotes numbered through the book with heads like "Notes to pages 44–62" (Bringhurst, rules 4.3.1–4.3.4, pp. 68–69). Tschichold keeps the text's lead increment in notes (10/12 text, 8/10 notes) and calls the short 4-pica rule pointless (*The Form of the Book*, pp. 123–128).
- **Indexes.** Two or more columns, a gutter of at least a pica, flush-and-hang entries ([memdesign](https://mirrors.ctan.org/info/memdesign/memdesign.pdf)); Chicago 18 prefers word-by-word order (`index-sort`).
- **Sections.** A dinkus for every unheaded break, since "without them it is impossible to see whether a part ends at the bottom of a page" ([Penguin Composition Rules, 1947](https://plain-xetex.neocities.org/typography/penguinrules.pdf)); a blank line only where it can never fall at a page's foot (`thematic_break_content`, `_content_display: boundary`).
- **Sentence spacing.** One word space after a period (Tschichold, pp. 95ff.; Bringhurst, rule 2.1.4).

## Line breaking

All the serious breakers run Knuth and Plass's dynamic program and differ in their costs ([Knuth & Plass 1981](https://gwern.net/doc/design/typography/tex/1981-knuth.pdf); [tex.web](https://ctan.math.illinois.edu/systems/knuth/dist/tex/tex.web)).

| | Plain TeX | LaTeX `\sloppy` | microtype | Typst | Adobe (Photoshop API) |
| --- | --- | --- | --- | --- | --- |
| Demerits | (line_penalty + b)² ± p² | as TeX | as TeX | (1 + b + p)², the paper's | not published |
| Tolerance | pretolerance 100, tolerance 200 | 9999, emergency stretch 3em | — | none | — |
| Line penalty | 10 | — | — | — | — |
| Hyphen penalty | 50 | — | — | 135 | — |
| Double / final hyphen demerits | 10000 / 5000 | — | — | — | — |
| Adjacent fitness | 10000 | — | — | no fitness classes | — |
| Club, widow penalties | 150 | — | — | — | — |
| Hyphen minimums | 2 left, 3 right | — | — | — | 2 and 2, words over 5 |
| Consecutive hyphens | no cap (only demerits) | — | — | — | limit 2 |
| Word spacing | ⅓ em, +⅙, −⅑ | — | — | 66.67–150% | 80/100/133% |
| Expansion | — | — | ±20 thousandths, step 1 | — | — |
| Protrusion | — | — | per glyph: hyphen 500, period 700, comma 500… | — | — |
| Tracking | — | — | small caps 50/1000 em | — | — |

Sources: [plain.tex](https://ctan.math.illinois.edu/systems/knuth/dist/lib/plain.tex), [ltpage.dtx](https://github.com/latex3/latex2e/blob/develop/base/ltpage.dtx), [microtype](https://ctan.math.illinois.edu/macros/latex/contrib/microtype/microtype.pdf), [Thành's thesis](https://tug.org/TUGboat/tb21-4/tb69thanh.pdf), [Typst linebreak.rs](https://github.com/typst/typst/blob/main/crates/typst-layout/src/inline/linebreak.rs), [Adobe JustificationProperties](https://developer.adobe.com/photoshop/uxp/2022/ps_reference/objects/options/justificationproperties).

What ptome takes from this:

- **Total fit with TeX's costs** for justified text, three passes (no hyphenation, hyphenation, emergency stretch). Badness is computed in floating point, so the documentation says "TeX-like".
- **Narrow measures loosen**: LaTeX turns `\sloppy` on for two-column setting and bibliographies; ptome's emergency stretch is a parameter tied to the measure.
- **Ragged text is a hard rag**: finite right glue of 2 em with fixed word spaces (plain TeX, ragged2e), not infinitely stretchable glue, so total fit still evens the lines and hyphenates (Bringhurst, rule 2.1.3, p. 27). LaTeX's kernel `\raggedright` makes hyphenation nearly impossible.
- **A hyphen-run cap** (`base_hyphenate_limit_lines`), which TeX lacks: Bringhurst's "no more than three", InDesign's limit.
- **Microtypography**: protrusion counted by the breaker (`base_overhang`), expansion (`base_font_expansion`), tracking for capitals and small capitals (`caps_letter_spacing`, microtype's 50 thousandths).
- **Runts**: a last line not too short (`base_last_line_min_width`).
- **Gutenberg's B42 justified with alternative sorts at a fixed word space**, the hyphen, full point and raised s hung in the margin ([Wild 1995](https://www.numdam.org/item/CG_1995___22_5_0.pdf)): a model for discretionary alternatives, not for font expansion.
- **Determinism**: legislative printing needs the same breaks every time (GPO's MicroComp treats a dictionary change as a major version), so an update to plain_hyphenation's patterns is a breaking change for documents with line numbers.

## The parameter families

What each tradition needs, as families of parameters, with ptome's keys where they exist (doc/pdf.md).

| Family | What it holds | ptome |
| --- | --- | --- |
| Margins | canon n, DIV and BCOR, ratio pairs, measured profiles, whole-line foot, a gutter by page count | `page_margin_canon`, `_div`, `_bcor`, `_profile`, `_whole_lines`, `_gutter` |
| Measure | a length or a character count | `page_measure` (`66ch`) |
| Breaking | value sets as files; hyphen-run cap; protrusion, expansion, tracking; runts; ragged glue | `base_line_breaking`, `base_hyphenate_limit_lines`, `base_overhang`, `base_font_expansion`, `caps_letter_spacing`, `base_last_line_min_width` |
| Vertical rhythm | heading space in lines; a baseline grid; line matching for thin paper; an exact pitch | `page_baseline_grid`, `base_line_pitch`, `role_<role>_grid_line` |
| Paragraph signals | indent or blank line, none after headings | look tokens (`paragraph.signal`) |
| Thematic breaks | a content template, forced at page boundaries | `thematic_break_content`, `_content_display` |
| Initials | drop lines (2 or 3), a lead-in in small caps | `heading_h<n>_drop_lines`, `role_<role>_drop_lines`, `_drop_lead_in` |
| Running heads | range, current and current-reference modes over any mark stream | `running_content_marks`, `running_content_units` |
| Line numbers | counting domain, interval, side, restart, basis (typeset lines or a grid), a rule | `line_numbers_*`, `:line-numbers:` |
| Notes | series with keying, arrangement (run in, columns), placement (foot, side, centre, end); in step with their text | `note_streams`, `note_stream_<name>_*`, `footnotes_text_min_lines`, `footnotes_lag` |
| Floats | top, bottom, across columns; whole, never cut | `role_<role>_float`, `_float_scope` |
| Pagination | first fit or optimal | `pagination` |
| Text conventions | punctuation spacing by language, Sperrsatz, dash and ellipsis styles, mediation glyph, amendment vocabularies, verse-number emphasis | partly (`units_<level>_label_*`); per-language tables open |
| Page labels | templates such as "II – 1 – 51" or "1-13" | page label templates (doc/books.md) |
| Code | size as a ratio of the text | open |
| Title pages | recto and verso slot lists (DocBook's) | open |

Rule for the engine: content it cannot place produces a warning that names it, never silence.

## What each output can carry

Only the PDF engine owns the breaker, the page builder and the fonts, so only it carries every convention. The others inherit print unequally.

| Convention | HTML5 | EPUB 3 (reflowable) | ptome PDF | man | DocBook 5 |
| --- | --- | --- | --- | --- | --- |
| Justification and hyphenation | `hyphens`; `text-wrap: pretty` (Chrome: last four lines, on a trigger; Safari: whole paragraph, but not where soft hyphens occur) | the reader may override; Kindle honours `hyphens` | total fit, 72 languages | groff decides | encoded only |
| Balanced columns | `columns` | Kindle ignores them | yes, mid-page too | none | FO parameter |
| Drop initials | `initial-letter` (Chrome; prefixed in Safari); float fallback (Firefox only parses it) | span and float; Kindle interprets | from headings and from a paragraph's first letter | none | role |
| Running heads | none on screen | the reader's own | templates, mark and unit ranges | `.TH` only | FO templates |
| Notes | end of page; sidenotes by CSS | popups | page foot, streams, side columns, in step with their text | NOTES section | `<footnote>` |
| Baseline grid | not possible | not possible | yes | none | none |
| Small caps, old-style figures | `font-variant-*` | `small-caps` only | `smcp`, made from capitals when missing; `onum` | bold or caps | role |

For EPUB, the reading system owns the body: Kindle ignores columns, widows, orphans and `hyphenate-limit-*` ([Kindle Publishing Guidelines](https://kindlegen.s3.amazonaws.com/AmazonKindlePublishingGuidelines.pdf)); Apple Books lets the reader's justification win unless fonts are specified ([Apple Books Asset Guide](https://help.apple.com/itc/booksassetguide/en.lproj/itc2cf4d26eb.html)); Standard Ebooks leaves alignment unset and hyphenates ([core.css](https://github.com/standardebooks/tools/blob/master/se/data/templates/core.css)), which ptome follows. Build-time soft hyphens help e-readers and Firefox but switch Safari's paragraph optimiser off, so they are a per-format switch.

For addressed texts on the web, all apparatus (verse numbers, notes, headings, words of Christ) stays in the markup and root classes or data attributes switch it, as ESV.org, Bible Gateway and YouVersion's reader do.

## The traditions, measured

### Books

- **Penguin** ([Composition Rules](https://plain-xetex.neocities.org/typography/penguinrules.pdf)): words spaced as closely as possible, a one-em indent and none after a heading, asterisks for unheaded breaks, single quotes, spaced en rules, letterspaced small-cap running heads (book on the verso, chapter on the recto), notes 2 pt smaller. Penguin Classics: 10.25/12.25 Sabon, heads 8.25, folios 8.5, heading space in multiples or halves of the line.
- **Harry Potter** ([Errington's bibliography](https://archive.org/details/jkrowlingbibliog0000erri)): Scholastic US, 12 pt Adobe Garamond, a vignette between "CHAPTER n" and the title, "CHAPTER n" on the verso and the title on the recto; Bloomsbury UK, 198 × 129 mm, "HARRY POTTER" on the verso, a drop capital, no images.
- **Children's books**: 14/22 to 16/26 Sassoon Primary; Puffin middle grade 13/16 to 15/22.
- **Scholarly**: displayed quotations from about 50 words (*New Hart's*) or 100 words (Chicago); verse centred on its longest line on each page; a run-on index (Chicago's run-in style) in two columns. The `scholarly-monograph` look.

### Technical

- **Bell Labs troff books** (K&R 1978, *The UNIX Programming Environment*, *The AWK Programming Language*): one house layout across three typesetters, Times 11 on 12 on a 4.8 in measure, Courier near 9 on 10 indented 0.5 in, the running head 32 pt above the first line. The `troff` look.
- **O'Reilly**: 1990s ITC Garamond in gtroff; 2000s Birka and Myriad Condensed; a 2018 Animal book is Minion Pro 10.5/12.6 on a 7 × 9.1875 in page with 1 in margins both sides, Ubuntu Mono 8.5/10.2 indented 17 pt, a running foot and no running head. The `tech-book` look.
- **DEC (DECdocument)**: Letter, New Century Schoolbook 10/12 ragged, Helvetica Bold heads hung an inch left of the body, folios "1–8 Title". **IBM (SCRIPT/VS)**: Letter, a 1 in bind margin, a 6 in line, flush-left heads over an offset body.
- **The TeXbook** ([manmac.tex](https://mirrors.ctan.org/macros/plain/base/manmac.tex)): 29 × 44 pc, 3 pc indent, inch-high chapter numbers, the folio hung outside. **Tufte**: a 26 pc column, a 12 pc margin column, 10/14 body, 8/10 notes.
- **Documentation sites**: a system sans at 16 px, 1.5 to 1.75 leading, a 750–800 px measure (85–95 characters); Stripe's runs to about 104.
- **Man pages**: bold for literals, italic for what is replaced; groff still underlines italics on terminals by default, though nearly every current emulator shows real italics.

### Addressed texts

One machine serves Bibles, statutes, critical editions, dictionaries and hymnals: marks in the text, numbers in the margin, several note streams, running heads computed from the first and last address on the page (or the current one), and a baseline grid for thin paper.

- **Bibles**: chapters traditionally credited to Langton at Paris (contested); Estienne's verse numbers (1551). The Cambridge Clarion: 8.75 Lexicon No. 1 on about 10.5, light verse numbers, lines matched back to back. The ESV Reader's Bible: verse numbers hidden, chapter numbers in the margin, a running head giving the verse range from hidden anchors. PTXprint's centre column stacks notes in caller order in a 60 pt gutter rather than setting each beside its verse ([ptx-note-style.tex](https://github.com/sillsdev/ptx2pdf/blob/d42210ef5af16150551efa48cddbbcb1970482e1/src/ptx-note-style.tex#L1254-L1325)); ptome sets each beside its verse. The `reference-bible` and `readers-bible` looks; the study Bible in doc/study-bible.md.
- **Qur'an**: the Madina mushaf's 604 pages of 15 lines are ayah-aligned by construction. **Talmud**: a main block with Rashi and Tosafot around it and keyed minor apparatus.
- **US law**: the US Code in Ionic 8/9 in two columns of about 17½ pc (`us-code`); bills on a 26 pt grid numbering every line it holds (25 usually, 26 after a heading). **UK**: bills number every fifth line in italic on the right; Acts to 2000 carry outer sidenotes, from 2001 bold headings with hanging numbers (`uk-act`). **EU**: the Official Journal went from two columns to one on 1 April 2014 (`eu-journal`).
- **Courts**: the Supreme Court's booklet, 6⅛ × 9¼ in, Century 12 with at least 2 pt of lead, notes 10, a text field of 4⅛ × 7⅛ in ([Rules](https://www.supremecourt.gov/filingandrules/2023RulesoftheCourt.pdf)); California pleading, at least three numbered lines an inch at the left margin, the court's title on line 8 ([rule 2.108](https://courts.ca.gov/cms/rules/index/two/rule2_108)). The `scotus-booklet` and `pleading` looks.
- **Critical editions**: every fifth line numbered (reledmac's default), counted per Stephanus section (Burnet's Plato) or per Bekker line; no in-text bars; the apparatus at the foot. The `critical-edition` look.
- **Dictionaries**: guide words; Webster's divided page; Collins at 72% word spacing on a fixed grid. Britannica's running head is the article current at the page's top.
- **Hymnals and psalters**: the tune line, stanzas numbered from 2, the half-verse mark a colon in the English book and an asterisk in the American.

### Magazines and newspapers

Vignelli's canon: narrow outer margins, 2 to 4 columns for a book and 6 or more for a newspaper, gutters a line of type wide, type tied to measure (8/9 to 10/11 up to 70 mm, 12/13 to 14/16 up to 140 mm), flush left ([Vignelli Canon](https://www.rit.edu/vignellicenter/sites/rit.edu.vignellicenter/files/documents/The%20Vignelli%20Canon.pdf)). The anatomy has a machine vocabulary (IPTC NITF: `hl1`, `hl2`, byline, dateline) and a historical one (hed, dek, lede, kicker, nut graf). The magazine looks and doc/magazine.md.

## Named looks

A look is a parameter file over three levels, tokens, role styles and templates, as asciidoctor-pdf's `extends`, Quarto's brand file and DocBook's parameters, attribute sets and templates all layer them. The built-in looks and what they follow are in doc/looks.md; the recipes measured but not yet shipped are listed here as the work queue for themes.

| Recipe | Distinguishing values |
| --- | --- |
| Penguin Classics | 10.25/12.25 Sabon; heads 8.25, folios 8.5; heading space in lines; asterisk breaks; letterspaced small-cap heads (the `trade-novel` look) |
| Harry Potter, Scholastic US | 12 pt Garamond; "CHAPTER n", vignette slot, title, initial; a three-star running-head ornament |
| Early reader | 14/22 to 16/26; leading ratio about 1.6 (1.1 to 2.0) |
| DEC manual | Letter; New Century Schoolbook 10/12 ragged at 162 pt; heads hung at 90 pt; "1–8 Title" foot |
| IBM 3820 manual | Letter; 1 in bind; 6 in line; flush-left heads over an offset body |
| The TeXbook | 29 × 44 pc; 3 pc indent; inch-high chapter numbers; hung folio |
| Pragmatic Bookshelf | 7.5 × 9 in; Bookman Light 9.7 (TeX Gyre Bonum); Myriad heads; mono at 7.76 |
| Tufte | 26 pc text, 12 pc margin column; 10/14 body, 8/10 notes; small-caps openers |
| Federal Register | three 14¼ pc columns; Melior 9/10 ragged |
| US bill | 26 pt grid; every line numbered, restarting per page; DeVinne 14 (the `us-bill` look) |
| UK bill | every fifth line numbered right in italic 9 pt; Book Antiqua 11 on 12 or 13.3 (the `uk-bill` look) |
| Loeb facing pages | original verso, translation recto; recto head with the line range |
| Dictionary | three columns; guide words; divided page; key strip |
| Mushaf | fixed 15-line pages of whole ayahs (needs line data and RTL) |
