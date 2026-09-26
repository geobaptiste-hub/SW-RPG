import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/core/constants/planet_constants.dart'
    show PlanetConstants;
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/armor.dart';
import 'package:star_wars_rpg/models/boss.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/portal.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/models/weapon.dart';
import 'package:star_wars_rpg/screens/game_over/game_over_screen.dart'
    show GameOverScreen, WinnerResolution;
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';
import 'package:star_wars_rpg/widgets/card_image.dart'
    show planetAmbienceTrack, planetImageId;

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

/// Enregistreur : capture le dernier état sauvegardé (test « sauver et
/// quitter » en pleine partie).
class _RecordingSaveService extends SaveService {
  GameState? lastSaved;

  @override
  Future<bool> hasSave() async => false;

  @override
  Future<void> save(GameState state) async {
    lastSaved = state;
  }

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

Ally _support(String name) => CardConstants.supports
    .firstWhere((Ally a) => a.name == name);

Player _player({
  Position position = const Position(0, 0),
  Faction faction = Faction.rebel,
  int level = 1,
  int hp = 200,
  int maxHp = 200,
  List<Ally> allies = const [],
}) {
  final int lvl = level.clamp(1, 6);
  return Player(
    id: 'p1',
    name: 'Testeur',
    faction: faction,
    position: position,
    level: lvl,
    xp: 0,
    attack: GameConstants.attackForLevel(lvl),
    hp: hp,
    maxHp: maxHp,
    allies: allies,
  );
}

Player _opponent({
  Position position = const Position(1, 0),
  Faction faction = Faction.sith,
  int level = 3,
  int hp = 2000,
}) {
  final int lvl = level.clamp(1, 6);
  return Player(
    id: 'p2',
    name: 'Adversaire',
    faction: faction,
    position: position,
    level: lvl,
    xp: 0,
    attack: GameConstants.attackForLevel(lvl),
    hp: hp,
    maxHp: hp,
  );
}

GameState _duelState(Planet planet, List<Player> players,
    {int movement = 3}) {
  // movement 0 = dé pas encore lancé (sinon le state porte un lancer).
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'playtest2',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.hoth,
    currentPlanet: planet,
    players: players,
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: movement,
    lastDiceRoll: movement == 0 ? null : movement,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
}

void main() {
  group('Soutien critOn5 (Ki-Adi-Mundi, C-3PO…)', () {
    test('le 5 devient un critique', () {
      expect(CombatService.isCritical(5), isFalse);
      expect(CombatService.isCritical(5, critOn5: true), isTrue);
      expect(CombatService.isCritical(6, critOn5: false), isTrue);
      expect(
        CombatService.attackDamage(attackTotal: 450, roll: 5, critOn5: true),
        900,
      );
    });
  });

  group('Soutien doubleMoveDice (Luminara Unduli…)', () {
    test('les points de déplacement valent le double du dé', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[_player(allies: <Ally>[_support('Luminara Unduli')])],
        movement: 0,
      );

      controller.rollDice();
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.lastDiceRoll, inInclusiveRange(1, 6));
      expect(after.movementPointsRemaining, after.lastDiceRoll! * 2,
          reason: 'le dé est affiché brut, les points sont doublés');
    });
  });

  group('Soutien bonusXp20 (Jocasta Nu…)', () {
    test('+20 XP après une victoire contre un monstre', () {
      final ProviderContainer container = _container(9);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(
        level: 6,
        hp: 10000,
        maxHp: 10000,
        allies: <Ally>[_support('Jocasta Nu')],
      );
      final Position target = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[player], activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      final int index = target.y * planet.width + target.x;
      tiles[index] = tiles[index].copyWith(
          monster: Monster.forCard('Wampa', 1)); // 10 XP
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet.withTiles(tiles), <Player>[player]);

      controller.moveActivePlayerTo(target.x, target.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startMonsterCombat(target);
      int guard = 0;
      while (!(container.read(combatControllerProvider)?.finished ?? false)) {
        combat.attack();
        guard++;
        expect(guard, lessThan(30));
      }
      expect(container.read(gameControllerProvider)!.activePlayer.xp, 10 + 20,
          reason: '10 XP du monstre + 20 du soutien');
    });
  });

  group('Soutien attackTimesDice (Yaddle…) — usage unique', () {
    test('dégâts = ATK x dé, carte consommée', () {
      final ProviderContainer container = _container(7);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(
        level: 6,
        hp: 10000,
        maxHp: 10000,
        allies: <Ally>[_support('Yaddle')],
      );
      final Position target = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[player], activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      final int index = target.y * planet.width + target.x;
      tiles[index] = tiles[index]
          .copyWith(monster: Monster.forCard('Wampa', 1));
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet.withTiles(tiles), <Player>[player]);

      controller.moveActivePlayerTo(target.x, target.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startMonsterCombat(target);
      final int atk = container.read(gameControllerProvider)!
          .activePlayer.totalAttack;
      combat.attack(useAttackTimesDice: true);

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.attackTimesDiceUsed, isTrue);
      expect(session.lastDamage, atk * session.lastRoll!,
          reason: 'ATK multipliée par la face du dé');
      expect(container.read(gameControllerProvider)!.activePlayer.hasAttackTimesDice,
          isFalse, reason: 'la carte est consommée');
    });
  });

  group('Soutien preventDeath (Adi Gallia…) — usage unique', () {
    test('combat de boss : survit à 1 PV une fois, puis éliminé', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Player player = _player(allies: <Ally>[_support('Adi Gallia')]);
      final GameState state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest2',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.mustafar,
        currentPlanet: mapService.generateSecondaryPlanet(
            PlanetType.mustafar, seed: 7),
        players: <Player>[player],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: <Boss>[
          Boss(
            name: 'Exogorth',
            type: BossType.exogorth,
            planet: PlanetType.mustafar,
            hp: GameConstants.bossHp,
            attackMin: GameConstants.bossAttackMin,
            attackMax: GameConstants.bossAttackMax,
            position: const Position(3, 4),
          ),
        ],
        portals: const [],
        status: GameStatus.inProgress,
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startBossCombat(state.bosses.first);

      // Riposte du boss au N1 : toujours 120 (plafond 60 % de 200 PV).
      combat.attack();
      expect(container.read(combatControllerProvider)!.playerHp, 80);
      combat.attack(); // 80 - 120 → mort empêchée.
      CombatSession session = container.read(combatControllerProvider)!;
      expect(session.deathPrevented, isTrue);
      expect(session.playerHp, 1);
      expect(session.playerEliminated, isFalse);
      expect(container.read(gameControllerProvider)!.activePlayer.allies,
          isEmpty, reason: 'la carte est consommée');

      combat.attack(); // plus de carte : éliminé.
      session = container.read(combatControllerProvider)!;
      expect(session.playerEliminated, isTrue);
      expect(session.deathPrevented, isTrue,
          reason: 'le flag du premier sauvetage reste affiché');
    });

    test('carte ennemie létale : survit à 1 PV', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally vador = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Dark Vador');
      final Player player = _player(hp: 100, allies: <Ally>[
        _support('Adi Gallia'),
      ]);
      final Position target = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[player], activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      final int index = target.y * planet.width + target.x;
      tiles[index] = tiles[index].copyWith(ally: vador);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet.withTiles(tiles), <Player>[player]);

      controller.moveActivePlayerTo(target.x, target.y);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.hp, 1);
      expect(after.activePlayer.eliminated, isFalse);
      expect(after.activePlayer.allies, isEmpty);
    });
  });

  group('JvJ : riposte du défenseur (GDD §13 — fix playtest)', () {
    test('l attaquant subit l ATK du défenseur (sans critique)', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player attacker = _player(level: 3, hp: 1000, maxHp: 1000);
      final Position defenderTile = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[attacker],
              activePlayerIndex: 0)
          .first;
      final Player defender = _opponent(position: defenderTile, hp: 2000);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state =
          _duelState(planet, <Player>[attacker, defender]);

      controller.moveActivePlayerTo(defenderTile.x, defenderTile.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startPlayerCombat(1);
      combat.attack();

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.finished, isTrue);
      expect(session.targetEliminated, isFalse);
      expect(session.damageTaken, defender.totalAttack,
          reason: 'l attaquant subit la riposte du défenseur');
      expect(session.playerHp, 1000 - defender.totalAttack);
    });

    test('défenseur éliminé : pas de riposte, +500 XP à l attaquant', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player attacker = _player(level: 6, hp: 1000, maxHp: 1000);
      final Position defenderTile = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[attacker],
              activePlayerIndex: 0)
          .first;
      final Player defender = _opponent(position: defenderTile, hp: 100);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet, <Player>[attacker, defender]);

      controller.moveActivePlayerTo(defenderTile.x, defenderTile.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startPlayerCombat(1);
      combat.attack();

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.targetEliminated, isTrue);
      expect(session.xpGained, GameConstants.playerKillXpReward);
      expect(session.damageTaken, 0,
          reason: 'un défenseur éliminé ne riposte pas');
      expect(session.playerHp, 1000,
          reason: 'l attaquant sort indemne');
    });

    test('attaquant éliminé par la riposte : +500 XP au défenseur', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player attacker = _player(level: 6, hp: 100, maxHp: 1000);
      final Position defenderTile = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[attacker],
              activePlayerIndex: 0)
          .first;
      final Player defender = _opponent(position: defenderTile, hp: 5000);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet, <Player>[attacker, defender]);

      controller.moveActivePlayerTo(defenderTile.x, defenderTile.y);
      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startPlayerCombat(1);
      combat.attack();

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.playerEliminated, isTrue);
      expect(session.victory, isFalse);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[1].xp, GameConstants.playerKillXpReward,
          reason: 'le défenseur touche la prime de chasseur');
      expect(after.players[0].eliminated, isTrue);
    });
  });

  group('Doublons d alliés (playtest : deux Poe Dameron)', () {
    test('recruter une carte déjà en équipe est refusé (hors escouades)',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally poe = CardConstants.nukers
          .firstWhere((Ally a) => a.name == 'Poe Dameron');
      final Player player = _player(level: 3, allies: <Ally>[poe]);
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[player],
        movement: 0,
      );

      controller.pendingAllyOffer = poe;
      controller.recruitPendingAlly();
      expect(container.read(gameControllerProvider)!.activePlayer.allies
          .where((Ally a) => a.name == 'Poe Dameron')
          .length, 1, reason: 'pas de doublon');
    });

    test('les escouades restent cumulables', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally ewok =
          CardConstants.squads.firstWhere((Ally a) => a.name == 'Ewok');
      final Player player = _player(level: 3, allies: <Ally>[ewok]);
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[player],
        movement: 0,
      );

      controller.pendingAllyOffer = ewok;
      controller.recruitPendingAlly();
      expect(container.read(gameControllerProvider)!.activePlayer.allies
          .where((Ally a) => a.name == 'Ewok')
          .length, 2, reason: 'formule cumulative des escouades');
    });
  });

  group('Équipement : plus de doublon équipé/réserve', () {
    test('équiper la réserve sans arme équipée VIDE la réserve', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Weapon arme = CardConstants.weapons.firstWhere(
          (Weapon w) =>
              w.rarity == Rarity.commun);
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[_player(level: 3).copyWith(storedWeapon: arme)],
        movement: 0,
      );

      expect(controller.equipStoredWeapon(), isTrue);
      final Player after = container.read(gameControllerProvider)!.activePlayer;
      expect(after.weapon?.id, arme.id);
      expect(after.storedWeapon, isNull,
          reason: 'la réserve ne doit PAS garder une copie (doublon)');
    });

    test('ranger l arme équipée en réserve (et refus si réserve occupée)',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Weapon a = CardConstants.weapons[0];
      final Weapon b = CardConstants.weapons[1];
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[_player(level: 6).copyWith(weapon: a)],
        movement: 0,
      );

      expect(controller.storeEquippedWeapon(), isTrue);
      Player after = container.read(gameControllerProvider)!.activePlayer;
      expect(after.weapon, isNull);
      expect(after.storedWeapon?.id, a.id);

      // Réserve occupée : ranger une autre arme est refusé.
      controller.state = container.read(gameControllerProvider)!.copyWith(
        players: <Player>[
          container.read(gameControllerProvider)!.activePlayer.copyWith(
                weapon: b,
              ),
        ],
      );
      expect(controller.storeEquippedWeapon(), isFalse);
    });
  });

  group('Équipe ↔ réserve d allié : échange', () {
    test('storeTeamAlly échange avec l allié stocké si les places suffisent',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally ewok =
          CardConstants.squads.firstWhere((Ally a) => a.name == 'Ewok');
      final Ally mace = CardConstants.tanks
          .firstWhere((Ally a) => a.name == 'Mace Windu');
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[
          _player(
            level: 6,
            allies: <Ally>[ewok, _support('Jocasta Nu')],
            hp: 2000,
            maxHp: 2000,
          ),
        ],
        movement: 0,
      );
      // Mace Windu en réserve.
      container.read(gameControllerProvider.notifier).state =
          container.read(gameControllerProvider)!.copyWith(
        players: <Player>[
          container.read(gameControllerProvider)!.activePlayer.copyWith(
                storedAlly: mace,
              ),
        ],
      );

      expect(controller.storeTeamAlly(0), isTrue);
      final Player after = container.read(gameControllerProvider)!.activePlayer;
      expect(after.storedAlly?.name, 'Ewok',
          reason: 'l Ewok parti de l équipe occupe la réserve');
      expect(after.allies.map((Ally a) => a.name), contains('Mace Windu'));
    });

    test('refus si les places ne suffisent pas pour l échange', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally expensive = CardConstants.specials.first; // 5 places
      final Ally cheap =
          CardConstants.squads.firstWhere((Ally a) => a.name == 'Ewok');
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[
          // Équipe pleine : 10 places d'Ewoks (escouades cumulables).
          _player(
            level: 6,
            allies: List<Ally>.filled(10, cheap),
            hp: 2000,
            maxHp: 2000,
          ).copyWith(storedAlly: expensive),
        ],
        movement: 0,
      );

      // Après libération d'un Ewok (1 place) : 9 + 5 > 10 → refus.
      expect(controller.storeTeamAlly(0), isFalse);
    });
  });

  group('Boss rebattable (fix réapparition — retours playtest v3)', () {
    test('sur une planète entièrement découverte, le boss réapparaît et le '
        '2e joueur le bat pour 300 XP (rang 2)', () async {
      final ProviderContainer container = _container(11);
      addTearDown(container.dispose);
      final Planet mustafar =
          mapService.generateSecondaryPlanet(PlanetType.mustafar, seed: 7);
      // Planète ENTIÈREMENT découverte : l'ancien code laissait le boss
      // fugué pour toujours (aucune case non découverte disponible).
      final Planet revealed =
          mapService.revealFogAround(mustafar, const Position(3, 3), radius: 30);
      final Player p1 = _player(
        faction: Faction.jedi,
        level: 6,
        hp: 10000,
        maxHp: 10000,
        position: const Position(3, 3),
      ).copyWith(planet: PlanetType.mustafar);
      final Position p2Pos = revealed.tiles
          .map((Tile t) => Position(t.x, t.y))
          .where((Position p) =>
              revealed.isWalkableAt(p.x, p.y) && p != const Position(3, 3))
          .first;
      final Player p2 = _player(
        faction: Faction.sith,
        level: 6,
        hp: 10000,
        maxHp: 10000,
        position: p2Pos,
      ).copyWith(planet: PlanetType.mustafar);
      final Position bossPos = revealed.tiles
          .map((Tile t) => Position(t.x, t.y))
          .where((Position p) =>
              revealed.isWalkableAt(p.x, p.y) &&
              p != const Position(3, 3) &&
              p != p2Pos)
          .first;
      final GameState state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest2',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.mustafar,
        currentPlanet: revealed,
        planets: <PlanetType, Planet>{PlanetType.mustafar: revealed},
        players: <Player>[p1, p2],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: <Boss>[
          Boss(
            name: 'Exogorth',
            type: BossType.exogorth,
            planet: PlanetType.mustafar,
            hp: GameConstants.bossHp,
            attackMin: GameConstants.bossAttackMin,
            attackMax: GameConstants.bossAttackMax,
            position: bossPos,
          ),
        ],
        portals: const [],
        status: GameStatus.inProgress,
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;
      final CombatController combat =
          container.read(combatControllerProvider.notifier);

      // Victoire 1 : XP de rang 1 = 400, le boss prend la fuite.
      combat.startBossCombat(state.bosses.first);
      int guard = 0;
      while (!(container.read(combatControllerProvider)?.finished ?? false)) {
        combat.attack();
        guard++;
        expect(guard, lessThan(20));
      }
      CombatSession session = container.read(combatControllerProvider)!;
      expect(session.victory, isTrue);
      expect(session.xpGained, GameConstants.bossXpRewards[0]);
      expect(container.read(gameControllerProvider)!.bosses.first.isGone,
          isTrue);

      // Fin de tour : le boss RÉAPPARAÎT malgré la planète découverte.
      await controller.endTurn();
      final GameState afterTurn = container.read(gameControllerProvider)!;
      expect(afterTurn.bosses.first.isGone, isFalse,
          reason: 'le boss est rebattable par les autres joueurs');
      expect(
        afterTurn.currentPlanet
            .tileAt(
                afterTurn.bosses.first.position.x,
                afterTurn.bosses.first.position.y)
            .walkable,
        isTrue,
      );

      // Victoire 2 (joueur 2) : XP de rang 2 = 300.
      combat.startBossCombat(afterTurn.bosses.first);
      guard = 0;
      while (!(container.read(combatControllerProvider)?.finished ?? false)) {
        combat.attack();
        guard++;
        expect(guard, lessThan(20));
      }
      session = container.read(combatControllerProvider)!;
      expect(session.victory, isTrue);
      expect(session.xpGained, GameConstants.bossXpRewards[1],
          reason: '2e vainqueur du boss : 300 XP (table de rang)');
    });
  });

  group('Niveau requis par rareté (retours playtest v3)', () {
    test('minLevelForRarity : table Commun 1 → Mythique 6', () {
      expect(GameConstants.minLevelForRarity(Rarity.commun.index), 1);
      expect(GameConstants.minLevelForRarity(Rarity.rare.index), 3);
      expect(GameConstants.minLevelForRarity(Rarity.epique.index), 4);
      expect(GameConstants.minLevelForRarity(Rarity.legendaire.index), 5);
      expect(GameConstants.minLevelForRarity(Rarity.mythique.index), 6);
    });
  });

  group('Cases consommées : la carte se redépose ailleurs', () {
    test('après ramassage, l\'arme existe toujours sur la planète', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(level: 6, hp: 2000, maxHp: 2000)
          .copyWith(planet: PlanetType.hoth);
      final Weapon weapon = CardConstants.weapons
          .firstWhere((Weapon w) => w.rarity == Rarity.commun);
      final Position target = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[player],
              activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      final int index = target.y * planet.width + target.x;
      tiles[index] = tiles[index].copyWith(weapon: weapon);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(
        planet.withTiles(tiles),
        <Player>[player],
      );

      final int weaponsBefore = planet.withTiles(tiles).tiles
          .where((Tile t) => t.weapon != null)
          .length;
      expect(weaponsBefore, 1);

      final MoveResult result =
          controller.moveActivePlayerTo(target.x, target.y);
      expect(result, MoveResult.itemEncounter);
      controller.equipPendingWeapon();

      final Planet after =
          container.read(gameControllerProvider)!.currentPlanet;
      expect(
        after.tileAt(target.x, target.y).weapon,
        isNull,
        reason: 'la case d\'origine est bien vidée (pas de farm)',
      );
      expect(
        after.tiles.where((Tile t) => t.weapon != null).length,
        greaterThanOrEqualTo(1),
        reason: 'la carte consommée a été redéposée ailleurs au hasard '
            '(le populate peut en avoir posé d\'autres sur les nouvelles '
            'découvertes)',
      );

      // FIX synchronisation : après endTurn, la planète restaurée depuis
      // planets[type] ne doit PAS faire réapparaître la carte consommée.
      await controller.endTurn();
      final GameState afterTurn = container.read(gameControllerProvider)!;
      final Planet restored = afterTurn.planets[PlanetType.hoth]!;
      expect(
        restored.tileAt(target.x, target.y).weapon,
        isNull,
        reason: 'la carte consommée ne doit pas réapparaître au tour '
            'suivant (c\'était le bug « toujours la même carte »)',
      );
    });
  });

  group('Les 4 portails garantis dès le N3 (retours playtest)', () {
    test('le premier endTurn en phase milieu pose les 4, sous le brouillard, '
        'vers des destinations différentes', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(level: 3, hp: 2000, maxHp: 2000)
          .copyWith(planet: PlanetType.hoth);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet, <Player>[player], movement: 0);

      await controller.endTurn();

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.portals.length, 4,
          reason: 'dès le premier joueur N3, les 4 portails sont posés '
              'd\'un coup (retours playtest)');
      final Player active = after.activePlayer;
      final int sight = GameConstants.fogVisibleRadius;
      for (final Portal portal in after.portals) {
        expect(portal.discovered, isTrue,
            reason: 'le portail existe et est fonctionnel : le voyage se '
                'déclenche dès qu\'un joueur marche dessus');
        // Fix 19/09 : la pose NE RÉVÈLE PAS la case — le portail reste sous
        // le brouillard de guerre et ne s'affiche qu'à l'approche d'un
        // joueur (zone visible). Exception : un portail tiré DANS le rayon
        // de révélation du début de tour est vu légitimement.
        final Tile tile = after.currentPlanet
            .tileAt(portal.position.x, portal.position.y);
        if (portal.position.chebyshevDistanceTo(active.position) > sight) {
          expect(tile.discovered, isFalse,
              reason: 'la pose d\'un portail ne doit pas révéler sa case');
          expect(tile.visible, isFalse,
              reason: 'le portail ne doit pas être visible sous le brouillard');
        } else {
          expect(tile.visible, isTrue,
              reason: 'un portail apparu dans la zone de vue du joueur est '
                  'révélé par la révélation de début de tour, pas par la pose');
        }
        // Chaque portail mène à une planète secondaire différente, déjà
        // générée.
        expect(after.planets.containsKey(portal.destination), isTrue);
      }
      expect(
        after.portals.map((Portal p) => p.destination).toSet().length,
        4,
        reason: 'une destination différente par portail',
      );
    });

    test('aucun portail tant que personne n\'est N3 (phase début)', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(level: 1, hp: 2000, maxHp: 2000)
          .copyWith(planet: PlanetType.hoth);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet, <Player>[player], movement: 0);

      await controller.endTurn();

      expect(container.read(gameControllerProvider)!.portals, isEmpty,
          reason: 'les portails n\'apparaissent qu\'à partir du niveau 3 '
              '(GDD §5)');
    });

    test('marcher sur un portail pas encore vu déclenche quand même le '
        'voyage (le portail existe sous le brouillard)', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(level: 3, hp: 2000, maxHp: 2000)
          .copyWith(planet: PlanetType.hoth);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet, <Player>[player], movement: 0);

      await controller.endTurn();

      final GameState after = container.read(gameControllerProvider)!;
      // Un portail posé hors de la zone visible : sa case est masquée.
      final Portal portal = after.portals.firstWhere((Portal p) =>
          !after.currentPlanet.tileAt(p.position.x, p.position.y).visible);
      expect(
        after.currentPlanet.tileAt(portal.position.x, portal.position.y),
        isA<Tile>().having((Tile t) => t.discovered, 'discovered', isFalse),
      );
      // Le joueur est téléporté à côté, puis marche dessus sans l'avoir
      // jamais vu : le voyage doit se déclencher (case voisine = entrable,
      // le portail est fonctionnel même non vu).
      final Planet main = after.currentPlanet;
      final Position from = mapService
          .neighborPositions(portal.position, main)
          .firstWhere((Position p) => main.isWalkableAt(p.x, p.y));
      controller.state = after.copyWith(
        players: <Player>[after.activePlayer.copyWith(position: from)],
        movementPointsRemaining: 1,
        lastDiceRoll: 1,
      );

      final MoveResult result = controller.moveActivePlayerTo(
          portal.position.x, portal.position.y);

      expect(result, MoveResult.portalTravel);
      final GameState traveled = container.read(gameControllerProvider)!;
      expect(traveled.activePlayer.planet, portal.destination);
      expect(traveled.activePlayer.position,
          PlanetConstants.secondaryPortalPosition);
      // Le portail central de retour est révélé à l'arrivée (il s'affiche).
      expect(
        traveled.currentPlanet
            .tileAt(
                PlanetConstants.secondaryPortalPosition.x,
                PlanetConstants.secondaryPortalPosition.y)
            .visible,
        isTrue,
      );
    });
  });

  group('JvJ : la case d\'un coéquipier n\'est pas entrable', () {
    test('validMoveTargets exclut les coéquipiers, pas les ennemis', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player hero = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: const Position(0, 0),
      ).copyWith(team: TeamSide.teamA);
      final Player ally = _player(
        faction: Faction.jedi,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: const Position(1, 0),
      ).copyWith(team: TeamSide.teamA, planet: PlanetType.hoth);
      final Player enemy = _player(
        faction: Faction.sith,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: const Position(0, 1),
      ).copyWith(team: TeamSide.teamB, planet: PlanetType.hoth);

      final List<Position> targets = mapService.validMoveTargets(
        planet: planet,
        players: <Player>[hero, ally, enemy],
        activePlayerIndex: 0,
      );

      expect(targets, contains(const Position(0, 1)),
          reason: 'la case d\'un ENNEMI reste attaquable (GDD §13)');
      expect(targets, isNot(contains(const Position(1, 0))),
          reason: 'impossible d\'entrer sur la case d\'un coéquipier '
              '(retours playtest)');
    });

    test('FIX 19/09 : un coéquipier sur une AUTRE planète ne bloque pas '
        'la case de mêmes coordonnées', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player hero = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: const Position(0, 0),
      ).copyWith(team: TeamSide.teamA);
      // Coéquipier sur DAGOBAH, aux coordonnées d'un voisin du héros.
      final Position neighbor = mapService
          .neighborPositions(const Position(0, 0), planet)
          .firstWhere((Position p) => planet.isWalkableAt(p.x, p.y));
      final Player teammateElsewhere = _player(
        faction: Faction.jedi,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: neighbor,
      ).copyWith(
        team: TeamSide.teamA,
        planet: PlanetType.dagobah,
      );

      final List<Position> targets = mapService.validMoveTargets(
        planet: planet,
        players: <Player>[hero, teammateElsewhere],
        activePlayerIndex: 0,
      );

      expect(targets, contains(neighbor),
          reason: 'sans le fix, un pion sur une autre planète aux mêmes '
              'coordonnées bloquait la case de façon fantôme');

      // Le même coéquipier SUR la planète bloque toujours.
      final Player teammateHere = teammateElsewhere.copyWith(
        planet: PlanetType.hoth,
      );
      final List<Position> targetsHere = mapService.validMoveTargets(
        planet: planet,
        players: <Player>[hero, teammateHere],
        activePlayerIndex: 0,
      );
      expect(targetsHere, isNot(contains(neighbor)));
    });
  });

  group('Les PV suivent la tenue équipée (retours playtest 19/09)', () {
    test('équiper une tenue +100 à 200/200 donne 300/300', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Player player = _player(hp: 200, maxHp: 200);
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[player],
        movement: 0,
      );
      controller.pendingArmorOffer = const Armor(
        id: 'tenue_test',
        name: 'Tenue test',
        rarity: Rarity.commun,
        hpBonus: 100,
      );

      expect(controller.equipPendingArmor(), isTrue);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.armor!.hpBonus, 100);
      expect(after.activePlayer.totalMaxHp, 300);
      expect(after.activePlayer.hp, 300,
          reason: 'les PV actuels montent avec le maximum '
              '(et non 200/300)');
    });

    test('échanger vers une plus faible n\'enlève pas de PV', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      const Armor forte = Armor(
        id: 'forte',
        name: 'Forte',
        rarity: Rarity.commun,
        hpBonus: 200,
      );
      const Armor faible = Armor(
        id: 'faible',
        name: 'Faible',
        rarity: Rarity.commun,
        hpBonus: 50,
      );
      final Player player = _player(hp: 150, maxHp: 200).copyWith(
        armor: forte,
      );
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[player],
        movement: 0,
      );
      controller.pendingArmorOffer = faible;

      expect(controller.equipPendingArmor(), isTrue);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.totalMaxHp, 250);
      expect(after.activePlayer.hp, 150,
          reason: 'rétrograder de tenue ne retire jamais de PV '
              '(les PV restants sont conservés)');
    });
  });

  group('Équipement : 3e objet, la réserve est préservée si demandé', () {
    test('discardReplaced défausse l\'équipée et garde la réserve', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Armor a = CardConstants.armors[0];
      final Armor b = CardConstants.armors[1];
      final Armor c = CardConstants.armors[2];
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[
          _player(level: 6, hp: 2000, maxHp: 2000)
              .copyWith(armor: a, storedArmor: b),
        ],
        movement: 0,
      );
      controller.pendingArmorOffer = c;

      expect(controller.equipPendingArmor(discardReplaced: true), isTrue);
      final Player after =
          container.read(gameControllerProvider)!.activePlayer;
      expect(after.armor?.id, c.id,
          reason: 'la 3e tenue est équipée');
      expect(after.storedArmor?.id, b.id,
          reason: 'la réserve initiale est PRÉSERVÉE (plus de perte)');
    });
  });

  group('Mode Big Four (retours playtest)', () {
    test('createNewGame : 8 joueurs, 4 équipes de 2 par faction', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      // Persos imposés dans l'ordre de jeu : Rebel, Rebel, Jedi, Jedi,
      // Sith, Sith, Empire, Empire.
      CharacterDefinition charById(String id) =>
          CharacterConstants.characters
              .firstWhere((CharacterDefinition c) => c.id == id);
      final List<CharacterDefinition> characters = <CharacterDefinition>[
        charById('princesse_leia'), charById('padme_amidala'),
        charById('luke_skywalker'), charById('yoda'),
        charById('dark_vador'), charById('darth_nihilus'),
        charById('empereur_palpatine'), charById('grand_moff_tarkin'),
      ];
      final GameState created = await controller.createNewGame(NewGameConfig(
        mode: GameMode.bigFour,
        playerCount: 8,
        teamSize: 2,
        planetType: PlanetType.hoth,
        characters: characters,
      ));

      expect(created.players.length, 8);
      expect(created.mode, GameMode.bigFour);
      // Équipes par blocs de 2 : A(Rebel), B(Jedi), C(Sith), D(Empire).
      final List<TeamSide?> teams =
          created.players.map((Player p) => p.team).toList();
      expect(teams.sublist(0, 2), everyElement(TeamSide.teamA));
      expect(teams.sublist(2, 4), everyElement(TeamSide.teamB));
      expect(teams.sublist(4, 6), everyElement(TeamSide.teamC));
      expect(teams.sublist(6, 8), everyElement(TeamSide.teamD));
      // Factions imposées.
      expect(created.players[0].faction, Faction.rebel);
      expect(created.players[4].faction, Faction.sith);
      expect(created.players[6].faction, Faction.empire);
    });

    test('Doubles monstres (fix 20/09) : stats additionnées, XP x 2,5, '
        'apparition après le premier N4', () {
      // 1) Le populate SANS débloquage ne pose jamais de double.
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Planet revealed = mapService.revealFogAround(
        planet,
        const Position(10, 10),
        radius: 30,
      );
      final populateSimple = mapService.populateNewlyDiscoveredTiles(
        before: planet,
        after: revealed,
        phase: GamePhase.fin,
        rng: Random(3),
        occupied: const <Position>{},
        existingPortals: const [],
        bossUnlocked: false,
        doubleMonstersUnlocked: false,
      );
      final int simpleMonstres = populateSimple.planet.tiles
          .where((Tile t) => t.monster != null)
          .length;
      final int simplesAvecDouble = populateSimple.planet.tiles
          .where((Tile t) => t.monster != null && t.monster2 != null)
          .length;
      expect(simpleMonstres, greaterThan(0),
          reason: 'des monstres simples sont posés');
      expect(simplesAvecDouble, 0,
          reason: 'doubles verrouillés tant que personne n’est N4');

      // 2) Débloqué : ~20 % des monstres posés sont des doubles, composés
      //    de deux monstres de niveaux 1-3, stats additionnées.
      final populateDouble = mapService.populateNewlyDiscoveredTiles(
        before: planet,
        after: revealed,
        phase: GamePhase.fin,
        rng: Random(9),
        occupied: const <Position>{},
        existingPortals: const [],
        bossUnlocked: false,
        doubleMonstersUnlocked: true,
      );
      final List<Tile> doubles = populateDouble.planet.tiles
          .where((Tile t) => t.monster != null && t.monster2 != null)
          .toList();
      expect(doubles, isNotEmpty,
          reason: 'sur ~370 cases en phase fin, des doubles sortent '
              '(probabilité 20 % par monstre posé)');
      for (final Tile tile in doubles) {
        expect(tile.monster!.level, inInclusiveRange(1, 3));
        expect(tile.monster2!.level, inInclusiveRange(1, 3));
      }
    });

    test('Doubles monstres : XP = (somme des XP) x 2,5', () {
      // N1 (10 XP) + N2 (20 XP) → 75 XP (et non 30).
      final Monster m1 = Monster.forCard('Gungans', 1);
      final Monster m2 = Monster.forCard('Droïde de combat B1', 2);
      final int xp = ((m1.xpReward + m2.xpReward) * 2.5).round();
      expect(m1.attack + m2.attack, 15, reason: '5 + 10 ATK');
      expect(m1.hp + m2.hp, 500, reason: '200 + 300 PV');
      expect(xp, 75, reason: '(10 + 20) x 2,5 = 75 (et non 30)');
    });

    test('FIX 20/09 : le gagnant Big Four est annoncé par sa FACTION', () {
      // Équipe D (Empire : deux joueurs) atteint 3 boss ADVERSES.
      final GameState base = _duelState(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        <Player>[
          _player(faction: Faction.empire, position: const Position(0, 0))
              .copyWith(team: TeamSide.teamD),
          _player(faction: Faction.empire, position: const Position(1, 1))
              .copyWith(team: TeamSide.teamD),
          _player(faction: Faction.rebel, position: const Position(2, 2))
              .copyWith(team: TeamSide.teamA),
          _player(faction: Faction.rebel, position: const Position(3, 3))
              .copyWith(team: TeamSide.teamA),
          _player(faction: Faction.jedi, position: const Position(4, 4))
              .copyWith(team: TeamSide.teamB),
          _player(faction: Faction.jedi, position: const Position(5, 5))
              .copyWith(team: TeamSide.teamB),
          _player(faction: Faction.sith, position: const Position(6, 6))
              .copyWith(team: TeamSide.teamC),
          _player(faction: Faction.sith, position: const Position(7, 7))
              .copyWith(team: TeamSide.teamC),
        ],
      ).copyWith(mode: GameMode.bigFour);
      final List<Player> players = List<Player>.of(base.players);
      players[0] = players[0].copyWith(
        defeatedBosses: const <BossType>[
          BossType.exogorth, // Sith (adverse)
          BossType.kraytDragon, // Rebel (adverse)
          BossType.rancor, // Jedi (adverse)
        ],
      );
      final GameState state = base.copyWith(players: players);

      final WinnerResolution winner = GameOverScreen.resolveWinner(state);

      expect(winner.title, 'La faction Empire remporte la partie !',
          reason: 'en Big Four, la FACTION gagnante est annoncée '
              '(et non « Équipe D »)');
    });


    test('la case d\'un coéquipier Big Four n\'est pas entrable', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player hero = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: const Position(0, 0),
      ).copyWith(team: TeamSide.teamA);
      final Player mate = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 2000,
        maxHp: 2000,
        position: const Position(1, 0),
      ).copyWith(team: TeamSide.teamA, planet: PlanetType.hoth);
      final List<Position> targets = mapService.validMoveTargets(
        planet: planet,
        players: <Player>[hero, mate],
        activePlayerIndex: 0,
      );
      expect(targets, isNot(contains(const Position(1, 0))),
          reason: 'coéquipier Big Four : case bloquée');
    });

    test('Big Four : fin de partie quand une seule équipe a des vivants',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      Player alive = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 2000,
        maxHp: 2000,
      ).copyWith(team: TeamSide.teamA);
      final Player deadA = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 0,
        maxHp: 2000,
      ).copyWith(team: TeamSide.teamA, eliminated: true);
      final Player deadB = _player(
        faction: Faction.jedi,
        level: 6,
        hp: 0,
        maxHp: 2000,
      ).copyWith(team: TeamSide.teamB, eliminated: true);
      final Player deadC = _player(
        faction: Faction.sith,
        level: 6,
        hp: 0,
        maxHp: 2000,
      ).copyWith(team: TeamSide.teamC, eliminated: true);
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest2',
        seed: 42,
        mode: GameMode.bigFour,
        teamSize: 2,
        planetType: PlanetType.hoth,
        currentPlanet: planet,
        players: <Player>[alive, deadA, deadB, deadC],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );

      // Toute action de jeu déclenche la vérification de survie : dès
      // qu'une seule équipe a des vivants, la partie se termine
      // (générique à N équipes).
      controller.applyPlayerCombatHp(100);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.status, GameStatus.finished);
      expect(alive, isNotNull, reason: 'l\'Équipe A est la dernière debout');
    });
  });

  group('Boss de sa propre faction : non-combattable (retours playtest)', () {
    test('la case du boss Empire est exclue pour un joueur Empire, incluse '
        'pour les autres', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet etoileNoire =
          mapService.generateSecondaryPlanet(PlanetType.etoileNoire, seed: 7);
      const Position bossPos = Position(6, 6);
      final Player empereur = _player(
        faction: Faction.empire,
        level: 6,
        hp: 10000,
        maxHp: 10000,
        position: const Position(3, 3),
      ).copyWith(planet: PlanetType.etoileNoire);
      final Player rebel = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 10000,
        maxHp: 10000,
        position: const Position(5, 6),
      ).copyWith(planet: PlanetType.etoileNoire);
      final GameState state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest2',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.etoileNoire,
        currentPlanet: etoileNoire,
        players: <Player>[empereur, rebel],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 2,
        lastDiceRoll: 2,
        bosses: <Boss>[
          Boss(
            name: 'AT-AT',
            type: BossType.atAt,
            planet: PlanetType.etoileNoire,
            hp: GameConstants.bossHp,
            attackMin: GameConstants.bossAttackMin,
            attackMax: GameConstants.bossAttackMax,
            position: bossPos,
          ),
        ],
        portals: const [],
        status: GameStatus.inProgress,
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);

      // Joueur Empire : le boss Empire n'est pas ciblable.
      controller.state = state;
      expect(controller.validMoveTargets(), isNot(contains(bossPos)));

      // Joueur Rebel : le boss Empire reste attaquable.
      controller.state = state.copyWith(currentPlayerIndex: 1);
      expect(controller.validMoveTargets(), contains(bossPos));
    });

    test('un boss de sa faction ne compte PAS dans les 3 victoires', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Player empereur = _player(
        faction: Faction.empire,
        level: 6,
        hp: 10000,
        maxHp: 10000,
      );
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest2',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet:
            mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        players: <Player>[empereur],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: <Boss>[
          Boss(
            name: 'AT-AT',
            type: BossType.atAt,
            planet: PlanetType.etoileNoire,
            hp: GameConstants.bossHp,
            attackMin: GameConstants.bossAttackMin,
            attackMax: GameConstants.bossAttackMax,
            position: const Position(1, 1),
          ),
        ],
        portals: const [],
        status: GameStatus.inProgress,
      );

      controller.applyBossVictory(type: BossType.atAt, playerHp: 1000);
      final GameState after =
          container.read(gameControllerProvider)!;
      expect(after.status, GameStatus.inProgress,
          reason: 'AT-AT (Empire) est le boss de SA faction : il ne compte '
              'pas dans les 3 victoires adverses');
      expect(after.players[0].defeatedBosses, contains(BossType.atAt));
    });
  });

  group('Boss : le vainqueur ne peut pas le rebattre (retours playtest)', () {
    test('la case du boss est exclue pour le vainqueur, disponible pour '
        'les autres', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet mustafar =
          mapService.generateSecondaryPlanet(PlanetType.mustafar, seed: 7);
      const Position bossPos = Position(6, 6);
      final Player winner = _player(
        faction: Faction.jedi,
        level: 6,
        hp: 10000,
        maxHp: 10000,
        position: const Position(3, 3),
      ).copyWith(
        planet: PlanetType.mustafar,
        defeatedBosses: <BossType>[BossType.exogorth],
      );
      final Player other = _player(
        faction: Faction.rebel,
        level: 6,
        hp: 10000,
        maxHp: 10000,
        position: const Position(5, 6),
      ).copyWith(planet: PlanetType.mustafar);
      final GameState state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest2',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.mustafar,
        currentPlanet: mustafar,
        players: <Player>[winner, other],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 2,
        lastDiceRoll: 2,
        bosses: <Boss>[
          Boss(
            name: 'Exogorth',
            type: BossType.exogorth,
            planet: PlanetType.mustafar,
            hp: GameConstants.bossHp,
            attackMin: GameConstants.bossAttackMin,
            attackMax: GameConstants.bossAttackMax,
            position: bossPos,
          ),
        ],
        portals: const [],
        status: GameStatus.inProgress,
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;

      // Le vainqueur : la case du boss n'est plus ciblable.
      final List<Position> forWinner = controller.validMoveTargets();
      expect(forWinner, isNot(contains(bossPos)));

      // L'autre joueur : la case reste attaquable.
      controller.state = state.copyWith(currentPlayerIndex: 1);
      final List<Position> forOther = controller.validMoveTargets();
      expect(forOther, contains(bossPos));
    });
  });

  group('Dialog carte ennemie (fix « case sans effet »)', () {
    test('la carte ennemie remplit pendingAllyOffer pour le dialog', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally scout = CardConstants.nukers
          .firstWhere((Ally a) => a.name == 'Scout Trooper'); // Empire
      final Player player = _player(faction: Faction.rebel);
      final Position target = mapService
          .validMoveTargets(
              planet: planet, players: <Player>[player],
              activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      final int index = target.y * planet.width + target.x;
      tiles[index] = tiles[index].copyWith(ally: scout);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet.withTiles(tiles), <Player>[player]);

      final MoveResult result =
          controller.moveActivePlayerTo(target.x, target.y);
      expect(result, MoveResult.allyEncounter);
      expect(controller.pendingAllyOffer?.name, 'Scout Trooper',
          reason: 'sans ça, le dialog ne s affiche jamais '
              '(bug « case sans effet » du playtest)');
      expect(controller.pendingSpecialDamage, isNotNull);
    });
  });

  group('Portails : les 4 restent atteignables en phase fin', () {
    test('un peuplement complet en phase fin pose 4 portails (majorité '
        'des graines)', () {
      int fourCount = 0;
      int total = 0;
      for (int seed = 1; seed <= 30; seed++) {
        final Planet planet =
            mapService.generateStartPlanet(PlanetType.coruscant, seed: seed);
        final Planet revealed = mapService.revealFogAround(
          planet,
          const Position(10, 10),
          radius: 30,
        );
        final populate = mapService.populateNewlyDiscoveredTiles(
          before: planet,
          after: revealed,
          phase: GamePhase.fin,
          rng: Random(seed * 7 + 1),
          occupied: <Position>{},
          existingPortals: const [],
          bossUnlocked: false,
        );
        total += populate.newPortals.length;
        if (populate.newPortals.length == 4) fourCount++;
      }
      expect(fourCount, greaterThanOrEqualTo(20),
          reason: 'à 10 % de proba portail en phase fin, au moins 2 graines '
              'sur 3 atteignent le plafond de 4 portails '
              '(moyenne posée : ${total / 30})');
    });
  });

  group('Ambiances sonores des planètes (fix 19/09)', () {
    test('les 9 planètes ont chacune leur piste, ids = images de planètes',
        () {
      final List<PlanetType> all = <PlanetType>[
        ...PlanetConstants.startPlanets,
        ...PlanetConstants.secondaryPlanets,
      ];
      expect(all.length, 9,
          reason: '5 planètes principales + 4 planètes secondaires');
      expect(all.map(planetAmbienceTrack).toSet().length, 9,
          reason: 'une boucle sonore DISTINCTE par planète');
      for (final PlanetType type in all) {
        expect(planetAmbienceTrack(type), planetImageId(type),
            reason: 'mêmes noms de fichiers que les images '
                '(assets/images/planets/) — plus simple à déposer');
      }
    });
  });

  group('Sauvegarder et quitter en pleine partie (fix 19/09)', () {
    test('saveGame() persiste l\'état courant, tour en cours inclus',
        () async {
      final _RecordingSaveService recorder = _RecordingSaveService();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          saveServiceProvider.overrideWithValue(recorder),
          combatServiceProvider
              .overrideWithValue(CombatService(random: Random(5))),
        ],
      );
      addTearDown(container.dispose);
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _duelState(planet, <Player>[_player()], movement: 3);

      await controller.saveGame();

      expect(recorder.lastSaved, isNotNull,
          reason: 'quitter en pleine partie doit sauvegarder l\'état du '
              'tour en cours (l\'autosave ne couvre que la fin de tour)');
      expect(recorder.lastSaved!.movementPointsRemaining, 3,
          reason: 'les déplacements restants du tour en cours sont '
              'conservés pour la reprise');
      expect(recorder.lastSaved!.status, GameStatus.inProgress);
      expect(recorder.lastSaved!.savedAt, isNotNull);
    });
  });
}