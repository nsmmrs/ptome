"""Writes vendor/cldr/48.2.0/calendars.tsv from CLDR's common/main/*.xml.

Each locale's calendar fields that it defines itself (not those it
inherits, marked or left out), for every calendar: the wide and
abbreviated month and day names, leap month patterns, the abbreviated
format day periods, the eras, the cyclic year names, the date, time and
date-time patterns of each length (a pattern's own numbering after `#`),
and the localized GMT formats of its time zone names. Each is keyed by
its path: an element's type, or its name where it has none
(`japanese/eras/eraAbbr/236`, `gregorian/dateFormats/long/standard`).
Draft values below "contributed" are left out, as ICU's data build
leaves them out.

Also root's aliases between those paths (calendar_aliases.tsv: a field
not found under the one path is looked for under the other, in the
locale and its parents again, as LDML resolves them) and the eras' start
dates (supplemental/supplementalData.xml: eras.tsv).

    python3 -I tool/import_cldr_calendars.py CLDR_COMMON_DIR

lib/src/date_format.dart resolves them through CLDR's parent locales.
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET

KEEP = {None, 'contributed', 'approved'}
# The parts of a calendar kept, and within them the widths.
SECTIONS = {'months', 'monthPatterns', 'days', 'dayPeriods', 'eras',
            'cyclicNameSets', 'dateFormats', 'timeFormats',
            'dateTimeFormats'}
WIDTHS = {'wide', 'abbreviated', 'all'}
# (Within dateTimeFormats, the length patterns only.)
SKIPPED = {'availableFormats', 'appendItems', 'intervalFormats',
           'dateTimeFormatLength@relative', 'default', 'alias',
           'dateFormatItem', 'datetimeSkeleton'}
# (Of the cyclic name sets, the years': `U`.)
CYCLIC = {'years'}
STANDARD = {'dateFormat', 'timeFormat', 'dateTimeFormat'}
# The elements that hold values (others, such as an empty monthContext,
# hold none).
LEAVES = {'month', 'day', 'dayPeriod', 'era', 'cyclicName', 'monthPattern',
          'pattern'}

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


def segment(element):
    """An element's part of a path: its type (and year type), else its
    name; an untyped date, time or date-time format `standard`."""
    kind = element.get('type')
    if kind is None:
        return 'standard' if element.tag in STANDARD else element.tag
    if element.get('yeartype') is not None:
        return '%s-%s' % (kind, element.get('yeartype'))
    return kind


def fields(element, path, out):
    """The values under [element] at [path], into [out]."""
    if element.tag in SKIPPED or element.get('alt') is not None:
        return
    if element.tag.endswith('Width') and element.get('type') not in WIDTHS:
        return
    if element.tag == 'cyclicNameSet' and element.get('type') not in CYCLIC:
        return
    children = list(element)
    if not children or element.tag == 'pattern':
        value = text(element)
        if value is not None and element.tag in LEAVES:
            out.append((path, value))
        return
    for child in children:
        if child.tag == 'pattern':
            value = text(child)
            if value is None:
                continue
            out.append((path, value))
            # (A pattern's own numbering for some fields:
            # numbers="y=jpanyear".)
            if child.get('numbers'):
                out.append((path + '#numbers', child.get('numbers')))
            continue
        fields(child, '%s/%s' % (path, segment(child)), out)


def resolve(path, relative):
    """The path [relative] (an XPath of `..` and `name[@type='x']` steps)
    names from [path]."""
    parts = path.split('/')
    for step in relative.split('/'):
        if step == '..':
            parts.pop()
        elif "[@type='" in step:
            parts.append(step.split("[@type='")[1].split("'")[0])
        else:
            parts.append(step)
    return '/'.join(parts)


def main():
    common = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    vendor = os.path.join(root, 'vendor/cldr/48.2.0')
    out = open(os.path.join(vendor, 'calendars.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/main/*.xml: the calendars and the\n'
              '# GMT formats), under the Unicode License v3 (LICENSE);\n'
              '# written by tool/import_cldr_calendars.py.\n'
              '# locale, path, value (fields a locale defines itself)\n')
    aliases = []
    for path in sorted(glob.glob(os.path.join(common, 'main', '*.xml'))):
        locale = os.path.basename(path)[:-4].replace('_', '-')
        tree = ET.parse(path).getroot()
        PARENTS.clear()
        PARENTS.update({c: p for p in tree.iter() for c in p})
        found = []
        for calendar in tree.findall('dates/calendars/calendar'):
            name = calendar.get('type')
            for section in calendar:
                if section.tag not in SECTIONS:
                    continue
                fields(section, '%s/%s' % (name, section.tag), found)
        if locale == 'root':
            for alias in tree.iter('alias'):
                owner = PARENTS[alias]
                steps = []
                node = owner
                while node is not None and node.tag != 'calendar':
                    steps.append(segment(node))
                    node = PARENTS.get(node)
                if node is None:
                    continue
                at = '/'.join([node.get('type')] + list(reversed(steps)))
                if at.split('/')[1] not in SECTIONS:
                    continue
                aliases.append((at, resolve(at, alias.get('path'))
                                .replace('calendar/', '', 1)
                                if 'calendar' in alias.get('path')
                                else resolve(at, alias.get('path'))))
        zones = tree.find('dates/timeZoneNames')
        if zones is not None:
            for tag in ('gmtFormat', 'gmtZeroFormat', 'hourFormat'):
                value = text(zones.find(tag))
                if value is not None:
                    found.append(('zone/' + tag, value))
        for key, value in found:
            value = value.replace('\\', '\\\\').replace('\t', '\\t')
            out.write('%s\t%s\t%s\n' % (locale, key, value))
    out.close()
    out = open(os.path.join(vendor, 'calendar_aliases.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/main/root.xml: the aliases in its\n'
              '# calendars), under the Unicode License v3 (LICENSE);\n'
              '# written by tool/import_cldr_calendars.py.\n'
              '# path, the path it is looked for under instead\n')
    for at, to in aliases:
        out.write('%s\t%s\n' % (at, to))
    out.close()
    # The eras' start dates (or end, for an era counted backwards).
    data = ET.parse(os.path.join(common, 'supplemental',
                                 'supplementalData.xml')).getroot()
    out = open(os.path.join(vendor, 'eras.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/supplemental/supplementalData.xml:\n'
              '# calendarData), under the Unicode License v3 (LICENSE);\n'
              '# written by tool/import_cldr_calendars.py.\n'
              '# calendar, era, start, end (year-month-day, proleptic\n'
              '# Gregorian)\n')
    for calendar in data.findall('calendarData/calendar'):
        for era in calendar.findall('eras/era'):
            out.write('%s\t%s\t%s\t%s\n' % (
                calendar.get('type'), era.get('type'),
                era.get('start') or '', era.get('end') or ''))
    out.close()
    # The weeks: each region's first day and the fewest days of a year its
    # first week has (supplementalData.xml weekData), and each language's
    # likely region (likelySubtags.xml), for week-numbering years (`Y`).
    out = open(os.path.join(vendor, 'weeks.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/supplemental/supplementalData.xml:\n'
              '# weekData; likelySubtags.xml), under the Unicode License v3\n'
              '# (LICENSE); written by tool/import_cldr_calendars.py.\n'
              '# firstDay or minDays, region, value; or likely, language\n'
              '# (and script), region\n')
    for kind, attr in (('firstDay', 'day'), ('minDays', 'count')):
        for e in data.findall('weekData/%s' % kind):
            if e.get('alt') is not None:
                continue
            for region in e.get('territories').split():
                out.write('%s\t%s\t%s\n' % (kind, region, e.get(attr)))
    likely = ET.parse(os.path.join(common, 'supplemental',
                                   'likelySubtags.xml')).getroot()
    for e in likely.iter('likelySubtag'):
        source = e.get('from').split('_')
        target = e.get('to').split('_')
        # (A language, or a language and script, to its region.)
        if len(source) > 2 or (len(source) == 2 and len(source[1]) != 4):
            continue
        if source[0] == 'und' or len(target) < 3:
            continue
        out.write('likely\t%s\t%s\n' % ('-'.join(source), target[-1]))
    out.close()
    # The day periods' rules (supplemental/dayPeriods.xml, the format set):
    # each locale's periods from and before (or at) a time of day.
    rules = ET.parse(os.path.join(common, 'supplemental',
                                  'dayPeriods.xml')).getroot()
    out = open(os.path.join(vendor, 'day_periods.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/supplemental/dayPeriods.xml, the\n'
              '# format rules), under the Unicode License v3 (LICENSE);\n'
              '# written by tool/import_cldr_calendars.py.\n'
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
