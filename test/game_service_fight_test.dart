import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
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

Planet _planet() =>
    MapService().generateStartPlanet(PlanetType.coruscant, seed: 42);

Player _playerAt(Position position, {int hp = 200, int index = 0}) => Player(
      id: 'p${index + 1}',
      name: index == 0 ? 'Luke Skywalker' : 'Adversaire $index',
      faction: index == 0 ? Faction.jedi : Faction.sith,
      position: position,
      level: 1,
      xp: 0,
      attack: 125,
      hp: hp,
      maxHp: 200,
    );

/// État figé : joueur actif au start A, monstre posé sur un voisin
/// jouable, second joueur au coin opposé.
GameState _stateWith({
  required Planet planet,
  required Position monsterTile,
  required Monster monster,
  List<Player>? players,
  int activeIndex = 0,
}) {
  final List<Tile> tiles = List<Tile>.of(planet.tiles);
  if (monsterTile.x >= 0 && monsterTile.y >= 0) {
    final int index = monsterTile.y * planet.width + monsterTile.x;
    tiles[index] = tiles[index].copyWith(monster: monster);
  }
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'fight_test',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.coruscant,
    currentPlanet: planet.withTiles(tiles),
    players:
        players ?? <Player>[_playerAt(const Position(0, 0), index: 0)],
    turn: 1,
    currentPlayerIndex: activeIndex,
    gameTimeSeconds: 0,
    movementPointsRemaining: 3,
    lastDiceRoll: 3,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
}

void main() {
  late ProviderContainer container;
  late MapService mapService;

  setUp(() {
    container = _container(5);
    mapService = MapService();
  });

  tearDown(() => container.dispose());

  GameController controller(ProviderContainer c) =>
      c.read(gameControllerProvider.notifier);

  test('entrer sur une case à monstre déclenche une rencontre (GDD §10)',
      () {
    final Planet planet = _planet();
    final Player player = _playerAt(const Position(0, 0));
    final Position target =
        mapService.validMoveTargets(planet: planet, players: [player], activePlayerIndex: 0).first;
    final GameState state = _stateWith(
      planet: planet,
      monsterTile: target,
      monster: Monster.forCard('Wampa', 3),
      players: [player],
    );

    controller(container).state = state;
    final MoveResult result =
        controller(container).moveActivePlayerTo(target.x, target.y);

    expect(result, MoveResult.monsterEncounter);
    final GameState after = container.read(gameControllerProvider)!;
    expect(after.activePlayer.position, target,
        reason: 'le pion entre dans la case même en cas de rencontre');
    expect(after.currentPlanet.tileAt(target.x, target.y).monster, isNotNull,
        reason: 'fuir laisse le monstre en place');
    expect(after.movementPointsRemaining, 2);
  });

  test('victoire : monstre retiré, +XP, dégâts = ATK × attaques (GDD §11)',
      () {
    final Planet planet = _planet();
    final Player player = _playerAt(const Position(0, 0));
    final Position target =
        mapService.validMoveTargets(planet: planet, players: [player], activePlayerIndex: 0).first;
    final Monster wampa = Monster.forCard('Wampa', 3); // 20 ATK, 500 PV, 50 XP
    controller(container).state =
        _stateWith(planet: planet, monsterTile: target, monster: wampa, players: [player]);

    controller(container).moveActivePlayerTo(target.x, target.y);
    final CombatController combat =
        container.read(combatControllerProvider.notifier);
    combat.startMonsterCombat(target);

    int guard = 0;
    while (!(container.read(combatControllerProvider)?.finished ?? false)) {
      combat.attack();
      guard++;
      expect(guard, lessThan(50), reason: 'le combat doit se terminer');
    }

    final CombatSession session = container.read(combatControllerProvider)!;
    expect(session.victory, isTrue);
    expect(session.xpGained, 50);
    expect(session.attacksUsed, greaterThanOrEqualTo(4),
        reason: '500 PV / 250 max par coup critique');

    final GameState after = container.read(gameControllerProvider)!;
    expect(after.currentPlanet.tileAt(target.x, target.y).monster, isNull,
        reason: 'la carte du monstre est retirée');
    expect(after.activePlayer.xp, 50);
    // Sprint 4.1 : riposte du monstre après CHAQUE attaque non létale
    // (20 PV par round, sans tank dans l'équipe).
    final int ripostePerAttack = GameConstants.scaleIncomingDamage(
      wampa.attack,
      level: 1,
      maxHp: 200,
    ); // x 0,5 au niveau 1 (retours playtest).
    expect(session.damageTaken, ripostePerAttack * (session.attacksUsed - 1));
    expect(
      after.activePlayer.hp,
      200 - session.damageTaken,
      reason: 'dégâts subis sans montée de niveau (50 XP < 200)',
    );
    expect(after.activePlayer.eliminated, isFalse);
  });

  test('un joueur peut être éliminé par un monstre (0 PV)', () {
    final Planet planet = _planet();
    // PV très bas : 3 ripostes de 25 (50 ATK x 0,5 au N1) suffisent, alors
    // que le monstre exige au moins 4 attaques (1000 PV) — élimination
    // déterministe malgré la protection de niveau (retours playtest).
    final Player player = _playerAt(const Position(0, 0), hp: 60);
    final Position target =
        mapService.validMoveTargets(planet: planet, players: [player], activePlayerIndex: 0).first;
    final Monster sarlacc = Monster.forCard('Sarlacc', 5); // 50 ATK, 1000 PV
    controller(container).state =
        _stateWith(planet: planet, monsterTile: target, monster: sarlacc, players: [player]);

    controller(container).moveActivePlayerTo(target.x, target.y);
    final CombatController combat =
        container.read(combatControllerProvider.notifier);
    combat.startMonsterCombat(target);
    while (!(container.read(combatControllerProvider)?.finished ?? false)) {
      combat.attack();
    }

    final CombatSession session = container.read(combatControllerProvider)!;
    // 3 ripostes de 25 PV > 60 PV de départ ; le monstre (1000 PV) exige
    // au moins 4 attaques : l'élimination est certaine avant la victoire.
    expect(session.playerEliminated, isTrue);
    expect(container.read(gameControllerProvider)!.activePlayer.eliminated,
        isTrue);
  });

  group('Combat entre joueurs (GDD §13)', () {
    test('élimination à 0 PV : +500 XP à l attaquant', () {
      final Planet planet = _planet();
      final Player attacker = _playerAt(const Position(0, 0));
      final Position defenderTile =
          mapService.validMoveTargets(planet: planet, players: [attacker], activePlayerIndex: 0).first;
      final Player defender = _playerAt(defenderTile, hp: 100, index: 1);
      controller(container).state = _stateWith(
        planet: planet,
        monsterTile: const Position(-1, -1),
        monster: Monster.forCard('Ewoks', 1),
        players: [attacker, defender],
      );

      controller(container).moveActivePlayerTo(defenderTile.x, defenderTile.y);
      expect(container.read(gameControllerProvider)!.activePlayer.position,
          defenderTile, reason: 'les deux pions coexistent sur la case');

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startPlayerCombat(1);
      combat.attack();

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.finished, isTrue);
      expect(session.targetEliminated, isTrue);
      expect(session.xpGained, GameConstants.playerKillXpReward);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[1].eliminated, isTrue);
      expect(after.players[1].hp, 0);
      expect(after.players[0].xp, 500);
      expect(after.players[0].level, 3, reason: '500 XP → paliers 200 et 400');
    });

    test('le défenseur peut survivre à l échange', () {
      final Planet planet = _planet();
      final Player attacker = _playerAt(const Position(0, 0));
      final Position defenderTile =
          mapService.validMoveTargets(planet: planet, players: [attacker], activePlayerIndex: 0).first;
      final Player defender = _playerAt(defenderTile, hp: 500, index: 1);
      controller(container).state = _stateWith(
        planet: planet,
        monsterTile: const Position(-1, -1),
        monster: Monster.forCard('Ewoks', 1),
        players: [attacker, defender],
      );

      controller(container).moveActivePlayerTo(defenderTile.x, defenderTile.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startPlayerCombat(1);
      combat.attack();

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[1].eliminated, isFalse);
      expect(after.players[1].hp, inInclusiveRange(250, 499),
          reason: '125 à 250 dégâts (critique) sur 500 PV');
      expect(after.players[0].xp, 0, reason: 'pas de prime sans élimination');
    });

    test('endTurn saute les joueurs éliminés', () async {
      final Planet planet = _planet();
      final Player p0 = _playerAt(BoardConstants.startPositions[0], index: 0);
      final Player p1 = _playerAt(BoardConstants.startPositions[2], index: 1)
          .copyWith(eliminated: true);
      final Player p2 = _playerAt(BoardConstants.startPositions[1], index: 2);
      controller(container).state = _stateWith(
        planet: planet,
        monsterTile: const Position(-1, -1),
        monster: Monster.forCard('Ewoks', 1),
        players: [p0, p1, p2],
      );

      await controller(container).endTurn();
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.currentPlayerIndex, 2,
          reason: 'le joueur 1 éliminé est sauté');
      expect(after.turn, 1);
    });
  });
}
