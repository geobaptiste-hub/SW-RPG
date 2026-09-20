import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/core/constants/monster_constants.dart';
import 'package:star_wars_rpg/models/monster.dart';

void main() {
  group('Deck de monstres (Données cartes.xlsx)', () {
    test('20 monstres nommés, 56 cartes, niveaux 1 à 5', () {
      expect(MonsterConstants.deck.length, 20);
      expect(MonsterConstants.totalCards, 56);
      expect(MonsterConstants.isDeckConsistent, isTrue);

      for (int level = 1; level <= 5; level++) {
        expect(
          MonsterConstants.deck
              .where((MonsterCard card) => card.level == level)
              .length,
          4,
          reason: '4 monstres nommés par niveau',
        );
      }
    });

    test('les boss ne font pas partie du deck de rencontre', () {
      for (final String boss in MonsterConstants.bossNames) {
        expect(
          MonsterConstants.deck.any((MonsterCard card) => card.name == boss),
          isFalse,
          reason: '$boss est lié à une planète secondaire (Sprint 5)',
        );
      }
    });

    test('Monster.forCard applique les statistiques officielles (GDD §10)',
        () {
      final Monster n1 = Monster.forCard('Ewoks', 1);
      expect(n1.attack, 5);
      expect(n1.hp, 200);
      expect(n1.xpReward, 10);

      final Monster n3 = Monster.forCard('Wampa', 3);
      expect(n3.attack, 20);
      expect(n3.hp, 500);
      expect(n3.xpReward, 50);

      final Monster n5 = Monster.forCard('Sarlacc', 5);
      expect(n5.attack, 50);
      expect(n5.hp, 1000);
      expect(n5.xpReward, 200);
    });

    test('randomMonster : tirage toujours cohérent avec le deck', () {
      final Random rng = Random(42);
      final Set<String> namesSeen = <String>{};
      final Set<int> levelsSeen = <int>{};
      for (int i = 0; i < 2000; i++) {
        final Monster monster = MonsterConstants.randomMonster(rng);
        expect(monster.hp, GameConstants.monsterStatsPerLevel[monster.level - 1][1]);
        namesSeen.add(monster.name);
        levelsSeen.add(monster.level);
      }
      expect(namesSeen.length, 20,
          reason: 'Tous les monstres finissent par sortir');
      expect(levelsSeen, {1, 2, 3, 4, 5});
    });

    test('pondération : les N1 sortent plus souvent que les N5', () {
      final Random rng = Random(7);
      final Map<int, int> counts = <int, int>{};
      for (int i = 0; i < 5600; i++) {
        final Monster monster = MonsterConstants.randomMonster(rng);
        counts[monster.level] = (counts[monster.level] ?? 0) + 1;
      }
      expect(counts[1]!, greaterThan(counts[5]! * 4),
          reason: '24 cartes N1 contre 4 cartes N5');
    });
  });
}
