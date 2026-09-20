import '../core/constants/game_constants.dart';
import '../core/utils/json_utils.dart';

/// Un monstre rencontré sur la carte (Architecture v1.0 — modèle Monster).
///
/// Les monstres sont des créatures neutres : pas de faction (fichier
/// « Données cartes.xlsx »). 20 monstres nommés, 4 par niveau (1 à 5),
/// statistiques officielles du GDD §10 — voir MonsterConstants.
class Monster {
  final String name;
  final int level;
  final int attack;
  final int hp;
  final int xpReward;

  const Monster({
    required this.name,
    required this.level,
    required this.attack,
    required this.hp,
    required this.xpReward,
  });

  /// Construit un monstre nommé du deck de données avec les statistiques
  /// officielles de son niveau (GDD §10 / Données cartes.xlsx).
  factory Monster.forCard(String name, int level) {
    assert(level >= 1 && level <= 5, 'Niveau de monstre invalide : $level');
    final List<int> stats = GameConstants.monsterStatsPerLevel[level - 1];
    return Monster(
      name: name,
      level: level,
      attack: stats[0],
      hp: stats[1],
      xpReward: stats[2],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'level': level,
        'attack': attack,
        'hp': hp,
        'xpReward': xpReward,
      };

  factory Monster.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Monster(
      name: json['name'] as String,
      level: (json['level'] as num).toInt(),
      attack: (json['attack'] as num).toInt(),
      hp: (json['hp'] as num).toInt(),
      xpReward: (json['xpReward'] as num).toInt(),
    );
  }
}
