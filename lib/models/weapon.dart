import '../core/constants/enums.dart';
import '../core/utils/json_utils.dart';

/// Une carte arme (Architecture v1.0). Le bonus d'attaque est déduit de la
/// rareté (table du GDD) ; [id] identifie la carte (pipeline d'images).
class Weapon {
  final String id;
  final String name;
  final Rarity rarity;
  final int attackBonus;

  const Weapon({
    required this.id,
    required this.name,
    required this.rarity,
    required this.attackBonus,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rarity': enumToName(rarity),
        'attackBonus': attackBonus,
      };

  factory Weapon.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Weapon(
      id: json['id'] as String? ?? json['name'] as String,
      name: json['name'] as String,
      rarity: enumFromName(Rarity.values, json['rarity'], Rarity.commun),
      attackBonus: (json['attackBonus'] as num).toInt(),
    );
  }
}
