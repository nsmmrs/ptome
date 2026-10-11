# The units corpus: sources and licenses

Real documents written in numbered units (`doc/units.md`), the units
feature's large test: `test/units/corpus_model_test.dart` reads each and
compares its units model with `model/`. They came from the loci
experiment (retired 2026-10-11), each imported from a pinned source and
checked against the source's own numbering. The ptome license (MIT) covers
ptome's code, not these texts: each is under its source's terms below, and
the folder is left out of the published package. `quotations/` quotes
the others by address.

One change from the sources: legislation.gov.uk's commentary IDs in the
Computer Misuse Act (`key-` and 32 hex digits) are written `cmt-…`, a
form no secret scanner mistakes for an API key.

## bible/kjv: the King James Version, its notes, cross-references, headings and maps

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [kjv](https://ebible.org/Scriptures/eng-kjv_usfm.zip) | text, the 1611 translators' marginal notes | Public domain (King James Version, 1769 standard text; Crown patent applies only in the UK) | `0e0359e9e488582a…` |
| [bsb](https://ebible.org/Scriptures/engbsb_usfm.zip) | section headings only | CC0-1.0 (Berean Standard Bible, dedicated to the public domain 2023-04-30) | `b77cc2d5161b0361…` |
| [xrefs](https://a.openbible.info/data/cross-references.zip) | cross-reference ranking: readers' votes (the top 3 references a verse's phrases have, with at least 4 votes) | CC-BY (OpenBible.info cross-references, seeded from the public-domain Treasury of Scripture Knowledge) | `19aafdf923275142…` |
| [places](https://raw.githubusercontent.com/openbibleinfo/Bible-Geocoding-Data/7eb18a5ee62f27b9b93bd6689ea272d76dd23b8f/data/ancient.jsonl) | map places: coordinates of ancient places | CC-BY-4.0 (OpenBible.info Bible Geocoding Data) | `b8187aa4737e8517…` |
| [land](https://raw.githubusercontent.com/nvkelso/natural-earth-vector/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_10m_land.geojson) | maps: coastlines | Public domain (Natural Earth) | `1ac90796408bc6ad…` |
| [lakes](https://raw.githubusercontent.com/nvkelso/natural-earth-vector/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_10m_lakes.geojson) | maps: lakes and inland seas | Public domain (Natural Earth) | `2d036f53dedec578…` |
| [rivers](https://raw.githubusercontent.com/nvkelso/natural-earth-vector/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_10m_rivers_lake_centerlines.geojson) | maps: rivers | Public domain (Natural Earth) | `bb854a900ecbd3b4…` |
| [phrases](https://raw.githubusercontent.com/CrossReferences-org/bible-cross-references/ab3259f89f40b9130d7923e864b26aaa1cdaf3d2/tsv/crossreferences_kjv.tsv) | cross-reference anchors: the phrase each reference belongs to | CC-BY-4.0 (CrossReferences.org: the Treasury of Scripture Knowledge anchored to KJV phrases) | `fdd80ebd94dfb59d…` |

## catechism

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [wlc](https://raw.githubusercontent.com/NonlinearFruit/Creeds.json/2ae21a4c5387ecc91f474c9d3d67c826d2a6b9d5/creeds/westminster_larger_catechism.json) | Westminster Larger Catechism with proof texts | Public domain (Westminster Assembly, 1648); Creeds.json, Unlicense | `755274a3ba67aa84…` |

## classics

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [euthyphro-en](https://raw.githubusercontent.com/PerseusDL/canonical-greekLit/01b725d835e6e733062ffd79e0efdbae1ba06e5c/data/tlg0059/tlg001/tlg0059.tlg001.perseus-eng2.xml) | Plato, Euthyphro, tr. H. N. Fowler (1914) | CC BY-SA 4.0 (Perseus Digital Library, canonical-greekLit) | `45de42bc4cf5cdeb…` |
| [euthyphro-grc](https://raw.githubusercontent.com/PerseusDL/canonical-greekLit/01b725d835e6e733062ffd79e0efdbae1ba06e5c/data/tlg0059/tlg001/tlg0059.tlg001.perseus-grc1.xml) | Plato, Euthyphro, ed. J. Burnet (1903) | CC BY-SA 4.0 (Perseus Digital Library, canonical-greekLit) | `855af2e1a7fdc511…` |
| [ethics-en](https://raw.githubusercontent.com/PerseusDL/canonical-greekLit/01b725d835e6e733062ffd79e0efdbae1ba06e5c/data/tlg0086/tlg010/tlg0086.tlg010.perseus-eng2.xml) | Aristotle, Nicomachean Ethics, tr. H. Rackham (1934) | CC BY-SA 4.0 (Perseus Digital Library, canonical-greekLit) | `48b644fdab785b6e…` |
| [ethics-grc](https://raw.githubusercontent.com/PerseusDL/canonical-greekLit/01b725d835e6e733062ffd79e0efdbae1ba06e5c/data/tlg0086/tlg010/tlg0086.tlg010.perseus-grc2.xml) | Aristotle, Nicomachean Ethics, ed. J. Bywater (1894) | CC BY-SA 4.0 (Perseus Digital Library, canonical-greekLit) | `a203a8d2e793b068…` |

## hymns

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [otterbein](https://www.gutenberg.org/cache/epub/16455/pg16455.txt) | hymns: tunes, stanzas, refrains, index of first lines | Public domain in the US (The Otterbein Hymnal, ed. E. S. Lorenz, 1892; Project Gutenberg) | `1269a64dd2e4da9d…` |

## law-eu

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [gdpr](https://publications.europa.eu/resource/celex/32016R0679) | Regulation (EU) 2016/679 (GDPR), Official Journal L 119, 4.5.2016 | © European Union, https://eur-lex.europa.eu: reuse authorised, source acknowledged (Commission Decision 2011/833/EU) | `962539af03738bf5…` |

## law-uk

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [cma](https://www.legislation.gov.uk/ukpga/1990/18/data.xml) | Computer Misuse Act 1990, as amended (revised text) | Open Government Licence v3.0 (legislation.gov.uk, Crown copyright) | `23ba5ca02cf7088d…` |

## law-us

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [usc5-551](https://www.govinfo.gov/content/pkg/USCODE-2023-title5/html/USCODE-2023-title5-partI-chap5-subchapII-sec551.htm) | 5 U.S.C. 551 | Public domain (United States Code, a work of the U.S. Government; GovInfo, U.S. Government Publishing Office) | `095b9e4fbbda9cb8…` |
| [usc5-552](https://www.govinfo.gov/content/pkg/USCODE-2023-title5/html/USCODE-2023-title5-partI-chap5-subchapII-sec552.htm) | 5 U.S.C. 552 | Public domain (United States Code, a work of the U.S. Government; GovInfo, U.S. Government Publishing Office) | `8f49ae74e3f35df5…` |
| [usc5-552a](https://www.govinfo.gov/content/pkg/USCODE-2023-title5/html/USCODE-2023-title5-partI-chap5-subchapII-sec552a.htm) | 5 U.S.C. 552a | Public domain (United States Code, a work of the U.S. Government; GovInfo, U.S. Government Publishing Office) | `fd78a1cf3483020e…` |
| [usc5-552b](https://www.govinfo.gov/content/pkg/USCODE-2023-title5/html/USCODE-2023-title5-partI-chap5-subchapII-sec552b.htm) | 5 U.S.C. 552b | Public domain (United States Code, a work of the U.S. Government; GovInfo, U.S. Government Publishing Office) | `77be9f01d0ac737b…` |
| [usc5-553](https://www.govinfo.gov/content/pkg/USCODE-2023-title5/html/USCODE-2023-title5-partI-chap5-subchapII-sec553.htm) | 5 U.S.C. 553 | Public domain (United States Code, a work of the U.S. Government; GovInfo, U.S. Government Publishing Office) | `d80e124626170f7a…` |

## liturgy

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [bcp-psalms-1](https://www.eskimo.com/~lhowell/bcp1662/psalter/psalms_1.html) | the Psalter, week 1 | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `dfe2bb3f73d9a500…` |
| [bcp-psalms-2](https://www.eskimo.com/~lhowell/bcp1662/psalter/psalms_2.html) | the Psalter, week 2 | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `9a0b09860d07e7e1…` |
| [bcp-psalms-3](https://www.eskimo.com/~lhowell/bcp1662/psalter/psalms_3.html) | the Psalter, week 3 | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `03910708b6661998…` |
| [bcp-psalms-4](https://www.eskimo.com/~lhowell/bcp1662/psalter/psalms_4.html) | the Psalter, week 4 | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `21d686ecd138ebea…` |
| [bcp-psalms-5](https://www.eskimo.com/~lhowell/bcp1662/psalter/psalms_5.html) | the Psalter, week 5 | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `2612a92c31631fae…` |
| [bcp-morning](https://www.eskimo.com/~lhowell/bcp1662/daily/morning.html) | Morning Prayer | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `7902d0a48ace50a1…` |
| [bcp-litany](https://www.eskimo.com/~lhowell/bcp1662/daily/litany.html) | the Litany | Public domain text (Book of Common Prayer, 1662), transcription by Lynda M. Howell | `bf2548c7654e048b…` |

## quran

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [quran-uthmani](https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&rub=true&tatweel=true&quranType=uthmani&outType=txt-2&agree=true) | the Arabic text | Tanzil Quran Text (Uthmani, version 1.1): verbatim copies allowed with attribution to tanzil.net; the text may not be changed | `7f30c647331a6110…` |
| [quran-pickthall](https://tanzil.net/trans/?transID=en.pickthall&type=txt-2) | the English translation | Public domain in the US (M. M. Pickthall, The Meaning of the Glorious Koran, 1930), as distributed by Tanzil.net | `4aabbfa9d96796f5…` |
| [quran-data](https://tanzil.net/res/text/metadata/quran-data.js) | surah names, juz divisions | CC-BY-3.0 (Tanzil Quran metadata) | `9e9930c592aaa34b…` |

## specs

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [cpp-basic](https://raw.githubusercontent.com/cplusplus/draft/4d8e364814c9b8ea4ce8d719ad87942ed4c63e24/source/basic.tex) | C++ working draft, [basic] (clauses basic.pre, basic.def, basic.def.odr) | The C++ working draft (cplusplus/draft); quoted for testing | `0153c6b23c94c477…` |

## suttas

| Source | Used for | License | SHA-256 |
| --- | --- | --- | --- |
| [mn1-root](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/root/pli/ms/sutta/mn/mn1_root-pli-ms.json) | mn1: root | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `bee49a5461f36eea…` |
| [mn1-html](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/html/pli/ms/sutta/mn/mn1_html.json) | mn1: html | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `4c8eb8f43b4cd585…` |
| [mn1-en](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/translation/en/sujato/sutta/mn/mn1_translation-en-sujato.json) | mn1: en | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `3190ebe594f0f47d…` |
| [mn10-root](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/root/pli/ms/sutta/mn/mn10_root-pli-ms.json) | mn10: root | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `34c9a49a84a76d70…` |
| [mn10-html](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/html/pli/ms/sutta/mn/mn10_html.json) | mn10: html | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `ad8c8c987e52d01e…` |
| [mn10-en](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/translation/en/sujato/sutta/mn/mn10_translation-en-sujato.json) | mn10: en | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `42978efcb72b20be…` |
| [dn1-root](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/root/pli/ms/sutta/dn/dn1_root-pli-ms.json) | dn1: root | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `16b1b1c26b9c3bee…` |
| [dn1-html](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/html/pli/ms/sutta/dn/dn1_html.json) | dn1: html | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `fbf06c0668afec80…` |
| [dn1-en](https://raw.githubusercontent.com/suttacentral/bilara-data/e2fb86665ea25e449ded11212d82437198b10897/translation/en/sujato/sutta/dn/dn1_translation-en-sujato.json) | dn1: en | CC0-1.0 (SuttaCentral bilara-data: Mahāsaṅgīti Pali root text; translation by Bhikkhu Sujato) | `2c94cacbe81cbf83…` |
