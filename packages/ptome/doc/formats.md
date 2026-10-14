# What each format does with a book

Ptome writes a book as a PDF, a single HTML page, a website
(`multipage_html5`), an EPUB 3 and DocBook 5 (and man pages, for the
`manpage` doctype). ADR-0012 sets the goal: every feature of a book
works in every format, in the form that format's readers expect, unless
the medium has no place for it. This table records where each one is. A
**gap** is a feature a format should have and doesn't yet; lane epic
EPIC-m31mf9 has a card for each. *n/a* is a
feature the format has no use for.

| Feature | PDF | HTML | Website | EPUB 3 | DocBook 5 |
| --- | --- | --- | --- | --- | --- |
| Index (`[index]`, `((term))`) | page numbers | links to sections, by letter | its own page, links across pages | links, by letter, as an EPUB index (`epub:type`, a landmark) | `<indexterm>`, `<index/>` |
| Index order and headings (`index-category-headings`) | the attributes, or theme keys | the attributes | the attributes | the attributes | the processor's |
| Contents (`:toc:`, `toc::[]` in a section) | yes | yes | a page of its own | navigation; `toc::[]` lists the contents there | a chapter of `toc::[]` alone is `<toc>` |
| `%notoc` sections | yes | yes | yes | yes | n/a |
| Footnotes | bottom of the page | end of the page | end of each page | pop-up notes | `<footnote>` |
| Footnote marker templates | the attributes, or theme keys | attributes | attributes | attributes | n/a |
| Callouts linked both ways | always | `callout-links` | `callout-links` | `callout-links` | `<co>`, `<calloutlist>` |
| Caption templates, `<kind>-numbering: all`, `%unnumbered` | yes | yes | yes | yes | titles (the processor numbers) |
| Text files as images (`image::art.txt[]`) | the text, in the code font | the text, `<pre>` in the image block | same | same, the file not packed | `<literallayout>` in the media object |
| Figure placement (`placement=`, `image_placement`) | floats | n/a | n/a | n/a | `floatstyle` (`before`, `none`) |
| Keep together (`%unbreakable`) | yes | class `unbreakable` (the house stylesheet: `break-inside: avoid`) | same | same | `<?dbfo keep-together="always"?>` |
| Hyphenation (`:hyphens:`) | patterns, 72 languages | CSS `hyphens: auto` (the house look's prose without it too; off with `:hyphens!:`) | same | same | n/a |
| Roles for text (`[.sc]#...#`) | theme `role_<role>_*` | CSS (the author's) | CSS | CSS | `role` attribute |
| Built-in roles (`small-caps`, `big`, `small`, colors) | `small-caps` in the house look (`.small-caps`, `role_small-caps_font_variant`) | colors, sizes; `small-caps` in the house stylesheet | same | same | `role` attribute |
| Section roles (a boxed `[.html-note]`) | theme `section_role_<role>_*` | class (CSS) | class | class | `role` |
| Source highlighting | plain_highlighting | plain_highlighting | plain_highlighting | plain_highlighting | `language` |
| Math (`stem:[]`) | AsciiMath and LaTeX typeset (OpenType MATH) | MathJax | MathJax | MathML for AsciiMath; LaTeX as source | MathML for AsciiMath; LaTeX in `<alt>` |
| Cover (`front-cover-image`) | cover page | before the header | on the home page | cover | `<cover>` |
| Title page, dedication, colophon | yes | headings | pages | pages, with landmarks | `<dedication>`, `<colophon>` |
| Book metadata (`isbn`, `editor`, `copyright`) | XMP (`dc:identifier`, `dc:contributor`, `dc:rights`) | `<meta>` (author, copyright) | same | OPF | `<info>` (`biblioid`, `editor`, `copyright`) |
| Running heads, page numbers | yes | n/a | n/a | the print pages' markers and `page-list`, from the PDF's page map (`epub-page-map`) | n/a |
| Page paths (`page-path`) | n/a | n/a | yes | n/a | n/a |
| Show link URIs (`show-link-uri`) | footnote or after | n/a | n/a | n/a | n/a |
| Help text lists the backend | yes | yes | yes | yes | yes |

## Man pages

The `manpage` output is Asciidoctor's, byte for byte: links as its own
`.URL` and `.MTO` macros, list items as a hand-made hanging indent for
terminals, a description list's terms as plain lines. Through mandoc
(`man`'s HTML, `mandoc -T html`) that makes links that don't click, list
numbers run into their text ("1.First step") and terms without anchors.
`:man-semantic:` writes man(7)'s own macros instead: `.UR`/`.UE` and
`.MT`/`.ME` for links (groff 1.24 makes OSC 8 links of them in a
terminal), `.IP` for list items, `.TP` for a description list's entries
(each an anchor in mandoc's HTML), inside `.RS 0`/`.RE` so the text after
the list goes back to the margin. Never under `asciidoctor-compat`.

## Fonts

No format's fonts are compiled into Ptome. The PDF uses the fonts its
theme names from those installed on the machine (`doc/pdf.md`, Fonts);
`ptome doctor` installs the built-in themes'. An EPUB embeds no fonts
unless `-a epub-embed-fonts` is set: its stylesheet names Noto Serif, M+
1p and M+ 1mn and the reading system's fonts apply (its font icons are
shown as text); with the attribute, the fonts it names are embedded from
the installed ones. HTML and the website name their stylesheet's fonts,
as Asciidoctor's do.

## Languages

The generated text follows the document's `lang`: the table of contents'
title, the captions (`Figure`, `Table`, `Example`, `Listing` where turned
on), the admonitions' labels, `Appendix`, `Chapter` where the language
has a word for it, the last-update and version labels, in every format.
They are Asciidoctor's own translations, its 35 locale files
(`data/locale/attributes-<lang>.adoc`), which Asciidoctor leaves the
author to include: Ptome reads the language's file once the header is
parsed. A region or script picks its file (`zh-TW`, `zh-Hant` and `zh-HK`
Traditional Chinese, other `zh` Simplified; `sr-Latn`; `pt-BR`; `no` as
`nb`); a language without one keeps the English labels. A label the
author sets in the header, or from the API or the command line, is kept;
one the file sets only when turned on (`:listing-caption:`) is
translated when it is turned on, empty or in English. An index's
cross-references use the language's words too (`siehe`, `siehe auch`;
`voir`, `voir aussi`; `见`, `参见`...), or the document's
`index-see-label` and `index-see-also-label`. `:locale-labels: false`
keeps the English; nothing changes under `asciidoctor-compat` (any
format), unless `:locale-labels: true`.

The numbers a document generates are written in its language's digits,
the numbering system CLDR (48.2) gives the language: Arabic-Indic digits
(`١٢٣`) in Egyptian, Saudi and most other regional Arabic (`ar-EG`;
Arabic as such, `ar`, and Maghrebi Arabic keep 0 to 9, as CLDR has
them), Persian digits (`۱۲۳`) in Persian and Pashto, Devanagari in
Marathi and Nepali, Bengali in Bengali and Assamese, Burmese, Tibetan in
Dzongkha. Section numbers, caption numbers (`جدول ١`), footnote numbers
and numbered lists take them in every format, and the PDF's page
numbers, table of contents and index too. `:numbering-system:` names
another (CLDR's ids: `latn`, `arab`, `arabext`, `deva`, `hanidec`,
`fullwide`...), as does a `-u-nu-` extension of `lang` (`ar-u-nu-arab`);
the text's own digits are left as written. An ordered list can be
numbered in any counter style CSS defines, its name as the list's style:
`[hiragana]`, `[katakana-iroha]`, `[cjk-ideographic]`,
`[simp-chinese-formal]`, `[japanese-informal]`, `[korean-hangul-formal]`,
`[hebrew]`, `[armenian]`, `[georgian]`, `[lower-russian]`,
`[arabic-abjad]`, `[devanagari]`, `[thai]`, `[ethiopic-numeric]`... (CSS
Counter Styles Level 3's and the W3C's Ready-made Counter Styles, 203 in
all), with the style's own suffix (`あ、`, `а)`); HTML and EPUB write
CSS's `list-style-type`, with a `@counter-style` rule for a style
browsers don't predefine (checked with epubcheck). `:sectnums-style:`
numbers the sections in one (`upper-roman`: `II.I`). Not under
`asciidoctor-compat`.

`:line-break:` (`strict`, `normal`, `loose`, `anywhere`) sets how
strictly lines break around East Asian punctuation and small kana, as
CSS Text 3's `line-break`: HTML and EPUB write the property, the PDF
breaks so itself (its theme's `base_line_break` winning; `doc/pdf.md`).
Not under `asciidoctor-compat`.

Dates are shown as the language writes them: the footer's "Last
updated" date and time and an ISO `revdate` (`v1.0, 2026-10-14`) in the
header, on the title page and the PDF's, in CLDR's (48.2) patterns and
names for `lang` (`2026年10月14日`, `14. Oktober 2026`,
`mercredi 14 octobre 2026`, `١٤ أكتوبر ٢٠٢٦`), the time in its long
format with the zone's offset (`17:46:40 GMT+9`), the digits the
document's numbering system's (above). `:date-format:` chooses the
length: `short` (`14.10.26`), `medium`, `long` (the default in a
document whose language isn't English), `full` (with the weekday), or
`iso` (as written, the default in English). `:calendar:` (or `lang`'s
`-u-ca-`, `ja-u-ca-japanese`) shows them in another calendar: `japanese`
(`令和8年10月14日`, `October 14, 8 Reiwa`), `buddhist` (`14 ตุลาคม 2569`),
`roc` (`民國115年10月14日`), `hebrew` (`ג׳ בחשוון תשפ״ז`), `persian`
(`۲۲ مهر ۱۴۰۵`), `islamic-umalqura`, `islamic-civil`, `islamic-tbla`,
`islamic` (by the new moons), `coptic`, `ethiopic`, `ethioaa`, `indian`,
`chinese` (`2026丙午年九月初五`) or `dangi`, long by default in any
language; else, or for a name it doesn't know, the Gregorian.
The attributes themselves (`docdate`, `docdatetime`, `localdate`...)
stay ISO, as an EPUB's metadata and programs read them, and a `revdate`
that isn't an ISO date is shown as written. Not under
`asciidoctor-compat`.

AsciiDoc's typographic quotes (`"`text`"` and `'`text`'`) are set in the
marks of the text's language, CLDR's (48.2): `„text“` and `‚text‘` in
German, `«text»` in French, `「text」` and `『text』` in Japanese and in
Traditional Chinese, `“text”` in English and Simplified Chinese. The
double quotes take the language's outer pair, the single ones its inner
pair. The language is a block's `lang` attribute, else the document's
`lang`; a language CLDR doesn't have, or none, keeps Asciidoctor's
English marks. HTML, the website, EPUB and the PDF write the marks
themselves, a man page as roff's Unicode escapes (`\[u201E]`); DocBook
keeps its `<quote>` element, which DocBook's own stylesheets localize. A
span's `lang` (`[lang=ja]#...#`) doesn't change the quotes inside it. In
the PDF the theme's `quotes` key, where it sets one, wins. Not under
`asciidoctor-compat`.

French text (`lang` `fr`, `fr-FR`, `fr-BE`, `fr-CH`...) gets the
no-break spaces of French typography, after the Imprimerie nationale's
*Lexique des règles typographiques*: a narrow one (U+202F) before `;`, `!`
and `?`, a full one (U+00A0) before `:` and inside guillemets
(`« ici »`); a space typed there becomes the no-break one, and a line
never breaks at it. Canadian French (`fr-CA`), after the OQLF's *Banque de
dépannage linguistique*, has them before `:` and inside guillemets only.
Only punctuation ending a word is spaced (`10:30`, `std::vector` and
`?x=1` in a URL are not), and verbatim text never is. A man page writes
them as roff's `\~`. Not under `asciidoctor-compat`.

A block's own `lang` and direction reach HTML and EPUB too: a block with
`[lang=ar]` or `[dir=rtl]` above it writes `lang` and `dir` on its
element (`dir` where it runs the other way from the document, its `lang`
written right to left or left to right), and a span's (`[lang=fr]#…#`,
`[dir=rtl]#…#`) on a `<span>`. Not under `asciidoctor-compat`.

A document's direction and writing mode reach HTML and EPUB too.
`:dir: rtl` writes `dir="rtl"` on each page's root, and an EPUB's pages
turn to the left (its spine's `page-progression-direction="rtl"`).
`:writing-mode: vertical-rl` (or `vertical-lr`) sets the text in vertical
lines with CSS's `writing-mode` (and the `-epub-` and `-webkit-` prefixes
older reading systems read): tables, listings and literal blocks stay
across, upright in the columns; numbers of one or two digits stand
across their line (tate-chu-yoko, as `<span class="tcy">`, CSS's
`text-combine-upright: all`); a vertical-rl EPUB's pages turn to the
left. The roles `vertical-rl`, `vertical-lr` and `horizontal-tb` set a
block's own writing mode, and `tcy` any short text across its line, in
every format. The PDF reads `:writing-mode:` where its theme sets no
`page_writing_mode`. Checked with epubcheck 5.4 and in Vivliostyle. Not
under `asciidoctor-compat`.
