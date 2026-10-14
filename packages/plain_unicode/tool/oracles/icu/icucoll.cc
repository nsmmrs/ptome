// Sorts standard input's lines (after the first, a BCP 47 language tag
// such as "de" or "zh-u-co-stroke") with ICU's collator for that
// language at identical strength (its tertiary order, then the code
// points), and writes them in order, one line each, after a first line
// naming the locale whose collation ICU's data had.
#include <unicode/coll.h>
#include <unicode/locid.h>
#include <unicode/unistr.h>
#include <algorithm>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
int main () {
  std::string tag;
  if (!std::getline (std::cin, tag)) return 1;
  UErrorCode status = U_ZERO_ERROR;
  icu::Locale locale = icu::Locale::forLanguageTag (tag, status);
  std::unique_ptr<icu::Collator> collator (icu::Collator::createInstance (locale, status));
  if (U_FAILURE (status)) { std::cerr << u_errorName (status) << "\n"; return 1; }
  collator->setStrength (icu::Collator::IDENTICAL);
  std::cout << collator->getLocale (ULOC_ACTUAL_LOCALE, status).getName () << "\n";
  std::vector<icu::UnicodeString> lines;
  std::string line;
  while (std::getline (std::cin, line)) lines.push_back (icu::UnicodeString::fromUTF8 (line));
  std::stable_sort (lines.begin (), lines.end (), [&] (const icu::UnicodeString &a, const icu::UnicodeString &b) {
    UErrorCode s = U_ZERO_ERROR;
    return collator->compare (a, b, s) < 0;
  });
  for (auto &l : lines) {
    std::string out;
    l.toUTF8String (out);
    std::cout << out << "\n";
  }
}
