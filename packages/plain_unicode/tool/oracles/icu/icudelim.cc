// Prints ICU's quotation marks for each BCP 47 language tag of standard
// input, one line each: the quotation start and end and the alternate
// start and end, separated by tabs (ulocdata_getDelimiter, CLDR's
// delimiters, the locale from uloc_forLanguageTag), and the locale ICU's
// data had them from.
#include <unicode/ulocdata.h>
#include <unicode/uloc.h>
#include <unicode/ures.h>
#include <unicode/unistr.h>
#include <iostream>
#include <string>
int main () {
  std::string line;
  const ULocaleDataDelimiterType types[] = {
    ULOCDATA_QUOTATION_START, ULOCDATA_QUOTATION_END,
    ULOCDATA_ALT_QUOTATION_START, ULOCDATA_ALT_QUOTATION_END};
  while (std::getline (std::cin, line)) {
    char locale[ULOC_FULLNAME_CAPACITY];
    UErrorCode status = U_ZERO_ERROR;
    uloc_forLanguageTag (line.c_str (), locale, sizeof locale, nullptr, &status);
    ULocaleData *data = ulocdata_open (locale, &status);
    if (U_FAILURE (status)) { std::cout << "ERROR\n"; continue; }
    for (int i = 0; i < 4; i++) {
      UChar buffer[16];
      int32_t n = ulocdata_getDelimiter (data, types[i], buffer, 16, &status);
      std::string utf8;
      icu::UnicodeString (buffer, n).toUTF8String (utf8);
      std::cout << (i ? "\t" : "") << utf8;
    }
    UResourceBundle *bundle = ures_open (nullptr, locale, &status);
    const char *actual = ures_getLocaleByType (bundle, ULOC_ACTUAL_LOCALE, &status);
    std::cout << "\t" << (actual ? actual : "") << "\n";
    ures_close (bundle);
    ulocdata_close (data);
  }
}
