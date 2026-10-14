// Prints ICU's formatting of a date and time for each line of standard
// input: a BCP 47 language tag, a date style and a time style (none,
// short, medium, long, full), milliseconds since the epoch and an offset
// from UTC in minutes, and optionally a calendar (BCP 47's name: japanese,
// buddhist), separated by tabs; one line each, the date and time as
// DateFormat::createDateTimeInstance formats them in that calendar (the
// tag's -u-ca-; the Gregorian by default), in a time zone of that
// fixed offset that has no name (so its localized GMT offset shows). A
// locale ICU's data lacks falls back to the root, as CLDR's inheritance
// has it, not to the default locale. A line `?tag` asks whether ICU's data
// has the tag's locale itself (1 or 0).
#include <unicode/datefmt.h>
#include <unicode/locid.h>
#include <unicode/ures.h>
#include <unicode/simpletz.h>
#include <unicode/timezone.h>
#include <unicode/unistr.h>
#include <cstdio>
#include <iostream>
#include <sstream>
#include <string>
static icu::DateFormat::EStyle style (const std::string &name) {
  if (name == "short") return icu::DateFormat::kShort;
  if (name == "medium") return icu::DateFormat::kMedium;
  if (name == "long") return icu::DateFormat::kLong;
  if (name == "full") return icu::DateFormat::kFull;
  return icu::DateFormat::kNone;
}
int main () {
  UErrorCode init = U_ZERO_ERROR;
  icu::Locale::setDefault (icu::Locale::getRoot (), init);
  std::string line;
  while (std::getline (std::cin, line)) {
    if (!line.empty () && line[0] == '?') {
      UErrorCode status = U_ZERO_ERROR;
      icu::Locale locale = icu::Locale::forLanguageTag (line.substr (1), status);
      UResourceBundle *bundle = ures_openDirect (nullptr, locale.getName (), &status);
      std::cout << (U_SUCCESS (status) ? "1" : "0") << "\n";
      if (bundle) ures_close (bundle);
      continue;
    }
    std::istringstream in (line);
    std::string tag, date, time, millis, offset, calendar;
    std::getline (in, tag, '\t');
    std::getline (in, date, '\t');
    std::getline (in, time, '\t');
    std::getline (in, millis, '\t');
    std::getline (in, offset, '\t');
    if (!std::getline (in, calendar, '\t') || calendar.empty ()) calendar = "gregory";
    UErrorCode status = U_ZERO_ERROR;
    icu::Locale locale = icu::Locale::forLanguageTag (tag + "-u-ca-" + calendar, status);
    if (U_FAILURE (status)) { std::cout << "ERROR\n"; continue; }
    icu::DateFormat *format = icu::DateFormat::createDateTimeInstance (style (date), style (time), locale);
    if (!format) { std::cout << "ERROR\n"; continue; }
    int minutes = std::stoi (offset);
    format->adoptTimeZone (new icu::SimpleTimeZone (minutes * 60000, "Custom"));
    icu::UnicodeString out;
    format->format ((UDate) std::stod (millis), out);
    std::string utf8;
    out.toUTF8String (utf8);
    std::cout << utf8 << "\n";
    delete format;
  }
}
