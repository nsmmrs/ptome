// Writes ICU's AlphabeticIndex bucket label for each line of standard
// input after the first (a BCP 47 language tag), one line each; the first
// line written lists the index's labels, separated by spaces.
#include <unicode/alphaindex.h>
#include <unicode/locid.h>
#include <unicode/unistr.h>
#include <iostream>
#include <string>
int main () {
  std::string tag;
  if (!std::getline (std::cin, tag)) return 1;
  UErrorCode status = U_ZERO_ERROR;
  icu::Locale locale = icu::Locale::forLanguageTag (tag, status);
  icu::AlphabeticIndex index (locale, status);
  if (U_FAILURE (status)) { std::cerr << u_errorName (status) << "\n"; return 1; }
  std::string labels;
  index.resetBucketIterator (status);
  while (index.nextBucket (status)) {
    if (index.getBucketLabelType () != U_ALPHAINDEX_NORMAL) continue;
    std::string label;
    index.getBucketLabel ().toUTF8String (label);
    labels += (labels.empty () ? "" : " ") + label;
  }
  std::cout << labels << "\n";
  std::string line;
  while (std::getline (std::cin, line)) {
    icu::UnicodeString text = icu::UnicodeString::fromUTF8 (line);
    int32_t bucket = index.getBucketIndex (text, status);
    index.resetBucketIterator (status);
    std::string label;
    for (int32_t i = 0; index.nextBucket (status); i++) {
      if (i == bucket) {
        if (index.getBucketLabelType () == U_ALPHAINDEX_NORMAL) index.getBucketLabel ().toUTF8String (label);
        break;
      }
    }
    std::cout << label << "\n";
  }
}
