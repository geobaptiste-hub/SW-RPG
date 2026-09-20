/// Énumérations partagées entre les modèles et les services.
///
/// Ces énumérations sont définies dans `core/constants` car elles sont
/// utilisées par plusieurs modèles (armes, armures, alliés, état de jeu)
/// sans appartenir à un modèle en particulier.
library;

/// Rareté des cartes (GDD — Équipement et alliés).
///
/// Bonus associés (GDD) :
///  - Armes  : Commun +50 ATK, Rare +100, Épique +250, Légendaire +500, Mythique +1000.
///  - Tenues : Commun +100 PV, Rare +200, Épique +500, Légendaire +1000, Mythique +2000.
enum Rarity {
  commun,
  rare,
  epique,
  legendaire,
  mythique;

  /// Bonus d'attaque d'une carte d'équipement de cette rareté (GDD).
  int get attackBonus => switch (this) {
        Rarity.commun => 50,
        Rarity.rare => 100,
        Rarity.epique => 250,
        Rarity.legendaire => 500,
        Rarity.mythique => 1000,
      };

  /// Bonus de points de vie d'une tenue de cette rareté (GDD).
  int get hpBonus => switch (this) {
        Rarity.commun => 100,
        Rarity.rare => 200,
        Rarity.epique => 500,
        Rarity.legendaire => 1000,
        Rarity.mythique => 2000,
      };

  /// Nom affiché en français.
  String get displayName => switch (this) {
        Rarity.commun => 'Commun',
        Rarity.rare => 'Rare',
        Rarity.epique => 'Épique',
        Rarity.legendaire => 'Légendaire',
        Rarity.mythique => 'Mythique',
      };
}

/// Familles de cartes alliés (GDD — Répartition des cartes).
enum AllyType {
  healer,
  tank,
  nuker,
  escouade,
  soutien,
  special;

  String get displayName => switch (this) {
        AllyType.healer => 'Healer',
        AllyType.tank => 'Tank',
        AllyType.nuker => 'Nuker',
        AllyType.escouade => 'Escouade',
        AllyType.soutien => 'Soutien',
        AllyType.special => 'Spécial',
      };
}

/// Mode de jeu choisi à l'étape 1 de la création de partie (CDC §4,
/// Big Four — retours playtest).
enum GameMode {
  chacunPourSoi,
  equipes,
  bigFour;

  String get displayName => switch (this) {
        GameMode.chacunPourSoi => 'Chacun pour soi',
        GameMode.equipes => 'Équipes',
        GameMode.bigFour => 'Big Four',
      };
}

/// Équipes des modes à équipes : Équipes (2 camps) et Big Four (4 équipes
/// de 2, une par faction — retours playtest).
enum TeamSide {
  teamA,
  teamB,
  teamC,
  teamD;

  String get displayName => switch (this) {
        TeamSide.teamA => 'Équipe A',
        TeamSide.teamB => 'Équipe B',
        TeamSide.teamC => 'Équipe C',
        TeamSide.teamD => 'Équipe D',
      };
}

/// Phase de partie (GDD addendum §4.1) : pilote la distribution des
/// événements lors de la découverte des cases.
enum GamePhase {
  debut,
  milieu,
  fin;

  String get displayName => switch (this) {
        GamePhase.debut => 'Début de partie',
        GamePhase.milieu => 'Milieu de partie',
        GamePhase.fin => 'Fin de partie',
      };
}

/// État global de la partie.
enum GameStatus {
  inProgress,
  finished;

  String get displayName => switch (this) {
        GameStatus.inProgress => 'En cours',
        GameStatus.finished => 'Terminée',
      };
}
