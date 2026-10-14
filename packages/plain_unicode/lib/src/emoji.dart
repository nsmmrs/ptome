/// Emoji sequences (UTS #51): where text shows as an emoji.
library;

import 'package:plain_unicode/src/properties.dart';

/// The number of code points of the emoji presentation sequence that
/// starts at [at] in [runes], 0 where none does: UTS #51's possible emoji
/// (ED-17: elements joined by U+200D ZWJ, each a pair of regional
/// indicators, or an emoji character with U+FE0F, a keycap's U+20E3, a
/// skin tone or a tag sequence after it) that is shown as an emoji: one
/// with more than one element, a flag, a keycap, a skin tone, a tag
/// sequence or U+FE0F, or one emoji character shown as an emoji by
/// default (Emoji_Presentation) without U+FE0E after it.
int emojiSequenceLength(List<int> runes, int at) {
  final n = runes.length;
  var i = at;
  var elements = 0;
  var emoji = false;
  bool regional(int r) => r >= 0x1f1e6 && r <= 0x1f1ff;
  bool tag(int r) => r >= 0xe0020 && r <= 0xe007e;
  bool startsElement(int i) =>
      i < n &&
      (regional(runes[i]) ||
          isEmoji(runes[i]) ||
          isExtendedPictographic(runes[i]));
  while (true) {
    if (i + 1 < n && regional(runes[i]) && regional(runes[i + 1])) {
      i += 2;
      emoji = true;
    } else if (startsElement(i) && !regional(runes[i])) {
      var shown = isEmojiPresentation(runes[i]);
      i++;
      if (i < n && runes[i] == 0xfe0e) {
        shown = false;
        i++;
      } else if (i < n && runes[i] == 0xfe0f) {
        shown = true;
        i++;
      }
      if (i < n && (runes[i] == 0x20e3 || isEmojiModifier(runes[i]))) {
        shown = true;
        i++;
      }
      if (i < n && tag(runes[i])) {
        var j = i;
        while (j < n && tag(runes[j])) {
          j++;
        }
        if (j < n && runes[j] == 0xe007f) {
          i = j + 1;
          shown = true;
        }
      }
      if (shown) emoji = true;
    } else {
      break;
    }
    elements++;
    if (i + 1 < n && runes[i] == 0x200d && startsElement(i + 1)) {
      i++;
      continue;
    }
    break;
  }
  if (elements == 0) return 0;
  return emoji || elements > 1 ? i - at : 0;
}
