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
