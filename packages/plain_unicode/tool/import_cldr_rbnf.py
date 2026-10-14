"""Writes vendor/cldr/48.2.0/rbnf.tsv from CLDR's common/rbnf/*.xml.

The rule-based number formats of CLDR's algorithmic numbering systems
(supplemental/numberingSystems.xml: `hebr`, `jpanyear`, `hanidays`...):
each system's file, grouping and rule set, then the rule text of each
grouping they name, as CLDR writes it (one rule a line).

    python3 -I tool/import_cldr_rbnf.py CLDR_COMMON_DIR

lib/src/rbnf.dart interprets the rules.
"""
import os
import sys
import xml.etree.ElementTree as ET


def main():
    common = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    systems = ET.parse(os.path.join(common, 'supplemental',
                                    'numberingSystems.xml')).getroot()
    wanted = []
    for system in systems.iter('numberingSystem'):
        if system.get('type') != 'algorithmic':
            continue
        rules = system.get('rules').split('/')
        if len(rules) == 1:
            locale, grouping, ruleset = 'root', 'NumberingSystemRules', rules[0]
        else:
            locale, grouping, ruleset = rules
        wanted.append((system.get('id'), locale, grouping, ruleset))
    out = open(os.path.join(root, 'vendor/cldr/48.2.0/rbnf.tsv'), 'w')
    out.write('# From CLDR 48.2.0 (common/supplemental/numberingSystems.xml,\n'
              '# common/rbnf/*.xml), under the Unicode License v3 (LICENSE);\n'
              '# written by tool/import_cldr_rbnf.py.\n'
              '# system, numbering system, file, grouping, rule set; then\n'
              '# rules, file, grouping, a line of its rule text\n')
    for system, locale, grouping, ruleset in wanted:
        out.write('system\t%s\t%s\t%s\t%s\n' % (system, locale, grouping,
                                               ruleset))
    for locale, grouping in sorted({(w[1], w[2]) for w in wanted}):
        tree = ET.parse(os.path.join(common, 'rbnf', locale + '.xml'))
        for group in tree.getroot().iter('rulesetGrouping'):
            if group.get('type') != grouping:
                continue
            text = group.find('rbnfRules').text or ''
            for line in text.split('\n'):
                line = line.strip()
                if line:
                    out.write('rules\t%s\t%s\t%s\n' % (locale, grouping, line))
    out.close()


main()
