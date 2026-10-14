"""Writes vendor/cldr/48.2.0/gregorian.tsv from CLDR's common/main/*.xml.

Each locale's Gregorian calendar fields that it defines itself (not those
it inherits, marked or left out): the wide and abbreviated month and day
names of the format context, the AM and PM markers, the abbreviated eras,
the date, time and date-time patterns of each length, and the localized
GMT formats of its time zone names. Draft values below "contributed" are
left out, as ICU's data build leaves them out.

    python3 -I tool/import_cldr_gregorian.py CLDR_COMMON_DIR

lib/src/date_format.dart resolves them through CLDR's parent locales.
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET

KEEP = {None, 'contributed', 'approved'}
DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']
LENGTHS = ['full', 'long', 'medium', 'short']


PARENTS = {}


def draft(element):
    """The element's draft status, inherited from its ancestors (LDML)."""
    while element is not None:
        if element.get('draft') is not None:
            return element.get('draft')
        element = PARENTS.get(element)
    return None


def text(element):
    if element is None or draft(element) not in KEEP:
        return None
    if element.get('alt') is not None:
        return None
    value = element.text or ''
    return None if value == '↑↑↑' else value


def main():
    common = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = open(os.path.join(root, 'vendor/cldr/48.2.0/gregorian.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/main/*.xml: the Gregorian calendar\n'
              '# and the GMT formats), under the Unicode License v3\n'
              '# (LICENSE); written by tool/import_cldr_gregorian.py.\n'
              '# locale, field, value (fields a locale defines itself)\n')
    for path in sorted(glob.glob(os.path.join(common, 'main', '*.xml'))):
        locale = os.path.basename(path)[:-4].replace('_', '-')
        tree = ET.parse(path).getroot()
        PARENTS.clear()
        PARENTS.update({c: p for p in tree.iter() for c in p})
        fields = []
        calendar = tree.find(
            "dates/calendars/calendar[@type='gregorian']")
        if calendar is not None:
            for width, key in (('wide', 'M'), ('abbreviated', 'm')):
                for m in calendar.findall(
                        "months/monthContext[@type='format']/"
                        "monthWidth[@type='%s']/month" % width):
                    fields.append(('%s%s' % (key, m.get('type')), text(m)))
            for context, width, key in (
                    ('format', 'wide', 'D'), ('format', 'abbreviated', 'd'),
                    ('stand-alone', 'wide', 'SD'),
                    ('stand-alone', 'abbreviated', 'sd')):
                for d in calendar.findall(
                        "days/dayContext[@type='%s']/"
                        "dayWidth[@type='%s']/day" % (context, width)):
                    fields.append(('%s%s' % (key, d.get('type')), text(d)))
            for p in calendar.findall(
                    "dayPeriods/dayPeriodContext[@type='format']/"
                    "dayPeriodWidth[@type='abbreviated']/dayPeriod"):
                kind = p.get('type')
                fields.append((kind if kind in ('am', 'pm') else 'p.' + kind,
                               text(p)))
            for e in calendar.findall('eras/eraAbbr/era'):
                fields.append(('era%s' % e.get('type'), text(e)))
            for kind, tag in (('df', 'date'), ('tf', 'time'),
                              ('dtf', 'dateTime')):
                for length in LENGTHS:
                    for f in calendar.findall(
                            "%sFormats/%sFormatLength[@type='%s']/"
                            "%sFormat" % (tag, tag, length, tag)):
                        # (The standard pattern; a date and its time also
                        # joined "at", dateTimeFormat's atTime type.)
                        variant = {None: '', 'atTime': 'at'}.get(
                            f.get('type'))
                        if variant is None:
                            continue
                        pattern = f.find('pattern')
                        key = '%s%s.%s' % (kind, variant, length)
                        fields.append((key, text(pattern)))
                        # (A pattern's own numbering for some fields:
                        # numbers="M=romanlow".)
                        if pattern is not None and pattern.get('numbers') \
                                and text(pattern) is not None:
                            fields.append((key + '#numbers',
                                           pattern.get('numbers')))
        zones = tree.find('dates/timeZoneNames')
        if zones is not None:
            for tag, key in (('gmtFormat', 'gmt'),
                             ('gmtZeroFormat', 'gmtZero'),
                             ('hourFormat', 'hour')):
                fields.append((key, text(zones.find(tag))))
        for key, value in fields:
            if value is None:
                continue
            value = value.replace('\\', '\\\\').replace('\t', '\\t')
            out.write('%s\t%s\t%s\n' % (locale, key, value))
    out.close()
    # The day periods' rules (supplemental/dayPeriods.xml, the format set):
    # each locale's periods from and before (or at) a time of day.
    rules = ET.parse(os.path.join(common, 'supplemental',
                                  'dayPeriods.xml')).getroot()
    out = open(os.path.join(root, 'vendor/cldr/48.2.0/day_periods.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/supplemental/dayPeriods.xml, the\n'
              '# format rules), under the Unicode License v3 (LICENSE);\n'
              '# written by tool/import_cldr_gregorian.py.\n'
              '# locale, period, from, before (or at, with before empty)\n')
    for ruleset in rules.findall('dayPeriodRuleSet'):
        if ruleset.get('type') is not None:
            continue
        for group in ruleset.findall('dayPeriodRules'):
            for locale in group.get('locales').split():
                for rule in group.findall('dayPeriodRule'):
                    at = rule.get('at')
                    out.write('%s\t%s\t%s\t%s\n' % (
                        locale.replace('_', '-'), rule.get('type'),
                        at if at is not None else rule.get('from'),
                        '' if at is not None else rule.get('before')))
    out.close()


main()
