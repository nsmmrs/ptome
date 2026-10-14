// Prints ICU's line break positions (in UTF-16 code units) of each line
// of standard input.
#include <unicode/brkiter.h>
#include <unicode/unistr.h>
#include <unicode/locid.h>
#include <iostream>
#include <string>
int main (int argc, char **argv) {
  UErrorCode status = U_ZERO_ERROR;
  icu::BreakIterator *bi = icu::BreakIterator::createLineInstance (icu::Locale (argc > 1 ? argv[1] : "th"), status);
  if (U_FAILURE (status)) { std::cerr << "no break iterator\n"; return 1; }
  std::string line;
  while (std::getline (std::cin, line)) {
    icu::UnicodeString s = icu::UnicodeString::fromUTF8 (line);
    bi->setText (s);
    bool first = true;
    for (int32_t p = bi->first (); p != icu::BreakIterator::DONE; p = bi->next ()) {
      std::cout << (first ? "" : " ") << p; first = false;
    }
    std::cout << "\n";
  }
  delete bi;
}
