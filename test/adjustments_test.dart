import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/game_state.dart';
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

ProviderContainer _container(int seed) =>
    ProviderContainer(overrides: <Override>[
      saveServiceProvider.overrideWithValue(_FakeSaveService()),
      combatServiceProvider
          .overrideWithValue(CombatService(random: Random(seed))),
    ]);

Player _player(Faction faction, Position position, {int hp = 200}) => Player(
      id: 'p_${faction.name}_${position.x}_${position.y}',
      name: 'Joueur ${faction.name}',
      faction: faction,
      position: position,
      level: 1,
      xp: 0,
      attack: 125,
      hp: hp,
      maxHp: 200,
    );

GameState _state(Planet planet, List<Player> players, {int active = 0}) =>
    GameState(
      schemaVersion: GameState.currentSchemaVersion,
      gameId: 'adj_test',
      seed: 42,
      mode: GameMode.chacunPourSoi,
      teamSize: 0,
      planetType: PlanetType.hoth,
      currentPlanet: planet,
      players: players,
      turn: 1,
      currentPlayerIndex: active,
      gameTimeSeconds: 0,
      movementPointsRemaining: 5,
      lastDiceRoll: 5,
      bosses: const [],
      portals: const [],
      status: GameStatus.inProgress,
    );

void main() {
  group('Nukers — effet selon le porteur (décision 07/09/2026)', () {
    final Ally scout =
        CardConstants.nukers.firstWhere((Ally a) => a.name == 'Scout Trooper');

    test('Empire nuker : +200 pour Empire, +100 pour Sith', () {
      expect(scout.nukerOwnerEffect(Faction.empire), 200);
      expect(scout.nukerOwnerEffect(Faction.sith), 100);
    });

    test('malus PV pour les factions ennemies', () {
      expect(scout.nukerOwnerEffect(Faction.jedi), -50);
      expect(scout.nukerOwnerEffect(Faction.rebel), -100);
    });

    test('bonus ATK au total du porteur allié/propre', () {
      final MapService mapService = MapService();
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player sith = _player(
        Faction.sith,
        const Position(0, 0),
      ).copyWith(allies: <Ally>[scout]);

      expect(sith.totalAttack, 125 + 100,
          reason: 'porteur Sith (allié de l Empire) : +100 ATK');
      expect(sith.nukerAttackBonus, 100);
      expect(planet, isNotNull);
    });

    test('recrutement ennemi : malus de PV (Vador recrute Scout Trooper)', () {
      // Vador est Sith : Scout Trooper est Empire (faction ennemie) → -100 PV.
      Planet planet =
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player vador = _player(Faction.rebel, const Position(0, 0));
      final Position target = MapService()
          .validMoveTargets(
              planet: planet, players: <Player>[vador], activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      tiles[target.y * planet.width + target.x] =
          tiles[target.y * planet.width + target.x].copyWith(ally: scout);
      planet = planet.withTiles(tiles);

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(planet, <Player>[vador]);

      final MoveResult result =
          controller.moveActivePlayerTo(target.x, target.y);
      expect(result, MoveResult.allyEncounter);

      controller.recruitPendingAlly();
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.allies, isEmpty,
          reason: 'un allié de faction ennemie ne rejoint pas l équipe — '
              'il attaque à la place');
      expect(after.activePlayer.hp, 150,
          reason: 'malus ennemi de -100 PV, tempere par le niveau (N1 : x 0,5 - retours playtest)');
      expect(after.activePlayer.nukerAttackBonus, 0,
          reason: 'aucun bonus ATK pour un porteur ennemi');
    });
  });

  group('Combat — riposte par attaque et fuite (Sprint 4.1)', () {
    test('le monstre riposte après chaque attaque non létale', () {
      final Planet planet =
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(Faction.jedi, const Position(0, 0));
      final Position target = MapService()
          .validMoveTargets(
              planet: planet, players: <Player>[player], activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      tiles[target.y * planet.width + target.x] =
          tiles[target.y * planet.width + target.x]
              .copyWith(monster: Monster.forCard('Wampa', 3)); // 20 ATK, 500 PV
      final Planet crafted = planet.withTiles(tiles);

      final ProviderContainer container = _container(11);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(crafted, <Player>[player]);

      controller.moveActivePlayerTo(target.x, target.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startMonsterCombat(target);

      combat.attack();
      CombatSession session = container.read(combatControllerProvider)!;
      expect(session.playerHp, lessThan(200),
          reason: 'le monstre a riposté (dégâts par attaque — Sprint 4.1)');
      expect(session.playerHp,
          inInclusiveRange(200 - 20 - (20 / 2).ceil(), 200 - 10),
          reason: 'riposte de 20 PV (÷ 2 max avec tank, ici aucun)');
    });

    test('fuir en plein combat : dégâts conservés, pas d XP, monstre en place',
        () {
      final Planet planet =
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(Faction.jedi, const Position(0, 0));
      final Position target = MapService()
          .validMoveTargets(
              planet: planet, players: <Player>[player], activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      tiles[target.y * planet.width + target.x] =
          tiles[target.y * planet.width + target.x]
              .copyWith(monster: Monster.forCard('Wampa', 3));
      final Planet crafted = planet.withTiles(tiles);

      final ProviderContainer container = _container(23);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(crafted, <Player>[player]);

      controller.moveActivePlayerTo(target.x, target.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startMonsterCombat(target);

      combat.attack();
      combat.flee();
      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.finished, isTrue);
      expect(session.fled, isTrue);
      expect(session.victory, isFalse);
      expect(session.xpGained, 0);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.currentPlanet.tileAt(target.x, target.y).monster, isNotNull,
          reason: 'le monstre reste sur sa case');
      expect(after.activePlayer.eliminated, isFalse,
          reason: 'fuir ne tue pas : les dégâts subis sont conservés');
    });
  });

  group('Cartes Spéciales — personnages (Sprint 4.3)', () {
    test('spéciale ennemie : dégâts tempérés puis plafonnés, pas de recrutement', () {
      final Planet planet =
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally vador = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Dark Vador'); // Empire
      final Player leia = _player(Faction.rebel, const Position(0, 0));
      final Position target = MapService()
          .validMoveTargets(planet: planet, players: <Player>[leia],
              activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      tiles[target.y * planet.width + target.x] =
          tiles[target.y * planet.width + target.x].copyWith(ally: vador);
      final Planet crafted = planet.withTiles(tiles);

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(crafted, <Player>[leia]);

      final MoveResult result =
          controller.moveActivePlayerTo(target.x, target.y);
      expect(result, MoveResult.allyEncounter);
      expect(controller.pendingSpecialDamage, 120,
          reason: 'Vador (Empire) est ennemi du joueur Rebel : -500 de base, tempere au N1 (x 0,5) puis plafonne a 60 % des PV max (120)');

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.hp, 80,
          reason: 'plus de mort instantanee en une carte - retours playtest');
      expect(after.activePlayer.eliminated, isFalse);
      expect(after.activePlayer.allies, isEmpty,
          reason: 'la spéciale ennemie ne rejoint PAS l équipe');
      expect(after.currentPlanet.tileAt(target.x, target.y).ally, isNull,
          reason: 'la case est consommée');
    });

    test('spéciale alliée : recrutable normalement', () {
      final Planet planet =
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally luke = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Luke Skywalker'); // Jedi
      // Legendaire : recrutable a partir du niveau 5 (retours playtest).
      final Player leia =
          _player(Faction.rebel, const Position(0, 0)).copyWith(level: 5);
      final Position target = MapService()
          .validMoveTargets(planet: planet, players: <Player>[leia],
              activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      tiles[target.y * planet.width + target.x] =
          tiles[target.y * planet.width + target.x].copyWith(ally: luke);
      final Planet crafted = planet.withTiles(tiles);

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(crafted, <Player>[leia]);

      controller.moveActivePlayerTo(target.x, target.y);
      expect(controller.pendingSpecialDamage, isNull,
          reason: 'Luke (Jedi) est allié d un joueur Rebel');
      expect(controller.canRecruitPendingAlly(), isTrue,
          reason: 'coût 5 PP, équipe vide');

      controller.recruitPendingAlly();
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.allies.length, 1);
      expect(after.activePlayer.allies.first.name, 'Luke Skywalker');
      // Bonus de la Speciale amie desormais appliques (retours playtest) :
      // Luke (Jedi) est ami du porteur Rebel : +2000 ATK, +500 PV max.
      expect(after.activePlayer.specialAttackBonus, 2000);
      expect(after.activePlayer.specialHpBonus, 500);
      expect(after.activePlayer.totalAttack, 125 + 2000);
      expect(after.activePlayer.totalMaxHp, 200 + 500);
    });
  });
}
