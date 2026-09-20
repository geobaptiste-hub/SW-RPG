/// Transforme un nom de carte en identifiant de fichier image
/// (convention `SW/MD/images-cartes.md`) : minuscules, accents retirés,
/// séparateurs → underscore.
///
/// Exemples : « Ki-Adi-Mundi » → `ki_adi_mundi`, « L'empereur » →
/// `l_empereur`, « Chirrut Îmwe » → `chirrut_imwe`, « IG-88 » → `ig_88`.
String slugify(String input) {
  const Map<String, String> accents = <String, String>{
    'à': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
    'ÿ': 'y', 'ñ': 'n',
  };

  final StringBuffer buffer = StringBuffer();
  for (final int code in input.toLowerCase().runes) {
    final String char = String.fromCharCode(code);
    if (accents.containsKey(char)) {
      buffer.write(accents[char]);
    } else if ((code >= 0x61 && code <= 0x7A) || // a-z
        (code >= 0x30 && code <= 0x39)) {
      // 0-9
      buffer.write(char);
    } else {
      buffer.write('_');
    }
  }

  String result = buffer.toString();
  while (result.contains('__')) {
    result = result.replaceAll('__', '_');
  }
  return result.replaceAll(RegExp(r'^_+|_+$'), '');
}
