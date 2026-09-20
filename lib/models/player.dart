import '../core/constants/enums.dart';
import '../core/constants/game_constants.dart' show GameConstants;
import '../core/constants/planet_constants.dart' show PlanetConstants;
import 'planet.dart' show PlanetType;
import 'tile.dart' show Position;
import '../core/utils/json_utils.dart';
import 'ally.dart';
import 'armor.dart';
import 'boss.dart';
import 'tile.dart';
import 'weapon.dart';

/// Les 4 factions du jeu (GDD addendum « Factions et affinités »).
enum Faction {
  empire,
  sith,
  rebel,
  jedi;

  String get displayName => switch (this) {
        Faction.empire => 'Empire',
        Faction.sith => 'Sith',
        Faction.rebel => 'Rebel',
        Faction.jedi => 'Jedi',
      };

  // TODO(Sprint 4) : les affinités entre factions (identique / alliée /
  // ennemie / alliée d'une faction ennemie — GDD addendum) influencent les
  // bonus de certaines cartes. Table d'affinité (GDD) :
  // Empire ↔ Sith, Rebel ↔ Jedi. À implémenter avec les cartes.
  Faction? get alliedFaction => switch (this) {
        Faction.empire => Faction.sith,
        Faction.sith => Faction.empire,
        Faction.rebel => Faction.jedi,
        Faction.jedi => Faction.rebel,
      };
}

/// Un joueur : un personnage principal et sa progression
/// (Architecture v1.0 — modèle Player).
class Player {
  final String id;
  final String name;
  final Faction faction;

  /// Position actuelle sur la planète.
  final Position position;

  final int level;
  final int xp;

  /// Attaque totale de base (sans équipement ni alliés).
  final int attack;

  final int hp;
  final int maxHp;

  /// Une seule arme équipée à la fois (GDD §9).
  final Weapon? weapon;

  /// Une seule tenue équipée à la fois (GDD §9).
  final Armor? armor;

  /// Alliés recrutés (10 places d'équipe maximum ; le personnage principal
  /// ne consomme aucune place — GDD §8).
  final List<Ally> allies;

  /// Boss vaincus par ce joueur (conditions de victoire — GDD §16).
  final List<BossType> defeatedBosses;

  /// Équipe du joueur en mode Équipes (2v2, 3v3, 4v4) ; `null` en mode
  /// chacun pour soi.
  final TeamSide? team;

  /// Joueur éliminé (PV à 0 — combat entre joueurs GDD §13 ou monstre) :
  /// sauté dans la rotation des tours, son pion disparaît du plateau.
  final bool eliminated;

  /// Arme en réserve (Sprint 4 : 1 seule, échangeable avec l'arme équipée).
  final Weapon? storedWeapon;

  /// Tenue en réserve (Sprint 4 : 1 seule, échangeable avec la tenue équipée).
  final Armor? storedArmor;

  /// Allié en réserve (retours playtest 10/09/2026 : 1 seul, recrutable plus
  /// tard — utile quand la rareté dépasse le niveau ou les PP disponibles).
  final Ally? storedAlly;

  /// Bonus de capacité d'équipe gagné en vainquant des boss (retours
  /// playtest : +2 places par boss vaincu).
  final int teamCapacityBonus;

  /// Planète sur laquelle se trouve le joueur (Sprint 5 — multi-planètes).
  final PlanetType planet;

  /// Retour de portail : planète et position d'origine (transit — Sprint 5).
  final PlanetType? returnPlanet;
  final Position? returnPosition;

  const Player({
    required this.id,
    required this.name,
    required this.faction,
    required this.position,
    required this.level,
    required this.xp,
    required this.attack,
    required this.hp,
    required this.maxHp,
    this.weapon,
    this.armor,
    this.allies = const [],
    this.defeatedBosses = const [],
    this.team,
    this.eliminated = false,
    this.storedWeapon,
    this.storedArmor,
    this.storedAlly,
    this.teamCapacityBonus = 0,
    PlanetType? planet,
    this.returnPlanet,
    this.returnPosition,
  })  : planet = planet ?? PlanetType.coruscant;

  /// Somme des places d'équipe consommées par les alliés.
  int get usedTeamSlots =>
      allies.fold(0, (int total, Ally ally) => total + ally.teamCost);

  /// Capacité d'équipe du joueur : 10 places de base (GDD §8) + le bonus
  /// gagné en vainquant des boss (retours playtest).
  int get teamCapacity => GameConstants.teamCapacity + teamCapacityBonus;

  /// Indique si le joueur peut encore recruter un allié coûtant [cost] places.
  bool canRecruit(int cost) => usedTeamSlots + cost <= teamCapacity;

  /// Bonus ATK des escouades (formule cumulative du GDD addendum) :
  /// par escouade, bonus par carte × nombre de copies — +50 si le porteur
  /// est de la faction de l'escouade, +25 si c'est la faction alliée.
  int get squadAttackBonus {
    int bonus = 0;
    final Map<String, int> counts = <String, int>{};
    final Map<String, Ally> byName = <String, Ally>{};
    for (final Ally ally in allies) {
      if (ally.type != AllyType.escouade) continue;
      counts[ally.name] = (counts[ally.name] ?? 0) + 1;
      byName[ally.name] = ally;
    }
    for (final MapEntry<String, int> entry in counts.entries) {
      final Ally squad = byName[entry.key]!;
      final int perCard = squad.faction == faction
          ? (squad.squadBonusOwn ?? 0)
          : (faction.alliedFaction == squad.faction
              ? (squad.squadBonusAllied ?? 0)
              : 0);
      // Formule du GDD addendum : « Somme des attaques de l'escouade ×
      // Nombre de cartes de cette même escouade » — ex. 4 Ewoks :
      // (50 + 50 + 50 + 50) × 4 = 800 ATK.
      bonus += perCard * entry.value * entry.value;
    }
    return bonus;
  }

  /// Bonus de PV maximum des tanks présents dans l'équipe.
  int get tankHpBonus => allies.fold(
      0, (int total, Ally ally) => total + (ally.hpBonus ?? 0));

  /// Un tank « dégâts divisés par 2 » est présent dans l'équipe.
  bool get hasDamageDivider =>
      allies.any((Ally ally) => ally.dividesDamage);

  // --- Soutiens (retours playtest 10/09/2026 — capacités désormais actives) ---

  bool _hasSupport(String ability) => allies.any((Ally ally) =>
      ally.type == AllyType.soutien && ally.ability == ability);

  /// « Le 5 compte aussi pour un coup critique » (Ki-Adi-Mundi, C-3PO…).
  bool get hasCritOn5 => _hasSupport('critOn5');

  /// « Multipliez la valeur du dé par deux pour vous déplacer »
  /// (Luminara Unduli, Bail Organa…).
  bool get hasDoubleMoveDice => _hasSupport('doubleMoveDice');

  /// « +20 XP en plus après chaque combat » (Jocasta Nu, Chirrut Îmwe…).
  bool get hasXpBonusSupport => _hasSupport('bonusXp20');

  /// « Une seule fois : lancez le dé et multipliez l'attaque par le chiffre
  /// du dé » (Yaddle, Amiral Ackbar…) — carte consommée à l'usage.
  bool get hasAttackTimesDice => _hasSupport('attackTimesDice');

  /// « Une seule fois : empêche la mort et garde le perso à 1 PV »
  /// (Adi Gallia, Mon Mothma…) — carte consommée au déclenchement.
  bool get hasPreventDeath => _hasSupport('preventDeath');

  /// L'équipe (ou la réserve) contient déjà une carte du même nom. Les
  /// doublons sont interdits, sauf escouades qui se cumulent par design
  /// (retours playtest 10/09/2026).
  bool hasAllyNamed(String name) =>
      allies.any((Ally ally) => ally.name == name) ||
      storedAlly?.name == name;

  /// Soin total apporté après chaque victoire contre un monstre
  /// (somme des healers — cumulable, plafonné au max PV).
  int get healerAfterCombatHeal => allies.fold(0,
      (int total, Ally ally) => total + (ally.healAfterCombat ?? 0));

  /// Bonus ATK des nukers selon la faction du porteur (Sprint 4.1) :
  /// faction propre ou alliée → bonus ⚔ de la carte. Les factions ennemies
  /// n'apportent rien (malus de PV appliqué au recrutement).
  int get nukerAttackBonus => allies.fold(0, (int total, Ally ally) {
        final int? effect = ally.nukerOwnerEffect(faction);
        return total + ((effect != null && effect > 0) ? effect : 0);
      });

  /// Bonus ATK des cartes Spéciales de faction amie (propre ou alliée —
  /// retours playtest 10/09/2026). Les factions ennemies n'apportent rien
  /// (la carte n'est d'ailleurs pas recrutable).
  int get specialAttackBonus => allies.fold(
      0,
      (int total, Ally ally) =>
          total +
          (ally.type == AllyType.special && ally.isFriendlyTo(faction)
              ? (ally.bonusAtkIfFriendly ?? 0)
              : 0));

  /// Bonus de PV maximum des cartes Spéciales de faction amie.
  int get specialHpBonus => allies.fold(
      0,
      (int total, Ally ally) =>
          total +
          (ally.type == AllyType.special && ally.isFriendlyTo(faction)
              ? (ally.bonusHpIfFriendly ?? 0)
              : 0));

  /// Attaque de base + arme + escouades cumulatives + nukers + spéciales
  /// amies (Sprint 4.1, retours playtest).
  int get totalAttack =>
      attack +
      (weapon?.attackBonus ?? 0) +
      squadAttackBonus +
      nukerAttackBonus +
      specialAttackBonus;

  /// PV maximum : base + tenue + tanks + spéciales amies (Sprint 4).
  int get totalMaxHp =>
      maxHp + (armor?.hpBonus ?? 0) + tankHpBonus + specialHpBonus;

  Player copyWith({
    String? id,
    String? name,
    Faction? faction,
    Position? position,
    int? level,
    int? xp,
    int? attack,
    int? hp,
    int? maxHp,
    Weapon? weapon,
    bool clearWeapon = false,
    Armor? armor,
    bool clearArmor = false,
    List<Ally>? allies,
    List<BossType>? defeatedBosses,
    TeamSide? team,
    bool clearTeam = false,
    bool? eliminated,
    Weapon? storedWeapon,
    bool clearStoredWeapon = false,
    Armor? storedArmor,
    bool clearStoredArmor = false,
    Ally? storedAlly,
    bool clearStoredAlly = false,
    int teamCapacityBonusDelta = 0,
    PlanetType? planet,
    PlanetType? returnPlanet,
    bool clearReturn = false,
    Position? returnPosition,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      faction: faction ?? this.faction,
      position: position ?? this.position,
      level: level ?? this.level,
      xp: xp ?? this.xp,
      attack: attack ?? this.attack,
      hp: hp ?? this.hp,
      maxHp: maxHp ?? this.maxHp,
      weapon: clearWeapon ? null : (weapon ?? this.weapon),
      armor: clearArmor ? null : (armor ?? this.armor),
      allies: allies ?? this.allies,
      defeatedBosses: defeatedBosses ?? this.defeatedBosses,
      team: clearTeam ? null : (team ?? this.team),
      eliminated: eliminated ?? this.eliminated,
      storedWeapon:
          clearStoredWeapon ? null : (storedWeapon ?? this.storedWeapon),
      storedArmor: clearStoredArmor ? null : (storedArmor ?? this.storedArmor),
      storedAlly: clearStoredAlly ? null : (storedAlly ?? this.storedAlly),
      teamCapacityBonus: teamCapacityBonus + teamCapacityBonusDelta,
      planet: planet ?? this.planet,
      returnPlanet:
          clearReturn ? null : (returnPlanet ?? this.returnPlanet),
      returnPosition:
          clearReturn ? null : (returnPosition ?? this.returnPosition),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'faction': enumToName(faction),
        'position': position.toJson(),
        'level': level,
        'xp': xp,
        'attack': attack,
        'hp': hp,
        'maxHp': maxHp,
        'weapon': weapon?.toJson(),
        'armor': armor?.toJson(),
        'allies': allies.map((Ally ally) => ally.toJson()).toList(),
        'defeatedBosses': defeatedBosses.map(enumToName).toList(),
        'team': team == null ? null : enumToName(team!),
        'eliminated': eliminated,
        'storedWeapon': storedWeapon?.toJson(),
        'storedArmor': storedArmor?.toJson(),
        if (storedAlly != null) 'storedAlly': storedAlly!.toJson(),
        'teamCapacityBonus': teamCapacityBonus,
        'planet': enumToName(planet),
        if (returnPlanet != null) 'returnPlanet': enumToName(returnPlanet!),
        if (returnPosition != null)
          'returnPosition': returnPosition!.toJson(),
      };

  factory Player.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      faction: enumFromName(Faction.values, json['faction'], Faction.rebel),
      position: Position.fromJson(json['position']),
      level: (json['level'] as num).toInt(),
      xp: (json['xp'] as num).toInt(),
      attack: (json['attack'] as num).toInt(),
      hp: (json['hp'] as num).toInt(),
      maxHp: (json['maxHp'] as num).toInt(),
      weapon: json['weapon'] == null ? null : Weapon.fromJson(json['weapon']),
      armor: json['armor'] == null ? null : Armor.fromJson(json['armor']),
      allies: asJsonList(json['allies'])
          .map((dynamic a) => Ally.fromJson(a))
          .toList(),
      defeatedBosses: asJsonList(json['defeatedBosses'])
          .map((dynamic b) =>
              enumFromName(BossType.values, b, BossType.exogorth))
          .toList(),
      team: json['team'] == null
          ? null
          : enumFromName(TeamSide.values, json['team'], TeamSide.teamA),
      eliminated: json['eliminated'] as bool? ?? false,
      storedWeapon:
          json['storedWeapon'] == null ? null : Weapon.fromJson(json['storedWeapon']),
      storedArmor:
          json['storedArmor'] == null ? null : Armor.fromJson(json['storedArmor']),
      storedAlly:
          json['storedAlly'] == null ? null : Ally.fromJson(json['storedAlly']),
      teamCapacityBonus: (json['teamCapacityBonus'] as num?)?.toInt() ?? 0,
      planet: enumFromName(
          PlanetType.values, json['planet'], PlanetConstants.startPlanets.first),
      returnPlanet: json['returnPlanet'] == null
          ? null
          : enumFromName(PlanetType.values, json['returnPlanet'], PlanetType.hoth),
      returnPosition: json['returnPosition'] == null
          ? null
          : Position.fromJson(json['returnPosition']),
    );
  }
}
