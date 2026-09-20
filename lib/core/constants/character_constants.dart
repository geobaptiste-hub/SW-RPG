import '../../models/player.dart';

/// Définition d'un personnage principal jouable (8 cartes personnages,
/// 2 par faction — GDD addendum « Répartition des cartes »).
class CharacterDefinition {
  final String id;
  final String name;
  final Faction faction;

  const CharacterDefinition({
    required this.id,
    required this.name,
    required this.faction,
  });
}

/// Les 8 personnages principaux sélectionnables à l'étape 4 de la
/// création de partie (CDC §4).
class CharacterConstants {
  CharacterConstants._();

  /// Factions et noms alignés sur le fichier de référence
  /// « Données cartes.xlsx » (décision du 07/09/2026) :
  /// Rebel = Leia, Padmé ; Jedi = Yoda, Luke ; Empire = L'empereur, Tarkin ;
  /// Sith = Vador, Nihilus.
  static const List<CharacterDefinition> characters = [
    // Faction Rebel
    CharacterDefinition(
      id: 'luke_skywalker',
      name: 'Luke Skywalker',
      faction: Faction.jedi,
    ),
    CharacterDefinition(
      id: 'princesse_leia',
      name: 'Princesse Leia',
      faction: Faction.rebel,
    ),
    // Faction Jedi
    CharacterDefinition(id: 'yoda', name: 'Yoda', faction: Faction.jedi),
    CharacterDefinition(
      id: 'padme_amidala',
      name: 'Padmé Amidala',
      faction: Faction.rebel,
    ),
    // Faction Empire
    CharacterDefinition(
      id: 'empereur_palpatine',
      name: "L'empereur",
      faction: Faction.empire,
    ),
    CharacterDefinition(
      id: 'darth_nihilus',
      name: 'Dark Nihilus',
      faction: Faction.sith,
    ),
    // Faction Sith
    CharacterDefinition(
      id: 'dark_vador',
      name: 'Dark Vador',
      faction: Faction.sith,
    ),
    CharacterDefinition(
      id: 'grand_moff_tarkin',
      name: 'Grand Moff Tarkin',
      faction: Faction.empire,
    ),
  ];

  // TODO(Design) : le GDD ne définit aucune statistique différenciée entre
  // les personnages (tous suivent les tables de progression du §7).
  // Si des stats spécifiques par personnage sont ajoutées plus tard, elles
  // devront être définies ici ou dans le GDD.
  // Note (07/09/2026) : le fichier Excel affiche 2000 XP au niveau 6 pour
  // L'empereur (contre 3000 pour les 7 autres) — traité comme une erreur de
  // copie : tous les personnages suivent la table commune (décision actée).

  /// Recherche d'un personnage par identifiant.
  static CharacterDefinition byId(String id) =>
      characters.firstWhere((c) => c.id == id,
          orElse: () => throw ArgumentError('Personnage inconnu : $id'));
}
