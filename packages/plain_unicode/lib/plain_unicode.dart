/// plain_unicode: Unicode text algorithms in pure Dart, the same on every
/// platform, generated from the Unicode Character Database.
///
/// - Line breaking (UAX #14, Unicode 18.0.0): the break opportunities of a
///   text and each code point's line break class; Thai, Lao, Khmer and
///   Myanmar broken between their words as ICU 78.3 breaks them.
/// - Bidirectional text (UAX #9, Unicode 18.0.0): each character's
///   embedding level in its paragraph, a line's visual order, and the
///   Bidi_Class, Bidi_Mirroring_Glyph and Joining_Type properties.
/// - Full case mapping (Unicode 17.0.0): `upperCase` and `lowerCase`, with
///   the special mappings (`ß` to `SS`) and, on request, the Final_Sigma
///   rule; Turkish, Azeri and Lithuanian tailorings by language.
/// - Collation (UTS #10, CLDR 48.2): `Collator`, strings ordered as a
///   language orders them, and an index's headings.
/// - Quotation marks by language (CLDR 48.2): `quotationMarks`.
/// - Counter styles (CSS Counter Styles Level 3 and the W3C's Ready-made
///   Counter Styles): numbers written in a script's numerals or letters
///   (`CounterStyle`), and the numbering system a language writes its
///   numbers in by default (CLDR 48.2): `defaultNumberingSystem`.
/// - Dates and times as a language writes them (CLDR 48.2, Gregorian):
///   `formatDate`, `formatTime` and `formatDateTime`.
/// - Emoji (UTS #51, Unicode 18.0.0): the emoji properties and where an
///   emoji presentation sequence (a flag, a ZWJ sequence...) starts and
///   ends: `emojiSequenceLength`.
library;

export 'src/bidi.dart'
    show
        BidiClass,
        BidiText,
        JoiningType,
        TextDirection,
        bidiClass,
        bidiMirror,
        canonicalCombiningClass,
        hasRightToLeft,
        joiningType,
        reorderRuns;
export 'src/bidi_data.g.dart' show bidiUnicodeVersion;
export 'src/case.dart' show isCaseIgnorable, isCased, lowerCase, upperCase;
export 'src/case_data.g.dart' show caseMappingUnicodeVersion;
export 'src/collation.dart' show CollationKey, Collator;
export 'src/counter_styles.dart'
    show
        CounterStyle,
        defaultNumberingSystem,
        formatDigits,
        numberingSystemDigits;
export 'src/date_format.dart'
    show DateStyle, formatDate, formatDateTime, formatTime;
export 'src/emoji.dart' show emojiSequenceLength;
export 'src/line_break.dart'
    show
        LineBreak,
        LineBreakClass,
        LineBreakOffsets,
        LineBreakStrictness,
        lineBreakClass,
        lineBreakOffsets,
        lineBreaks;
export 'src/line_break_data.g.dart' show lineBreakUnicodeVersion;
export 'src/properties.dart'
    show
        GeneralCategory,
        IndicPositionalCategory,
        IndicSyllabicCategory,
        VerticalOrientation,
        canonicalComposition,
        canonicalDecomposition,
        generalCategory,
        indicPositionalCategory,
        indicSyllabicCategory,
        isDefaultIgnorable,
        isEmoji,
        isEmojiModifier,
        isEmojiModifierBase,
        isEmojiPresentation,
        isExtendedPictographic,
        isMark,
        propertiesUnicodeVersion,
        scriptOf,
        verticalOrientation;
export 'src/quotation_marks.dart' show QuotationMarks, quotationMarks;
