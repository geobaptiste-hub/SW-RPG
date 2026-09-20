import '../core/constants/enums.dart';
import '../core/utils/json_utils.dart';
import 'player.dart' show Faction;

/// Un allié recrutable (Architecture v1.0 — modèle Ally, enrichi Sprint 4
/// avec les effets du fichier « Données cartes.xlsx »).
///
/// Effets actifs : healers (soins), tanks (+PV ou dégâts ÷ 2), escouades
/// (bonus ATK cumulatif), nukers (bonus/malus selon la faction du porteur)
/// et spéciales (bonus ATK/PV pour les factions amies — Sprint « retours
/// playtest »). Les soutiens (`ability`) restent des données d'affichage.
class Ally {
  final String name;
  final AllyType type;
  final Rarity rarity;
  final Faction faction;

  /// Coût en places d'équipe (PP).
  final int teamCost;

  // --- Healer ---
  /// PV récupérés après chaque victoire contre un monstre.
  final int? healAfterCombat;

  /// PV récupérés immédiatement au recrutement.
  final int? healInstant;

  // --- Tank ---
  /// Bonus de PV maximum tant qu'il est dans l'équipe.
  final int? hpBonus;

  /// Les dégâts subis par le joueur sont divisés par 2.
  final bool dividesDamage;

  // --- Escouade ---
  /// Bonus ATK par carte si le porteur est de la même faction.
  final int? squadBonusOwn;

  /// Bonus ATK par carte si le porteur est de la faction alliée.
  final int? squadBonusAllied;

  // --- Spéciale ---
  /// Bonus ATK tant que le porteur est de la faction de la carte ou de sa
  /// faction alliée (cartes Spéciales — retours playtest 10/09/2026).
  final int? bonusAtkIfFriendly;

  /// Bonus de PV maximum dans les mêmes conditions de faction.
  final int? bonusHpIfFriendly;

  // --- Données stockées (effets futurs — nukers, escouades, soutiens) ---
  final int? instantDamageJedi;
  final int? instantDamageRebel;
  final int? bonusIfSithOwner;
  final int? bonusIfEmpireOwner;
  final String? ability;
  final String? effectText;

  const Ally({
    required this.name,
    required this.type,
    required this.rarity,
    required this.faction,
    required this.teamCost,
    this.healAfterCombat,
    this.healInstant,
    this.hpBonus,
    this.dividesDamage = false,
    this.squadBonusOwn,
    this.squadBonusAllied,
    this.bonusAtkIfFriendly,
    this.bonusHpIfFriendly,
    this.instantDamageJedi,
    this.instantDamageRebel,
    this.bonusIfSithOwner,
    this.bonusIfEmpireOwner,
    this.ability,
    this.effectText,
  });

  factory Ally.healer({
    required String name,
    required Faction faction,
    required Rarity rarity,
    required int cost,
    required int healAfter,
    required int healInstant,
  }) {
    return Ally(
      name: name,
      type: AllyType.healer,
      rarity: rarity,
      faction: faction,
      teamCost: cost,
      healAfterCombat: healAfter,
      healInstant: healInstant,
    );
  }

  factory Ally.tank({
    required String name,
    required Faction faction,
    required Rarity rarity,
    required int cost,
    int? hpBonus,
    bool dividesDamage = false,
  }) {
    return Ally(
      name: name,
      type: AllyType.tank,
      rarity: rarity,
      faction: faction,
      teamCost: cost,
      hpBonus: hpBonus,
      dividesDamage: dividesDamage,
    );
  }

  factory Ally.nuker({
    required String name,
    required Faction faction,
    required Rarity rarity,
    required int cost,
    required int dmgVsJedi,
    required int dmgVsRebel,
    required int bonusIfSithOwner,
    required int bonusIfEmpireOwner,
  }) {
    // L'effet dépend de la faction du PORTEUR (décision du 08/09/2026).
    String part(Faction owner) {
      final int value = switch (owner) {
        Faction.empire => bonusIfEmpireOwner,
        Faction.sith => bonusIfSithOwner,
        Faction.rebel => dmgVsRebel,
        Faction.jedi => dmgVsJedi,
      };
      return value >= 0
          ? 'Vous êtes ${owner.displayName} : +$value ATK'
          : 'Vous êtes ${owner.displayName} : $value PV';
    }

    return Ally(
      name: name,
      type: AllyType.nuker,
      rarity: rarity,
      faction: faction,
      teamCost: cost,
      instantDamageJedi: dmgVsJedi,
      instantDamageRebel: dmgVsRebel,
      bonusIfSithOwner: bonusIfSithOwner,
      bonusIfEmpireOwner: bonusIfEmpireOwner,
      effectText:
          '${part(Faction.empire)} · ${part(Faction.sith)} · ${part(Faction.rebel)} · ${part(Faction.jedi)}',
    );
  }

  factory Ally.squad({
    required String name,
    required Faction faction,
    required int count,
    required int bonusOwn,
    required int bonusAllied,
    required int instantDamage1,
    required int instantDamage2,
  }) {
    return Ally(
      name: name,
      type: AllyType.escouade,
      rarity: Rarity.commun,
      faction: faction,
      teamCost: 1,
      squadBonusOwn: bonusOwn,
      squadBonusAllied: bonusAllied,
      instantDamageJedi: instantDamage1,
      instantDamageRebel: instantDamage2,
      effectText: 'Porteur ${faction.displayName} : +$bonusOwn ATK par carte · '
          'Porteur allié : +$bonusAllied ATK par carte',
    );
  }

  factory Ally.support({
    required String name,
    required Faction faction,
    required Rarity rarity,
    required int cost,
    required String ability,
    required String effectText,
  }) {
    return Ally(
      name: name,
      type: AllyType.soutien,
      rarity: rarity,
      faction: faction,
      teamCost: cost,
      ability: ability,
      effectText: effectText,
    );
  }

  factory Ally.special({
    required String name,
    required Faction faction,
    required String effectText,
    int? bonusAtkIfFriendly,
    int? bonusHpIfFriendly,
  }) {
    return Ally(
      name: name,
      type: AllyType.special,
      rarity: Rarity.legendaire,
      faction: faction,
      teamCost: 5,
      bonusAtkIfFriendly: bonusAtkIfFriendly,
      bonusHpIfFriendly: bonusHpIfFriendly,
      effectText: effectText,
    );
  }

  /// Copie avec remplacement de champs (limité aux champs mutables en
  /// jeu : la charge de soin des healers se consomme à l'usage).
  Ally copyWith({int? healInstant, bool clearHealInstant = false}) {
    return Ally(
      name: name,
      type: type,
      rarity: rarity,
      faction: faction,
      teamCost: teamCost,
      healAfterCombat: healAfterCombat,
      healInstant: clearHealInstant ? null : (healInstant ?? this.healInstant),
      hpBonus: hpBonus,
      dividesDamage: dividesDamage,
      squadBonusOwn: squadBonusOwn,
      squadBonusAllied: squadBonusAllied,
      bonusAtkIfFriendly: bonusAtkIfFriendly,
      bonusHpIfFriendly: bonusHpIfFriendly,
      instantDamageJedi: instantDamageJedi,
      instantDamageRebel: instantDamageRebel,
      bonusIfSithOwner: bonusIfSithOwner,
      bonusIfEmpireOwner: bonusIfEmpireOwner,
      ability: ability,
      effectText: effectText,
    );
  }

  /// La carte est-elle « amie » pour le porteur [ownerFaction] ?
  /// (faction propre ou faction alliée — table d'affinités du GDD.)
  bool isFriendlyTo(Faction ownerFaction) =>
      faction == ownerFaction || faction == ownerFaction.alliedFaction;

  /// Effet d'un nuker selon la faction du PORTEUR (décision du 07/09/2026) :
  ///  - faction propre → gros bonus ATK (⚔) ;
  ///  - faction alliée → bonus ATK réduit (⚔) ;
  ///  - factions ennemies → malus de PV (valeurs négatives dans l'Excel).
  /// Renvoie null pour les autres types de cartes.
  int? nukerOwnerEffect(Faction ownerFaction) {
    if (type != AllyType.nuker) return null;
    // Les colonnes de l'Excel sont nommées d'après la faction du joueur :
    // « Dégâts Jedi » = malus PV pour un porteur Jedi, « Bonus Empire » =
    // bonus ATK pour un porteur Empire, etc.
    return switch (ownerFaction) {
      Faction.jedi => instantDamageJedi,
      Faction.rebel => instantDamageRebel,
      Faction.sith => bonusIfSithOwner,
      Faction.empire => bonusIfEmpireOwner,
    };
  }

  /// Résumé de l'effet pour les fiches et dialogs.
  String get effectSummary {
    switch (type) {
      case AllyType.healer:
        return 'Soin après combat : +$healAfterCombat PV · '
            'Charge de soin : +$healInstant PV (à activer depuis '
            'l\'équipe)';
      case AllyType.tank:
        return dividesDamage
            ? 'Dégâts subis divisés par 2'
            : '+$hpBonus PV maximum';
      case AllyType.escouade:
        return effectText ?? 'Bonus ATK par carte (cumulatif par escouade)';
      case AllyType.nuker:
        return effectText ?? 'Bonus/malus selon votre faction';
      case AllyType.soutien:
      case AllyType.special:
        return effectText ?? '';
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': enumToName(type),
        'rarity': enumToName(rarity),
        'faction': enumToName(faction),
        'teamCost': teamCost,
        if (healAfterCombat != null) 'healAfterCombat': healAfterCombat,
        if (healInstant != null) 'healInstant': healInstant,
        if (hpBonus != null) 'hpBonus': hpBonus,
        if (dividesDamage) 'dividesDamage': true,
        if (squadBonusOwn != null) 'squadBonusOwn': squadBonusOwn,
        if (squadBonusAllied != null) 'squadBonusAllied': squadBonusAllied,
        if (bonusAtkIfFriendly != null)
          'bonusAtkIfFriendly': bonusAtkIfFriendly,
        if (bonusHpIfFriendly != null) 'bonusHpIfFriendly': bonusHpIfFriendly,
        if (instantDamageJedi != null) 'instantDamageJedi': instantDamageJedi,
        if (instantDamageRebel != null)
          'instantDamageRebel': instantDamageRebel,
        if (bonusIfSithOwner != null) 'bonusIfSithOwner': bonusIfSithOwner,
        if (bonusIfEmpireOwner != null)
          'bonusIfEmpireOwner': bonusIfEmpireOwner,
        if (ability != null) 'ability': ability,
        if (effectText != null) 'effectText': effectText,
      };

  factory Ally.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Ally(
      name: json['name'] as String,
      type: enumFromName(AllyType.values, json['type'], AllyType.nuker),
      rarity: enumFromName(Rarity.values, json['rarity'], Rarity.commun),
      faction: enumFromName(Faction.values, json['faction'], Faction.rebel),
      teamCost: (json['teamCost'] as num).toInt(),
      healAfterCombat: (json['healAfterCombat'] as num?)?.toInt(),
      healInstant: (json['healInstant'] as num?)?.toInt(),
      hpBonus: (json['hpBonus'] as num?)?.toInt(),
      dividesDamage: json['dividesDamage'] as bool? ?? false,
      squadBonusOwn: (json['squadBonusOwn'] as num?)?.toInt(),
      squadBonusAllied: (json['squadBonusAllied'] as num?)?.toInt(),
      bonusAtkIfFriendly: (json['bonusAtkIfFriendly'] as num?)?.toInt(),
      bonusHpIfFriendly: (json['bonusHpIfFriendly'] as num?)?.toInt(),
      instantDamageJedi: (json['instantDamageJedi'] as num?)?.toInt(),
      instantDamageRebel: (json['instantDamageRebel'] as num?)?.toInt(),
      bonusIfSithOwner: (json['bonusIfSithOwner'] as num?)?.toInt(),
      bonusIfEmpireOwner: (json['bonusIfEmpireOwner'] as num?)?.toInt(),
      ability: json['ability'] as String?,
      effectText: json['effectText'] as String?,
    );
  }
}
