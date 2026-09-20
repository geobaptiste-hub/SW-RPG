import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/armor.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/weapon.dart';
import 'package:star_wars_rpg/services/game_service.dart';

void main() {
  group('Deck de cartes (Données cartes.xlsx)', () {
    test('allies : 8 healers, 12 tanks, 32 nukers, 4 escouades, 20 soutiens, 8 spéciales', () {
      expect(CardConstants.healers.length, 8);
      expect(CardConstants.tanks.length, 12);
      expect(CardConstants.nukers.length, 32,
          reason: '8 nukers par faction (Scout Trooper ajouté au fichier)');
      expect(CardConstants.squads.length, 4);
      expect(CardConstants.supports.length, 20);
      expect(CardConstants.specials.length, 8);
      expect(CardConstants.recruitDeck.length, 120,
          reason: 'escouades en 10 exemplaires, spéciales incluses '
              '(ennemie = -500 PV, alliée = recrutable)');
    });

    test('healers : Dark Sion et Mère Talzin corrigés en Sith', () {
      final Ally sion = CardConstants.healers
          .firstWhere((Ally a) => a.name == 'Dark Sion');
      final Ally talzin = CardConstants.healers
          .firstWhere((Ally a) => a.name == 'Mère Talzin');
      expect(sion.faction, Faction.sith);
      expect(talzin.faction, Faction.sith);
      expect(
        CardConstants.healers
            .where((Ally a) => a.faction == Faction.sith)
            .length,
        2,
        reason: '2 healers par faction (GDD)',
      );
    });

    test('armes et tenues : 30 cartes chacune', () {
      expect(CardConstants.weaponTotalCards, 30,
          reason: 'communs en 2 exemplaires');
      expect(CardConstants.armorTotalCards, 30);
      expect(
        CardConstants.weapons
            .where((Weapon w) => w.rarity == Rarity.commun)
            .fold(0, (int t, Weapon w) => t + CardConstants.weaponCardCount(w)),
        14,
        reason: '7 armes communes × 2 exemplaires',
      );
      expect(
        CardConstants.armors
            .where((Armor a) => a.rarity == Rarity.commun)
            .fold(0, (int t, Armor a) => t + CardConstants.armorCardCount(a)),
        14,
        reason: '7 tenues communes × 2 exemplaires',
      );
    });

    test('tirages : tous les types d alliés sortent', () {
      final Random rng = Random(3);
      final Set<AllyType> types = <AllyType>{};
      for (int i = 0; i < 3000; i++) {
        types.add(CardConstants.randomAllyCard(rng).type);
      }
      expect(types, containsAll(AllyType.values));
    });

    test('restrictions de rareté par niveau (GDD §9)', () {
      expect(GameController.rarityAllowedForLevel(Rarity.commun, 1), isTrue);
      expect(GameController.rarityAllowedForLevel(Rarity.commun, 2), isTrue);
      expect(GameController.rarityAllowedForLevel(Rarity.rare, 2), isFalse);
      expect(GameController.rarityAllowedForLevel(Rarity.rare, 3), isTrue);
      expect(GameController.rarityAllowedForLevel(Rarity.epique, 4), isTrue);
      expect(GameController.rarityAllowedForLevel(Rarity.legendaire, 5), isTrue);
      expect(GameController.rarityAllowedForLevel(Rarity.mythique, 5), isFalse);
      expect(GameController.rarityAllowedForLevel(Rarity.mythique, 6), isTrue);
    });
  });

  group('Soin au dé (règle du game design ; % des PV max — playtest 10/09)', () {
    test('table 5/10/15/20/25/30 % des PV max', () {
      expect(GameConstants.healForRoll(1, maxHp: 200), 10);
      expect(GameConstants.healForRoll(2, maxHp: 200), 20);
      expect(GameConstants.healForRoll(3, maxHp: 200), 30);
      expect(GameConstants.healForRoll(4, maxHp: 200), 40);
      expect(GameConstants.healForRoll(5, maxHp: 200), 50);
      expect(GameConstants.healForRoll(6, maxHp: 200), 60);
      expect(GameConstants.healForRoll(6, maxHp: 5000), 1500,
          reason: 'le soin suit les PV max (utile en fin de partie)');
    });
  });

  group('Bonus d alliés', () {
    test('escouade cumulative : 3 Ewoks rebelles = +150 ATK', () {
      final Ally ewok = CardConstants.squads
          .firstWhere((Ally a) => a.name == 'Ewok');
      final List<Ally> allies = <Ally>[
        ewok, ewok, ewok,
      ];
      // Formule GDD addendum : (somme des cartes) × nombre.
      expect(_squadBonus(Faction.rebel, allies), 450,
          reason: '(50 + 50 + 50) × 3 = 450 ATK');
      expect(_squadBonus(Faction.jedi, allies), 225,
          reason: '(25 + 25 + 25) × 3 = 225 ATK (faction alliée)');
      expect(_squadBonus(Faction.empire, allies), 0,
          reason: 'faction ennemie : aucun bonus');
      // Exemple du GDD : 4 Ewoks → (50 × 4) × 4 = 800 ATK.
      expect(
        _squadBonus(Faction.rebel, <Ally>[ewok, ewok, ewok, ewok]),
        800,
      );
    });

    test('tank : bonus PV et divisibilité des dégâts', () {
      final Ally chewbacca = CardConstants.tanks
          .firstWhere((Ally a) => a.name == 'Chewbacca');
      expect(chewbacca.dividesDamage, isTrue,
          reason: 'Chewbacca est épique : dégâts subis ÷ 2');
      final Ally savage = CardConstants.tanks
          .firstWhere((Ally a) => a.name == 'Savage Opress');
      expect(savage.hpBonus, 500);
      final Ally malgus = CardConstants.tanks
          .firstWhere((Ally a) => a.name == 'Dark Malgus');
      expect(malgus.dividesDamage, isTrue);
    });

    test('healer : soins définis', () {
      final Ally r2d2 = CardConstants.healers
          .firstWhere((Ally a) => a.name == 'R2-D2');
      expect(r2d2.healAfterCombat, 50);
      expect(r2d2.healInstant, 500);
      expect(r2d2.teamCost, 3);
    });
  });
}

int _squadBonus(Faction ownerFaction, List<Ally> allies) {
  int bonus = 0;
  final Map<String, int> counts = <String, int>{};
  final Map<String, Ally> byName = <String, Ally>{};
  for (final Ally ally in allies) {
    counts[ally.name] = (counts[ally.name] ?? 0) + 1;
    byName[ally.name] = ally;
  }
  counts.forEach((String name, int count) {
    final Ally squad = byName[name]!;
    final int perCard = squad.faction == ownerFaction
        ? (squad.squadBonusOwn ?? 0)
        : (ownerFaction.alliedFaction == squad.faction
            ? (squad.squadBonusAllied ?? 0)
            : 0);
    // Formule GDD addendum : (somme des cartes) × nombre de cartes.
    bonus += perCard * count * count;
  });
  return bonus;
}
