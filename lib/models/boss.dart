import '../core/utils/json_utils.dart';
import 'planet.dart';
import 'tile.dart';

/// Les 4 boss galactiques, un par planète secondaire (GDD §12).
enum BossType {
  exogorth,
  kraytDragon,
  atAt,
  rancor;

  String get displayName => switch (this) {
        BossType.exogorth => 'Exogorth',
        BossType.kraytDragon => 'Krayt Dragon',
        BossType.atAt => 'AT-AT',
        BossType.rancor => 'Rancor',
      };
}

/// Un boss (Architecture v1.0 — modèle Boss).
///
/// Caractéristiques du GDD : 10 000 PV, attaque aléatoire entre 250 et 500
/// (par pas de 10), déplacement de 50 % de chance d'une case à la fin de
/// chaque tour de joueur.
///
/// Champs ajoutés au modèle d'architecture pour couvrir les règles du GDD :
///  - `defeatedByPlayerIds` : liste des joueurs ayant déjà vaincu ce boss
///    (un boss vaincu prend la fuite et ne peut plus être combattu par le
///    joueur qui vient de le vaincre — GDD §12) ;
///  - `isGone` : vrai lorsque le boss a fui après une victoire (il réapparaît
///    dans une zone non visible de la même planète).
/// La mort définitive est atteinte lorsque tous les joueurs l'ont vaincu.
class Boss {
  final String name;
  final BossType type;
  final PlanetType planet;
  final int hp;
  final int attackMin;
  final int attackMax;
  final Position position;

  /// Ids des joueurs ayant vaincu ce boss au moins une fois.
  final List<String> defeatedByPlayerIds;

  /// Vrai si le boss a fui (après au moins une victoire) et attend sa
  /// réapparition dans une zone non visible.
  final bool isGone;

  /// Vrai si le boss est mort définitivement (tous les joueurs l'ont vaincu).
  /// [totalPlayerCount] est le nombre total de joueurs de la partie.
  bool isDefinitivelyDead(int totalPlayerCount) =>
      defeatedByPlayerIds.length >= totalPlayerCount;

  const Boss({
    required this.name,
    required this.type,
    required this.planet,
    required this.hp,
    required this.attackMin,
    required this.attackMax,
    required this.position,
    this.defeatedByPlayerIds = const [],
    this.isGone = false,
  });

  Boss copyWith({
    String? name,
    int? hp,
    Position? position,
    List<String>? defeatedByPlayerIds,
    bool? isGone,
  }) {
    return Boss(
      name: name ?? this.name,
      type: type,
      planet: planet,
      hp: hp ?? this.hp,
      attackMin: attackMin,
      attackMax: attackMax,
      position: position ?? this.position,
      defeatedByPlayerIds: defeatedByPlayerIds ?? this.defeatedByPlayerIds,
      isGone: isGone ?? this.isGone,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': enumToName(type),
        'planet': enumToName(planet),
        'hp': hp,
        'attackMin': attackMin,
        'attackMax': attackMax,
        'position': position.toJson(),
        'defeatedByPlayerIds': defeatedByPlayerIds,
        'isGone': isGone,
      };

  factory Boss.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Boss(
      name: json['name'] as String,
      type: enumFromName(BossType.values, json['type'], BossType.exogorth),
      planet:
          enumFromName(PlanetType.values, json['planet'], PlanetType.mustafar),
      hp: (json['hp'] as num).toInt(),
      attackMin: (json['attackMin'] as num).toInt(),
      attackMax: (json['attackMax'] as num).toInt(),
      position: Position.fromJson(json['position']),
      defeatedByPlayerIds:
          asJsonList(json['defeatedByPlayerIds']).cast<String>().toList(),
      isGone: json['isGone'] as bool? ?? false,
    );
  }
}
