// Prints ICU's full case mapping of each line of standard input, a
// language and a mapping before it ("tr<TAB>upper<TAB>text"), one line
// each: u_strToUpper / u_strToLower with the language as the locale.
#include <unicode/ustring.h>
#include <unicode/unistr.h>
#include <iostream>
#include <string>
#include <vector>
int main () {
  std::string line;
  while (std::getline (std::cin, line)) {
    auto t1 = line.find ('\t'), t2 = line.find ('\t', t1 + 1);
    std::string lang = line.substr (0, t1), mode = line.substr (t1 + 1, t2 - t1 - 1);
    icu::UnicodeString s = icu::UnicodeString::fromUTF8 (line.substr (t2 + 1));
    std::vector<UChar> out (s.length () * 4 + 16);
    UErrorCode status = U_ZERO_ERROR;
    int32_t n = mode == "upper"
        ? u_strToUpper (out.data (), (int32_t) out.size (), s.getBuffer (), s.length (), lang.c_str (), &status)
        : u_strToLower (out.data (), (int32_t) out.size (), s.getBuffer (), s.length (), lang.c_str (), &status);
    if (U_FAILURE (status)) { std::cout << "ERROR\n"; continue; }
    std::string utf8;
    icu::UnicodeString (out.data (), n).toUTF8String (utf8);
    std::cout << utf8 << "\n";
  }
}
