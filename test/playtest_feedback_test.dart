import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/models/weapon.dart';
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
  Faction faction = Faction.rebel,
  int level = 1,
  int hp = 200,
  int maxHp = 200,
  List<Ally> allies = const [],
  Ally? storedAlly,
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
    storedAlly: storedAlly,
  );
}

/// État figé avec [ally] posée sur un voisin jouable du joueur actif.
({GameState state, Position target}) _stateWithAllyNearby(
  Planet planet,
  Player player,
  Ally ally,
) {
  final Position target = mapService
      .validMoveTargets(planet: planet, players: <Player>[player],
          activePlayerIndex: 0)
      .first;
  final List<Tile> tiles = List<Tile>.of(planet.tiles);
  final int index = target.y * planet.width + target.x;
  tiles[index] = tiles[index].copyWith(ally: ally);
  final GameState state = GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'playtest',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: planet.type,
    currentPlanet: planet.withTiles(tiles),
    players: <Player>[player],
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: 3,
    lastDiceRoll: 3,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
  return (state: state, target: target);
}

GameState _stateWithMonsterNearby(
  Planet planet,
  Player player,
  Monster monster,
) {
  final Position target = mapService
      .validMoveTargets(planet: planet, players: <Player>[player],
          activePlayerIndex: 0)
      .first;
  final List<Tile> tiles = List<Tile>.of(planet.tiles);
  final int index = target.y * planet.width + target.x;
  tiles[index] = tiles[index].copyWith(monster: monster);
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'playtest',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: planet.type,
    currentPlanet: planet.withTiles(tiles),
    players: <Player>[player],
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: 3,
    lastDiceRoll: 3,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
}

void main() {
  group('Bonus des cartes Spéciales alliées (retours playtest)', () {
    test('Ally.special expose les bonus et isFriendlyTo', () {
      final Ally luke = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Luke Skywalker');
      expect(luke.bonusAtkIfFriendly, 2000);
      expect(luke.bonusHpIfFriendly, 500);
      expect(luke.isFriendlyTo(Faction.rebel), isTrue,
          reason: 'Rebel est allié du Jedi Luke');
      expect(luke.isFriendlyTo(Faction.jedi), isTrue);
      expect(luke.isFriendlyTo(Faction.empire), isFalse);
      expect(luke.isFriendlyTo(Faction.sith), isFalse);
    });

    test('JSON round-trip : les bonus survivent à la sauvegarde', () {
      final Ally yoda = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Yoda');
      final Ally copy = Ally.fromJson(yoda.toJson());
      expect(copy.bonusAtkIfFriendly, 1500);
      expect(copy.bonusHpIfFriendly, 1000);
    });
  });

  group('Dégâts reçus : multiplicateur par niveau + plafond 60 %', () {
    test('scaleIncomingDamage : table de multiplicateurs', () {
      expect(
        GameConstants.scaleIncomingDamage(100,
            level: 1, maxHp: 10000),
        50,
      );
      expect(
        GameConstants.scaleIncomingDamage(100,
            level: 2, maxHp: 10000),
        70,
      );
      expect(
        GameConstants.scaleIncomingDamage(100,
            level: 3, maxHp: 10000),
        85,
      );
      expect(
        GameConstants.scaleIncomingDamage(100,
            level: 4, maxHp: 10000),
        100,
      );
    });

    test('plafond : aucun coup ne dépasse 60 % des PV max', () {
      expect(
        GameConstants.scaleIncomingDamage(500, level: 1, maxHp: 200),
        120,
        reason: '500 x 0,5 = 250 → plafonné à 60 % de 200 = 120',
      );
      expect(
        GameConstants.scaleIncomingDamage(500, level: 6, maxHp: 5000),
        500,
        reason: '500 x 1 = 500 < cap 3000 → inchangé',
      );
      expect(
        GameConstants.scaleIncomingDamage(10000, level: 6, maxHp: 5000),
        3000,
        reason: 'le plafond 60 % s applique même au N6',
      );
    });

    test('un joueur N1 survit à une Spéciale ennemie (-500 de base)', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally vador = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Dark Vador');
      final Player leia = _player(faction: Faction.rebel);
      final ({GameState state, Position target}) setup =
          _stateWithAllyNearby(planet, leia, vador);

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = setup.state;
      controller.moveActivePlayerTo(setup.target.x, setup.target.y);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.eliminated, isFalse,
          reason: 'plafond 60 % : -120 PV au lieu de -500');
      expect(after.activePlayer.hp, 80);
    });

    test('un joueur N4+ subit les dégâts complets (multiplicateur 1,0)',
        () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally vador = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Dark Vador');
      // Niveau 4, PV max 1100 (table GDD) : -500 x 1 = -500, cap 660.
      final Player leia = _player(
        faction: Faction.rebel,
        level: 4,
        hp: 1000,
        maxHp: 1100,
      );
      final ({GameState state, Position target}) setup =
          _stateWithAllyNearby(planet, leia, vador);

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = setup.state;
      controller.moveActivePlayerTo(setup.target.x, setup.target.y);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.hp, 500,
          reason: '-500 complets (pas de réduction au N4+, cap non atteint)');
    });

    test('la riposte du monstre est tempérée au N1', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(faction: Faction.jedi);
      final GameState state =
          _stateWithMonsterNearby(planet, player, Monster.forCard('Sarlacc', 5));
      // Sarlacc : 50 ATK, 1000 PV.

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;
      controller.moveActivePlayerTo(
        mapService
            .validMoveTargets(
                planet: planet, players: <Player>[player],
                activePlayerIndex: 0)
            .first
            .x,
        mapService
            .validMoveTargets(
                planet: planet, players: <Player>[player],
                activePlayerIndex: 0)
            .first
            .y,
      );

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startMonsterCombat(
        mapService
            .validMoveTargets(
                planet: planet, players: <Player>[player],
                activePlayerIndex: 0)
            .first,
      );
      final int hpBefore = container.read(gameControllerProvider)!.activePlayer.hp;
      combat.attack();
      final CombatSession session = container.read(combatControllerProvider)!;
      if (!session.finished) {
        // Fix 20/09 : riposte ALÉATOIRE (±10 % autour de 50 ATK, puis
        // x 0,5 au N1) → entre 22 et 27 PV.
        expect(
          hpBefore - session.playerHp,
          inInclusiveRange(22, 27),
          reason: 'riposte 50 ATK x 0,5 = 25 au niveau 1 (±10 %)',
        );
      }
    });
  });

  group('Restriction de rareté des alliés + réserve', () {
    test('recruter une Rare au N1 est refusé, au N3 autorisé', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Ally r2d2 = CardConstants.healers
          .firstWhere((Ally a) => a.name == 'R2-D2'); // Rare, 3 PP
      final Player player = _player(faction: Faction.rebel);
      final ({GameState state, Position target}) setup =
          _stateWithAllyNearby(planet, player, r2d2);

      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = setup.state;
      controller.moveActivePlayerTo(setup.target.x, setup.target.y);

      controller.recruitPendingAlly();
      expect(container.read(gameControllerProvider)!.activePlayer.allies,
          isEmpty, reason: 'Rare interdite au niveau 1');

      // Montée au N3 : le même pending peut être recruté.
      final GameState leveled =
          container.read(gameControllerProvider)!.copyWith(
        players: <Player>[
          container.read(gameControllerProvider)!.activePlayer.copyWith(
                level: 3,
              ),
        ],
      );
      controller.state = leveled;
      controller.pendingAllyOffer = r2d2;
      controller.recruitPendingAlly();
      expect(container.read(gameControllerProvider)!.activePlayer.allies
          .map((Ally a) => a.name),
          contains('R2-D2'));
    });

    test('storePendingAlly / recruitStoredAlly : le soin instantané ne se '
        're-déclenche pas depuis la réserve', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally r2d2 = CardConstants.healers
          .firstWhere((Ally a) => a.name == 'R2-D2'); // healInstant 500
      controller.state = _stateWithAllyNearby(
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42),
        _player(faction: Faction.rebel, level: 3, hp: 100),
        r2d2,
      ).state;

      controller.pendingAllyOffer = r2d2;
      controller.storePendingAlly();
      GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.storedAlly?.name, 'R2-D2');
      expect(after.activePlayer.allies, isEmpty);
      expect(after.activePlayer.hp, 100,
          reason: 'mettre en réserve ne soigne pas');

      controller.recruitStoredAlly();
      after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.allies.map((Ally a) => a.name),
          contains('R2-D2'));
      expect(after.activePlayer.storedAlly, isNull);
      expect(after.activePlayer.hp, 100,
          reason: 'healInstant réservé au premier recrutement (pas de '
              'boucle de soin infinie)');
    });

    test('recruitStoredAlly refuse une rareté interdite au niveau', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally luke = CardConstants.specials
          .firstWhere((Ally a) => a.name == 'Luke Skywalker'); // Légendaire
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet: mapService.generateStartPlanet(PlanetType.hoth,
            seed: 42),
        players: <Player>[
          _player(faction: Faction.rebel, storedAlly: luke),
        ],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );

      expect(controller.recruitStoredAlly(), isFalse,
          reason: 'légendaire interdit au N1');
      expect(container.read(gameControllerProvider)!.activePlayer.storedAlly,
          isNotNull);
    });

    test('storeTeamAlly transfère un allié de l équipe vers la réserve', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally ewok = CardConstants.squads
          .firstWhere((Ally a) => a.name == 'Ewok');
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet: mapService.generateStartPlanet(PlanetType.hoth,
            seed: 42),
        players: <Player>[
          _player(faction: Faction.rebel, allies: <Ally>[ewok]),
        ],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );

      expect(controller.storeTeamAlly(0), isTrue);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.allies, isEmpty);
      expect(after.activePlayer.storedAlly?.name, 'Ewok');
      // Réserve occupée : un second transfert échoue.
      expect(controller.storeTeamAlly(0), isFalse);
    });

    test('discardStoredAlly détruit l allié en réserve', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Ally ewok = CardConstants.squads
          .firstWhere((Ally a) => a.name == 'Ewok');
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet: mapService.generateStartPlanet(PlanetType.hoth,
            seed: 42),
        players: <Player>[_player(faction: Faction.rebel, storedAlly: ewok)],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );

      controller.discardStoredAlly();
      expect(container.read(gameControllerProvider)!.activePlayer.storedAlly,
          isNull);
    });
  });

  group('Refuser / défausser des objets', () {
    test('declinePendingWeapon détruit la proposition', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.pendingWeaponOffer =
          CardConstants.weapons.firstWhere((w) => w.rarity == Rarity.commun);
      controller.declinePendingWeapon();
      expect(controller.pendingWeaponOffer, isNull);
    });

    test('discardStoredWeapon / discardEquippedWeapon vident les emplacements',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Weapon arme = CardConstants.weapons.first;
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'playtest',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet: mapService.generateStartPlanet(PlanetType.hoth,
            seed: 42),
        players: <Player>[
          _player(faction: Faction.rebel).copyWith(
            weapon: arme,
            storedWeapon: arme,
          ),
        ],
        turn: 1,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 0,
        lastDiceRoll: null,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );

      controller.discardStoredWeapon();
      expect(
          container.read(gameControllerProvider)!.activePlayer.storedWeapon,
          isNull);
      controller.discardEquippedWeapon();
      expect(
          container.read(gameControllerProvider)!.activePlayer.weapon, isNull);
    });
  });
}
