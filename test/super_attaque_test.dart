import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';

class _FakeSaveService extends SaveService {
  @override
  Future<bool> hasSave() async => false;

  @override
  Future<void> save(GameState state) async {}

  @override
  Future<GameState?> load() async => null;

  @override
  Future<void> deleteSave() async {}
}

ProviderContainer _container(int combatSeed) => ProviderContainer(
      overrides: <Override>[
        saveServiceProvider.overrideWithValue(_FakeSaveService()),
        combatServiceProvider
            .overrideWithValue(CombatService(random: Random(combatSeed))),
      ],
    );

final MapService mapService = MapService();

Player _player({
  Position position = const Position(0, 0),
  int hp = 200,
  int maxHp = 200,
  int superAttackReadyTurn = 0,
}) =>
    Player(
      id: 'p1',
      name: 'Luke Skywalker',
      faction: Faction.jedi,
      position: position,
      planet: PlanetType.hoth,
      level: 1,
      xp: 0,
      attack: 125,
      hp: hp,
      maxHp: maxHp,
      superAttackReadyTurn: superAttackReadyTurn,
    );

/// État prêt pour un combat contre un Wampa (20 ATK, 500 PV, 50 XP) posé
/// sur [monsterTile] de la planète Hoth (graine 42).
GameState _state({
  required Planet planet,
  required Position monsterTile,
  required List<Player> players,
  int turn = 1,
}) {
  final List<Tile> tiles = List<Tile>.of(planet.tiles);
  tiles[monsterTile.y * planet.width + monsterTile.x] =
      tiles[monsterTile.y * planet.width + monsterTile.x]
          .copyWith(monster: Monster.forCard('Wampa', 3));
  final Planet crafted = planet.withTiles(tiles);
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'super_attaque_test',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.hoth,
    currentPlanet: crafted,
    planets: <PlanetType, Planet>{PlanetType.hoth: crafted},
    players: players,
    turn: turn,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: 2,
    lastDiceRoll: 2,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
}

/// Démarre un combat contre le Wampa de la case [tile] et le retourne.
CombatController _startCombat(ProviderContainer container, Position tile) {
  final CombatController combat =
      container.read(combatControllerProvider.notifier);
  combat.startMonsterCombat(tile);
  return combat;
}

void main() {
  group('Plage de dégâts ±10 % (retours playtest 10/10)', () {
    test('rollPlayerAttack : ATK 200 → uniquement 180 à 220', () {
      final CombatService combat = CombatService(random: Random(9));
      for (int i = 0; i < 500; i++) {
        expect(combat.rollPlayerAttack(200), inInclusiveRange(180, 220));
      }
    });

    test('rollSuperAttackHit : ~50 % de réussite', () {
      final CombatService combat = CombatService(random: Random(3));
      int hits = 0;
      for (int i = 0; i < 1000; i++) {
        if (combat.rollSuperAttackHit()) hits++;
      }
      expect(hits, inInclusiveRange(400, 600),
          reason: '50 % attendu, bornes larges (aléatoire contrôlé)');
    });
  });

  group('SUPER ATTAQUE — comportement en combat', () {
    test('recharge posée à tour + 5, une seule par combat, dégâts cohérents '
        '(réussie OU loupée, selon la graine)', () {
      int hits = 0;
      int misses = 0;
      for (int seed = 1; seed <= 40; seed++) {
        final Planet planet =
            mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
        final Player player = _player(position: const Position(0, 0));
        final Position target = mapService
            .validMoveTargets(
                planet: planet, players: <Player>[player],
                activePlayerIndex: 0)
            .first;
        final ProviderContainer container = _container(seed);
        addTearDown(container.dispose);
        final GameController controller =
            container.read(gameControllerProvider.notifier);
        controller.state =
            _state(planet: planet, monsterTile: target, players: <Player>[player]);

        final CombatController combat = _startCombat(container, target);
        final int hpAvant =
            container.read(combatControllerProvider)!.monsterHpRemaining;
        combat.superAttack();
        final CombatSession session =
            container.read(combatControllerProvider)!;

        // Quel que soit le résultat : utilisée + recharge de 5 tours.
        expect(session.superAttackUsed, isTrue,
            reason: 'seed $seed : une seule par combat (flag posé)');
        expect(session.finished, isFalse,
            reason: 'seed $seed : le Wampa (500 PV) survit à un seul super');
        final GameState game = container.read(gameControllerProvider)!;
        expect(game.players[0].superAttackReadyTurn, game.turn + 5,
            reason: 'seed $seed : recharge posée à tour + 5');

        if (session.superAttackResult == 1) {
          hits++;
          // Réussie : 3 × ATK ±10 % → 3 × [112, 137] = 336-411 dégâts.
          expect(session.lastDamage, inInclusiveRange(336, 411),
              reason: 'seed $seed');
          expect(session.monsterHpRemaining, lessThanOrEqualTo(hpAvant - 336),
              reason: 'seed $seed : le monstre a bien encaissé le ×3');
        } else {
          misses++;
          // Loupée : aucun dégât, mais le monstre RIPOSTE (décision 10/10).
          expect(session.superAttackResult, 2, reason: 'seed $seed');
          expect(session.lastDamage, 0, reason: 'seed $seed : loupé');
          expect(session.monsterHpRemaining, hpAvant,
              reason: 'seed $seed : monstre indemne');
          expect(session.playerHp, lessThan(200),
              reason: 'seed $seed : la riposte s\'applique même loupé');
          expect(session.damageTaken, greaterThan(0),
              reason: 'seed $seed : dégâts subis par la riposte');
        }

        // Une seule utilisation par combat : le second appel est sans effet.
        final int readyTurn = game.players[0].superAttackReadyTurn;
        combat.superAttack();
        final CombatSession again = container.read(combatControllerProvider)!;
        expect(again.superAttackUsed, isTrue);
        expect(container.read(gameControllerProvider)!.players[0]
            .superAttackReadyTurn, readyTurn,
            reason: 'seed $seed : pas de double recharge');
        expect(again.attacksUsed, session.attacksUsed,
            reason: 'seed $seed : le second appel ne fait rien');
      }
      expect(hits, greaterThan(0),
          reason: '40 graines : au moins une super attaque réussie');
      expect(misses, greaterThan(0),
          reason: '40 graines : au moins une super attaque loupée');
    });

    test('refusée pendant la recharge (readyTurn non atteint)', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player =
          _player(position: const Position(0, 0), superAttackReadyTurn: 99);
      final Position target = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[player], activePlayerIndex: 0)
          .first;
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
          planet: planet, monsterTile: target, players: <Player>[player]);

      final CombatController combat = _startCombat(container, target);
      final int hpAvant =
          container.read(combatControllerProvider)!.monsterHpRemaining;
      combat.superAttack();

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.superAttackUsed, isFalse,
          reason: 'en recharge : la super attaque ne part pas');
      expect(session.monsterHpRemaining, hpAvant);
      expect(container.read(gameControllerProvider)!.players[0]
          .superAttackReadyTurn, 99,
          reason: 'la recharge existante n\'est pas repoussée');
    });

    test('réutilisable exactement 5 tours du jeu plus tard', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);

      // Tour 5 (recharge jusqu'au tour 6 incluse depuis le tour 1) : refus.
      Position firstTarget(Position from, Player p) => mapService
          .validMoveTargets(
              planet: planet, players: <Player>[p], activePlayerIndex: 0)
          .first;
      {
        final Player player = _player(superAttackReadyTurn: 6);
        final Position target = firstTarget(const Position(0, 0), player);
        final ProviderContainer container = _container(5);
        addTearDown(container.dispose);
        container.read(gameControllerProvider.notifier).state = _state(
            planet: planet,
            monsterTile: target,
            players: <Player>[player],
            turn: 5);
        final CombatController combat = _startCombat(container, target);
        combat.superAttack();
        expect(container.read(combatControllerProvider)!.superAttackUsed,
            isFalse,
            reason: 'tour 5 < readyTurn 6 : encore en recharge');
      }

      // Tour 6 : la super attaque est de nouveau disponible.
      {
        final Player player = _player(superAttackReadyTurn: 6);
        final Position target = firstTarget(const Position(0, 0), player);
        final ProviderContainer container = _container(5);
        addTearDown(container.dispose);
        container.read(gameControllerProvider.notifier).state = _state(
            planet: planet,
            monsterTile: target,
            players: <Player>[player],
            turn: 6);
        final CombatController combat = _startCombat(container, target);
        combat.superAttack();
        final CombatSession session =
            container.read(combatControllerProvider)!;
        expect(session.superAttackUsed, isTrue,
            reason: 'tour 6 >= readyTurn 6 : disponible');
        expect(
            container.read(gameControllerProvider)!.players[0]
                .superAttackReadyTurn,
            6 + 5,
            reason: 'nouvelle recharge de 5 tours depuis le tour 6');
      }
    });
  });

  group('Sérialisation de la recharge (sauvegarde)', () {
    test('round-trip JSON conserve superAttackReadyTurn ; champ absent → 0',
        () {
      final Player player = _player().copyWith(superAttackReadyTurn: 7);
      final Player round = Player.fromJson(player.toJson());
      expect(round.superAttackReadyTurn, 7);

      // Ancienne sauvegarde sans le champ : disponible dès le début (0).
      final Map<String, dynamic> old = player.toJson()
        ..remove('superAttackReadyTurn');
      expect(Player.fromJson(old).superAttackReadyTurn, 0);
    });
  });

  test('GameConstants utilisés par la super attaque : aucun changement '
      'de palier XP cassé', () {
    // Garde-fou léger : la recharge est de 5 tours du jeu.
    expect(GameConstants.xpRequiredPerLevel[1], 200);
  });
}
