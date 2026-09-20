/// Constantes de règles du jeu, issues du GDD et du CDC.
class GameConstants {
  GameConstants._();

  // ---------------------------------------------------------------------------
  // Déplacement (GDD §6, CDC §7)
  // ---------------------------------------------------------------------------

  /// Dé à 6 faces : la valeur devient un nombre de points de déplacement.
  static const int diceSides = 6;

  /// Rayon visible du brouillard de guerre : 3 cases autour du joueur actif,
  /// soit un carré de Chebyshev 7x7 (CDC §5 — décision du 07/09/2026,
  /// réduction de 6 à 3 cases pour concentrer l'exploration).
  static const int fogVisibleRadius = 3;

  // ---------------------------------------------------------------------------
  // Progression du personnage (GDD §7)
  // ---------------------------------------------------------------------------

  /// Niveau maximum atteignable (tables du GDD définissent les niveaux 1 à 6).
  static const int maxPlayerLevel = 6;

  /// XP cumulée requise pour atteindre chaque niveau.
  /// Index = niveau - 1 (niveau 1 → 0 XP, niveau 2 → 200 XP, …).
  static const List<int> xpRequiredPerLevel = [0, 200, 400, 700, 1000, 3000];

  /// Attaque de base par niveau.
  static const List<int> attackPerLevel = [125, 250, 450, 800, 1200, 2000];

  /// Points de vie de base par niveau.
  static const List<int> hpPerLevel = [200, 350, 700, 1100, 2000, 5000];

  /// XP cumulée requise pour atteindre [currentLevel] + 1, ou `null` si le
  /// niveau maximum est atteint.
  static int? xpRequiredForNextLevel(int currentLevel) {
    if (currentLevel < 1 || currentLevel >= maxPlayerLevel) return null;
    return xpRequiredPerLevel[currentLevel];
  }

  /// Attaque de base d'un joueur de niveau [level].
  static int attackForLevel(int level) => attackPerLevel[level - 1];

  /// PV de base d'un joueur de niveau [level].
  static int hpForLevel(int level) => hpPerLevel[level - 1];

  /// Rareté maximale d'équipement utilisable par niveau (GDD — Restrictions).
  /// Index = niveau - 1.
  static const List<int> maxRarityLevelIndexPerLevel = [
    0, // Niveau 1 → Commun
    0, // Niveau 2 → Commun
    1, // Niveau 3 → Rare
    2, // Niveau 4 → Épique
    3, // Niveau 5 → Légendaire
    4, // Niveau 6 → Mythique
  ];

  /// Niveau minimum requis pour utiliser une rareté (Commun 1, Rare 3,
  /// Épique 4, Légendaire 5, Mythique 6) — retours playtest : affiché dans
  /// les dialogs et la réserve au lieu du vague « rareté non autorisée ».
  static int minLevelForRarity(int rarityIndex) {
    for (int level = 1; level < maxRarityLevelIndexPerLevel.length; level++) {
      if (maxRarityLevelIndexPerLevel[level - 1] >= rarityIndex) return level;
    }
    return maxPlayerLevel;
  }

  // ---------------------------------------------------------------------------
  // Équipe (GDD §8, CDC §12)
  // ---------------------------------------------------------------------------

  /// 10 places d'équipe ; le personnage principal ne consomme aucune place.
  static const int teamCapacity = 10;

  // ---------------------------------------------------------------------------
  // Monstres (GDD §10) — utilisés à partir du Sprint 3
  // ---------------------------------------------------------------------------

  /// Statistiques des monstres par niveau : [attaque, PV, XP].
  /// Index = niveau du monstre - 1.
  static const List<List<int>> monsterStatsPerLevel = [
    [5, 200, 10], // Niveau 1
    [10, 300, 20], // Niveau 2
    [20, 500, 50], // Niveau 3
    [40, 800, 100], // Niveau 4
    [50, 1000, 200], // Niveau 5
  ];

  // ---------------------------------------------------------------------------
  // Case « Soin » (règle du game design, 07/09/2026 ; % des PV max depuis
  // les retours playtest du 10/09/2026 — les valeurs plates 10→300 soignaient
  // tout au N1 et étaient quasi inutiles au N6)
  // ---------------------------------------------------------------------------

  /// PV récupérés selon le lancer de dé, en fraction des PV MAXIMUM du
  /// joueur (index = résultat - 1), plafonnés au maximum.
  static const List<double> healRatioPerRoll = [
    0.05, // 1 → +5 %
    0.10, // 2 → +10 %
    0.15, // 3 → +15 %
    0.20, // 4 → +20 %
    0.25, // 5 → +25 %
    0.30, // 6 → +30 %
  ];

  static int healForRoll(int roll, {required int maxHp}) =>
      (maxHp *
              healRatioPerRoll[(roll - 1).clamp(0, healRatioPerRoll.length - 1)])
          .round();

  // ---------------------------------------------------------------------------
  // Boss (GDD §12, CDC §16) — utilisés à partir du Sprint 5
  // ---------------------------------------------------------------------------

  static const int bossHp = 10000;
  static const int bossAttackMin = 250;
  static const int bossAttackMax = 500;

  /// L'attaque aléatoire du boss varie par pas de 10 (CDC §16).
  static const int bossAttackStep = 10;

  /// Récompenses XP à la victoire sur un boss : 1er, 2e, 3e joueur.
  /// Tous les suivants reçoivent [bossXpRewardSubsequent].
  static const List<int> bossXpRewards = [400, 300, 200];
  static const int bossXpRewardSubsequent = 100;

  /// Retours playtest : chaque boss vaincu soigne +500 PV et augmente la
  /// capacité d'équipe du vainqueur de +2 places.
  static const int bossVictoryHeal = 500;
  static const int bossTeamCapacityBonus = 2;

  /// Fin de chaque tour : 50 % de chance que chaque boss se déplace d'une case.
  static const double bossMoveChance = 0.5;

  /// Carte Spéciale d'une faction ennemie : dégâts immédiats au joueur
  /// (pas de recrutement, la carte ne rejoint pas l'équipe — Sprint 4.3).
  /// Valeur de base Excel : elle passe dans [scaleIncomingDamage] avant
  /// application (retours playtest 10/09/2026).
  static const int specialEnemyDamage = 500;

  // ---------------------------------------------------------------------------
  // Dégâts reçus (retours playtest 10/09/2026) — ripostes de monstres/boss
  // et malus de cartes ennemies. NE s'applique PAS aux combats JvJ
  // (élimination à 0 PV préservée — GDD §13).
  // ---------------------------------------------------------------------------

  /// Multiplicateur des dégâts reçus selon le niveau du joueur
  /// (index = niveau - 1) : protège le début de partie.
  static const List<double> incomingDamageMultiplierPerLevel = [
    0.5, // Niveau 1
    0.7, // Niveau 2
    0.85, // Niveau 3
    1.0, // Niveau 4
    1.0, // Niveau 5
    1.0, // Niveau 6
  ];

  /// Plafond : un même coup ne peut pas retirer plus de 60 % des PV maximum
  /// du joueur — aucune source ne peut tuer seule.
  static const double incomingDamageMaxHpCapRatio = 0.6;

  /// Applique le multiplicateur de niveau puis le plafond de PV max.
  static int scaleIncomingDamage(int baseDamage,
      {required int level, required int maxHp}) {
    final double multiplier =
        incomingDamageMultiplierPerLevel[(level - 1).clamp(0, 5)];
    final int scaled = (baseDamage * multiplier).round();
    final int cap = (maxHp * incomingDamageMaxHpCapRatio).floor();
    return scaled.clamp(0, cap);
  }

  // ---------------------------------------------------------------------------
  // Événements du plateau (GDD addendum §4.1) — Sprint 3
  // ---------------------------------------------------------------------------

  /// Types d'événements, dans l'ordre des probabilités ci-dessous.
  /// Sprint 3 : seul « monstre » produit du contenu (allié/objet/soin au
  /// Sprint 4, portail au Sprint 5 — tirage non retenu si l'événement n'est
  /// pas encore actif : la case reste vide).
  static const List<String> eventTypes = [
    'monstre',
    'allie',
    'objet',
    'soin',
    'portail',
  ];

  /// Probabilités par phase : [monstre, allié, objet, soin, portail].
  /// Début (addendum) : 55/20/10/15 — le portail n'existe pas en début.
  static const List<double> eventProbabilitiesDebut = [
    0.55,
    0.20,
    0.10,
    0.15,
    0.00,
  ];

  /// Milieu : 40/25/20/10/5.
  static const List<double> eventProbabilitiesMilieu = [
    0.40,
    0.25,
    0.20,
    0.10,
    0.05,
  ];

  /// Fin : 25/20/30/15/10 — portail relevé de 5 % à 10 % (retours
  /// playtest 10/09/2026 : à 5 %, trouver les 4 portails était quasi
  /// impossible — une partie découvre 150-250 cases, soit ~1 à 2 tirages
  /// bruts sur le bord ; à 10 %, les 4 portails redeviennent atteignables
  /// en fin de partie). La compensation vient du monstre (30 → 25 %).
  static const List<double> eventProbabilitiesFin = [
    0.25,
    0.20,
    0.30,
    0.15,
    0.10,
  ];

  // ---------------------------------------------------------------------------
  // Combat entre joueurs (GDD §13) — utilisé à partir du Sprint 3
  // ---------------------------------------------------------------------------

  /// XP gagnée par l'adversaire lorsqu'un joueur est éliminé.
  static const int playerKillXpReward = 500;

  /// Bonus XP du soutien « +20 XP en plus après chaque combat »
  /// (retours playtest 10/09/2026).
  static const int supportBonusXp = 20;

  // ---------------------------------------------------------------------------
  // Conditions de victoire (GDD §16, CDC §17) — utilisées à partir du Sprint 5
  // ---------------------------------------------------------------------------

  /// Nombre de boss différents à vaincre pour la victoire par objectifs.
  static const int bossesToWin = 3;
}
