/// Utilitaires de (dé)sérialisation JSON pour Hive.
///
/// Les sauvegardes sont stockées sous forme de Map JSON (approche choisie
/// pour éviter la génération de code build_runner ; les modèles implémentent
/// chacun `toJson` / `fromJson`).
library;

/// Convertit une valeur dynamique (souvent `Map<dynamic, dynamic>` renvoyée
/// par Hive) en `Map<String, dynamic>` sûre.
Map<String, dynamic> asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  throw ArgumentError(
      'Valeur JSON attendue de type Map, reçu : ${value.runtimeType}');
}

/// Convertit une valeur dynamique en `List` sûre.
List<dynamic> asJsonList(dynamic value) {
  if (value is List) return value;
  throw ArgumentError(
      'Valeur JSON attendue de type List, reçu : ${value.runtimeType}');
}

/// Décode une énumération stockée sous forme de chaîne (`enum.name`).
/// Renvoie [fallback] si la valeur est absente ou inconnue (permet de
/// migrer d'anciennes sauvegardes sans crash).
T enumFromName<T extends Enum>(List<T> values, dynamic raw, T fallback) {
  if (raw is String) {
    for (final T value in values) {
      if (value.name == raw) return value;
    }
  }
  return fallback;
}

/// Encode une énumération sous forme de chaîne.
String enumToName(Enum value) => value.name;
