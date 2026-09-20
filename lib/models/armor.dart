import '../core/constants/enums.dart';
import '../core/utils/json_utils.dart';

/// Une carte tenue (Architecture v1.0). Le bonus de PV est déduit de la
/// rareté (table du GDD) ; [id] identifie la carte (pipeline d'images).
class Armor {
  final String id;
  final String name;
  final Rarity rarity;
  final int hpBonus;

  const Armor({
    required this.id,
    required this.name,
    required this.rarity,
    required this.hpBonus,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rarity': enumToName(rarity),
        'hpBonus': hpBonus,
      };

  factory Armor.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Armor(
      id: json['id'] as String? ?? json['name'] as String,
      name: json['name'] as String,
      rarity: enumFromName(Rarity.values, json['rarity'], Rarity.commun),
      hpBonus: (json['hpBonus'] as num).toInt(),
    );
  }
}
