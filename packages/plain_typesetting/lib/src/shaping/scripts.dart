/// Scripts as the shaping plan sees them (after HarfBuzz 14.6's
/// `hb-ot-tag.cc`, `hb-common.cc` and `hb-ot-shaper.hh`): the OpenType
/// script tags a font may list a script under, its native horizontal
/// direction, and the shaper that sets it.
library;

/// The OpenType script tags of [script] (an ISO 15924 code), the
/// preferred first: the Indic scripts' `dev3`, `dev2`, `deva`; Myanmar's
/// `mym2`, `mymr`; otherwise the code in lower case, with the tags that
/// differ (`kana`, `lao `, `yi  `, `nko `, `vai `).
List<String> scriptTags(String script) {
  final out = <String>[];
  if (_newTags[script] case final tag?) {
    if (tag != 'mym2') out.add('${tag.substring(0, 3)}3');
    out.add(tag);
  }
  out.add(switch (script) {
    'Hira' || 'Kana' || 'Hrkt' => 'kana',
    'Laoo' => 'lao ',
    'Yiii' => 'yi  ',
    'Nkoo' => 'nko ',
    'Vaii' => 'vai ',
    'Zmth' => 'math',
    _ => script.toLowerCase(),
  });
  return out;
}

const Map<String, String> _newTags = {
  'Beng': 'bng2',
  'Deva': 'dev2',
  'Gujr': 'gjr2',
  'Guru': 'gur2',
  'Knda': 'knd2',
  'Mlym': 'mlm2',
  'Orya': 'ory2',
  'Taml': 'tml2',
  'Telu': 'tel2',
  'Mymr': 'mym2',
};

/// The scripts written right to left.
const Set<String> rightToLeftScripts = {
  'Arab', 'Hebr', 'Syrc', 'Thaa', 'Cprt', 'Khar', 'Phnx', 'Nkoo', 'Lydi', //
  'Avst', 'Armi', 'Phli', 'Prti', 'Sarb', 'Orkh', 'Samr', 'Mand', 'Merc',
  'Mero', 'Mani', 'Mend', 'Nbat', 'Narb', 'Palm', 'Phlp', 'Hatr', 'Adlm',
  'Rohg', 'Sogo', 'Sogd', 'Elym', 'Chrs', 'Yezi', 'Ougr', 'Gara', 'Sidt',
};

/// The shapers.
enum ShaperKind {
  /// Scripts that need no more than the common features.
  standard,

  /// Arabic and Syriac: joining forms.
  arabic,

  /// Hebrew: its compositions and mark order.
  hebrew,

  /// The Indic scripts of the old (2) and original specifications.
  indic,

  /// Khmer.
  khmer,

  /// Myanmar.
  myanmar,

  /// The Universal Shaping Engine.
  use,

  /// Thai and Lao.
  thai,

  /// Hangul.
  hangul,
}

/// The scripts the Universal Shaping Engine sets (with their own script
/// table in the font).
const Set<String> _useScripts = {
  'Tibt', 'Mong', 'Sinh', 'Buhd', 'Hano', 'Tglg', 'Tagb', 'Limb', 'Tale', //
  'Bugi', 'Khar', 'Sylo', 'Tfng', 'Bali', 'Nkoo', 'Phag', 'Cham', 'Kali',
  'Lepc', 'Rjng', 'Saur', 'Sund', 'Egyp', 'Java', 'Kthi', 'Mtei', 'Lana',
  'Tavt', 'Batk', 'Brah', 'Mand', 'Cakm', 'Plrd', 'Shrd', 'Takr', 'Dupl',
  'Gran', 'Khoj', 'Sind', 'Mahj', 'Mani', 'Modi', 'Hmng', 'Phlp', 'Sidd',
  'Tirh', 'Ahom', 'Mult', 'Adlm', 'Bhks', 'Marc', 'Newa', 'Gonm', 'Soyo',
  'Zanb', 'Dogr', 'Gong', 'Rohg', 'Maka', 'Medf', 'Sogo', 'Sogd', 'Elym',
  'Nand', 'Hmnp', 'Wcho', 'Chrs', 'Diak', 'Kits', 'Yezi', 'Cpmn', 'Ougr',
  'Tnsa', 'Toto', 'Vith', 'Kawi', 'Nagm', 'Gara', 'Gukh', 'Krai', 'Onao',
  'Sunu', 'Todr', 'Tutg', 'Berf', 'Sidt', 'Tayo', 'Tols', 'Jurc', 'Pcun',
  'Seal',
};

const Set<String> _indicScripts = {
  'Beng', 'Deva', 'Gujr', 'Guru', 'Knda', 'Mlym', 'Orya', 'Taml', 'Telu', //
};

/// The shaper that sets [script] horizontally (or, [vertical], down),
/// [gsubScript] the script tag the font's GSUB table was found to list
/// it under (HarfBuzz's `hb_ot_shaper_categorize`).
ShaperKind shaperFor(
  String script,
  String gsubScript, {
  bool vertical = false,
}) {
  final generic = gsubScript == 'DFLT' || gsubScript == 'latn';
  switch (script) {
    case 'Arab' || 'Syrc':
      return (gsubScript != 'DFLT' || script == 'Arab') && !vertical
          ? ShaperKind.arabic
          : ShaperKind.standard;
    case 'Thai' || 'Laoo':
      return ShaperKind.thai;
    case 'Hang':
      return ShaperKind.hangul;
    case 'Hebr':
      return ShaperKind.hebrew;
    case 'Khmr':
      return ShaperKind.khmer;
    case 'Mymr':
      return generic || gsubScript == 'mymr'
          ? ShaperKind.standard
          : ShaperKind.myanmar;
  }
  if (_indicScripts.contains(script)) {
    if (generic) return ShaperKind.standard;
    return gsubScript.endsWith('3') ? ShaperKind.use : ShaperKind.indic;
  }
  if (_useScripts.contains(script)) {
    return generic ? ShaperKind.standard : ShaperKind.use;
  }
  return ShaperKind.standard;
}
