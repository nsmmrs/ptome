/// plain_unicode: Unicode text algorithms in pure Dart, the same on every
/// platform, generated from the Unicode Character Database.
///
/// - Line breaking (UAX #14, Unicode 18.0.0): the break opportunities of a
///   text and each code point's line break class.
/// - Bidirectional text (UAX #9, Unicode 18.0.0): each character's
///   embedding level in its paragraph, a line's visual order, and the
///   Bidi_Class, Bidi_Mirroring_Glyph and Joining_Type properties.
/// - Full case mapping (Unicode 17.0.0): `upperCase` and `lowerCase`, with
///   the special mappings (`ß` to `SS`) and, on request, the Final_Sigma
///   rule.
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
        joiningType,
        reorderRuns;
export 'src/bidi_data.g.dart' show bidiUnicodeVersion;
export 'src/case.dart' show isCaseIgnorable, isCased, lowerCase, upperCase;
export 'src/case_data.g.dart' show caseMappingUnicodeVersion;
export 'src/line_break.dart'
    show
        LineBreak,
        LineBreakClass,
        LineBreakOffsets,
        lineBreakClass,
        lineBreakOffsets,
        lineBreaks;
export 'src/line_break_data.g.dart' show lineBreakUnicodeVersion;
