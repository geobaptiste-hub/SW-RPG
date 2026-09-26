import 'dart:math';

import '../../models/monster.dart';
import 'game_constants.dart';

/// Une carte monstre du fichier « Données cartes.xlsx » (référence des
/// données — 20 monstres nommés, 4 par niveau).
class MonsterCard {
  final String name;
  final int level;

  /// Nombre de cartes de ce monstre dans le jeu (Excel) : 6/4/2/1 selon le
  /// niveau. Sert de pondération au tirage en partie (56 cartes de monstres
  /// au total, bosses exclus).
  final int cardCount;

  const MonsterCard(this.name, this.level, this.cardCount);
}

/// Deck de monstres issu du fichier de données (Sprint 3).
///
/// Les 4 boss (AT-AT, Rancor, Krayt Dragon, Exogorth) ne font PAS partie du
/// deck de rencontre : ils sont liés aux planètes secondaires (Sprint 5),
/// leurs statistiques sont dans GameConstants.
class MonsterConstants {
  MonsterConstants._();

  /// Les 20 monstres nommés du fichier de données.
  static const List<MonsterCard> deck = [
    // Niveau 1 — 6 cartes chacun
    MonsterCard('Droïde sonde', 1, 6),
    MonsterCard('Gungans', 1, 6),
    MonsterCard('Ewoks', 1, 6),
    MonsterCard('Hommes des sables', 1, 6),
    // Niveau 2 — 4 cartes chacun
    MonsterCard('Droïde de combat B1', 2, 4),
    MonsterCard('Jawa', 2, 4),
    MonsterCard('Tauntaun', 2, 4),
    MonsterCard('Gamorréens', 2, 4),
    // Niveau 3 — 2 cartes chacun
    MonsterCard('IG-100 MagnaGuard', 3, 2),
    MonsterCard('Nexu', 3, 2),
    MonsterCard('Wampa', 3, 2),
    MonsterCard('Varactyl carnivores', 3, 2),
    // Niveau 4 — 1 carte chacun
    MonsterCard('Droïde de combat B2', 4, 1),
    MonsterCard('Zillo Beast', 4, 1),
    MonsterCard('Acklay', 4, 1),
    MonsterCard('AT-ST', 4, 1),
    // Niveau 5 — 1 carte chacun
    MonsterCard('Droïdeka', 5, 1),
    MonsterCard('Bendu', 5, 1),
    MonsterCard('Reek', 5, 1),
    MonsterCard('Sarlacc', 5, 1),
  ];

  /// Total de cartes de monstres (hors boss) : 56.
  static int get totalCards =>
      deck.fold(0, (int total, MonsterCard card) => total + card.cardCount);

  /// Tire une carte uniformément parmi les 56 cartes du deck (pondération
  /// naturelle : ≈ 43 % N1, 29 % N2, 14 % N3, 7 % N4, 7 % N5) et construit
  /// le monstre avec les statistiques officielles de son niveau.
  /// Tirage pondéré restreint aux niveaux 1-3 (retours playtest 20/09 :
  /// les « doubles monstres » associent deux monstres de niveaux 1 à 3).
  static Monster randomLowMonster(Random rng) {
    final List<MonsterCard> pool = deck
        .where((MonsterCard card) => card.level >= 1 && card.level <= 3)
        .toList();
    final int total =
        pool.fold(0, (int total, MonsterCard card) => total + card.cardCount);
    int roll = rng.nextInt(total);
    for (final MonsterCard card in pool) {
      roll -= card.cardCount;
      if (roll < 0) return Monster.forCard(card.name, card.level);
    }
    return Monster.forCard(pool.last.name, pool.last.level);
  }

  static Monster randomMonster(Random rng) {
    int roll = rng.nextInt(totalCards);
    for (final MonsterCard card in deck) {
      roll -= card.cardCount;
      if (roll < 0) {
        return Monster.forCard(card.name, card.level);
      }
    }
    // Inatteignable (le tirage couvre tout le deck).
    throw StateError('Tirage de monstre hors deck');
  }

  /// Les 4 boss des planètes secondaires (Sprint 5) — référencés ici pour
  /// traçabilité avec le fichier de données.
  static const List<String> bossNames = [
    'AT-AT',
    'Rancor',
    'Krayt Dragon',
    'Exogorth',
  ];

  /// Vérifications d'intégrité du deck avec les tables du GDD.
  static bool get isDeckConsistent {
    for (final MonsterCard card in deck) {
      if (card.level < 1 ||
          card.level > GameConstants.monsterStatsPerLevel.length) {
        return false;
      }
    }
    return totalCards == 56;
  }
}
