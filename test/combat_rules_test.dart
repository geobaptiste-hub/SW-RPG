import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';

Player _player({int hp = 200, int xp = 0}) => Player(
      id: 'p1',
      name: 'Luke Skywalker',
      faction: Faction.jedi,
      position: const Position(0, 0),
      level: 1,
      xp: xp,
      attack: 125,
      hp: hp,
      maxHp: 200,
    );

void main() {
  group('CombatService — jet et dégâts', () {
    test('le dé d attaque sort entre 1 et 6', () {
      final CombatService combat = CombatService(random: Random(1));
      for (int i = 0; i < 200; i++) {
        expect(combat.rollAttackDice(), inInclusiveRange(1, 6));
      }
    });

    test('un 6 est un critique, les autres jets non', () {
      expect(CombatService.isCritical(6), isTrue);
      for (int roll = 1; roll <= 5; roll++) {
        expect(CombatService.isCritical(roll), isFalse);
      }
    });

    test('dégâts doublés en cas de critique (décision 07/09/2026)', () {
      expect(CombatService.attackDamage(attackTotal: 125, roll: 6), 250);
      expect(CombatService.attackDamage(attackTotal: 125, roll: 3), 125);
      expect(CombatService.attackDamage(attackTotal: 2000, roll: 6), 4000);
    });
  });

  group('XP et montée de niveau (GDD §7, décision PV au nouveau max)', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    GameController controller() =>
        container.read(gameControllerProvider.notifier);

    test('sous le premier palier : XP cumulée, niveau inchangé', () {
      final Player result = controller().applyXpGain(_player(), 199);
      expect(result.level, 1);
      expect(result.xp, 199);
    });

    test('200 XP : niveau 2, ATK 250, PV remis au nouveau max (350)', () {
      final Player result = controller().applyXpGain(_player(), 200);
      expect(result.level, 2);
      expect(result.xp, 200);
      expect(result.attack, 250);
      expect(result.maxHp, 350);
      expect(result.hp, 350, reason: 'PV remis au nouveau maximum');
    });

    test('plusieurs paliers franchis en une fois', () {
      final Player result = controller().applyXpGain(_player(), 1300);
      expect(result.level, 5, reason: '200 + 400 + 700 = 1300 XP cumulés');
      expect(result.attack, 1200);
      expect(result.hp, 2000);
    });

    test('cap au niveau 6 (3000 XP), pas de dépassement', () {
      final Player result = controller().applyXpGain(_player(), 9999);
      expect(result.level, 6);
      expect(result.attack, 2000);
      expect(result.maxHp, 5000);
      expect(result.hp, 5000);
    });

    test('les blessures sont soignées par le passage de niveau', () {
      final Player wounded = _player(hp: 10);
      final Player result = controller().applyXpGain(wounded, 200);
      expect(result.level, 2);
      expect(result.hp, 350);
    });
  });
}
