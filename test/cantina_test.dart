import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/core/constants/planet_constants.dart'
    show PlanetConstants;
import 'package:star_wars_rpg/models/cantina_zone.dart';
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

ProviderContainer _container(int combatSeed) => ProviderContainer(
      overrides: <Override>[
        saveServiceProvider.overrideWithValue(_FakeSaveService()),
        combatServiceProvider
            .overrideWithValue(CombatService(random: Random(combatSeed))),
      ],
    );

final MapService mapService = MapService();

Planet _planet() =>
    mapService.generateStartPlanet(PlanetType.tatooine, seed: 42);

Position _door() => mapService.cantinaAnchorFor(42)!;

/// Un voisin hors porte de la case-portail (le plateau est connexe :
/// au moins un existe — la porte est protégée du blocage et connexe).
Position _outsideNeighbor(Planet planet, Position door) => mapService
    .neighborPositions(door, planet)
    .firstWhere((Position p) => planet.isWalkableAt(p.x, p.y));

Player _player({
  required Position position,
  PlanetType planet = PlanetType.tatooine,
  Faction faction = Faction.rebel,
  int hp = 200,
  int maxHp = 200,
  int index = 0,
}) {
  return Player(
    id: 'p${index + 1}',
    name: 'Joueur ${index + 1}',
    faction: faction,
    position: position,
    planet: planet,
    level: 1,
    xp: 0,
    attack: GameConstants.attackForLevel(1),
    hp: hp,
    maxHp: maxHp,
  );
}

GameState _state({
  required Planet planet,
  required List<Player> players,
  required Position door,
  PlanetType planetType = PlanetType.tatooine,
  int movement = 3,
  Planet? cantinaPlanet,
}) {
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'cantina_test',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: planetType,
    currentPlanet:
        planetType == PlanetType.cantina ? cantinaPlanet! : planet,
    planets: <PlanetType, Planet>{
      PlanetType.tatooine: planet,
      PlanetType.cantina: cantinaPlanet ?? mapService.generateCantinaPlanet(),
    },
    players: players,
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: movement,
    lastDiceRoll: movement,
    bosses: const [],
    portals: const [],
    cantina: CantinaZone(planet: PlanetType.tatooine, anchor: door),
    status: GameStatus.inProgress,
  );
}

void main() {
  group('La porte de la cantina (retours playtest 19/09 v2)', () {
    test('génération : une case ordinaire protégée, déterministe', () {
      final Planet planet = _planet();
      final Position door = _door();
      expect(door, isNotNull);
      expect(planet.tileAt(door.x, door.y).walkable, isTrue,
          reason: 'la porte est protégée du blocage');
      expect(planet.tileAt(door.x, door.y).cantina, isFalse,
          reason: 'la porte est une case ordinaire : la cantina est une '
              'mini-zone séparée');
      expect(planet.playableTileCount, BoardConstants.playableTiles);
      expect(planet.blockedTileCount, BoardConstants.blockedTiles);
      expect(mapService.isFullyConnected(planet), isTrue);
      // Déterminisme.
      expect(mapService.cantinaAnchorFor(42), door);
    });

    test('la mini-zone 3x3 : bar bloqué, comptoir, entrée en (1,2)', () {
      final Planet cantina = mapService.generateCantinaPlanet();
      expect(cantina.type, PlanetType.cantina);
      expect(cantina.width, 3);
      expect(cantina.height, 3);
      for (int x = 0; x < 3; x++) {
        expect(cantina.tileAt(x, 0).walkable, isFalse,
            reason: 'la rangée du haut est le bar en bois (bloquée)');
      }
      for (int x = 0; x < 3; x++) {
        expect(cantina.tileAt(x, 1).cantinaDrink, isTrue,
            reason: 'la ligne du milieu est le comptoir (PV 100 %)');
      }
      final Tile entrance = cantina.tileAt(1, 2);
      expect(entrance.walkable, isTrue);
      expect(entrance.cantinaEntrance, isTrue);
      expect(cantina.tileAt(1, 1).cantina, isTrue);
    });

    test('marcher sur la porte téléporte DANS la cantina (case (1,2))',
        () {
      final Planet planet = _planet();
      final Position door = _door();
      final Position outside = _outsideNeighbor(planet, door);
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: planet,
        players: <Player>[_player(position: outside)],
        door: door,
      );

      final MoveResult result =
          controller.moveActivePlayerTo(door.x, door.y);

      expect(result, MoveResult.cantinaTravel);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.planetType, PlanetType.cantina,
          reason: 'on entre dans une NOUVELLE zone (mini-planète 3x3)');
      expect(after.currentPlanet.type, PlanetType.cantina);
      expect(after.activePlayer.position, PlanetConstants.cantinaArrival,
          reason: 'arrivée sur la case du milieu bas (1,2)');
      expect(after.activePlayer.returnPlanet, PlanetType.tatooine);
      expect(after.activePlayer.returnPosition, door);
      expect(after.cantina!.visited, isTrue,
          reason: 'la première entrée marque la zone comme visitée');
      expect(after.movementPointsRemaining, 2,
          reason: 'le pas sur la case-portail coûte 1 point');
    });

    test('le comptoir du milieu remet les PV au maximum', () {
      final Planet planet = _planet();
      final Position door = _door();
      final Planet cantina = mapService.generateCantinaPlanet();
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: planet,
        // Déjà dans la cantina, sur la case d'entrée, blessé.
        players: <Player>[
          _player(
            position: PlanetConstants.cantinaArrival,
            planet: PlanetType.cantina,
            hp: 10,
            maxHp: 200,
          ),
        ],
        door: door,
        planetType: PlanetType.cantina,
        cantinaPlanet: cantina,
        movement: 2,
      );

      final MoveResult result = controller.moveActivePlayerTo(1, 1);

      expect(result, MoveResult.cantinaDrink);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.hp, after.activePlayer.totalMaxHp,
          reason: 'le verre remet les PV à 100 %');
    });

    test('repasser par la case d\'entrée (1,2) ramène à la porte', () {
      final Planet planet = _planet();
      final Position door = _door();
      final Planet cantina = mapService.generateCantinaPlanet();
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Player traveler = _player(
        position: const Position(0, 2),
        planet: PlanetType.cantina,
      ).copyWith(
        returnPlanet: PlanetType.tatooine,
        returnPosition: door,
      );
      controller.state = _state(
        planet: planet,
        players: <Player>[traveler],
        door: door,
        planetType: PlanetType.cantina,
        cantinaPlanet: cantina,
        movement: 3,
      );

      final MoveResult result = controller.moveActivePlayerTo(1, 2);

      expect(result, MoveResult.portalTravel);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.planetType, PlanetType.tatooine,
          reason: 'on ressort sur la planète principale');
      expect(after.activePlayer.position, door,
          reason: 'retour sur la case-portail elle-même');
      expect(after.activePlayer.returnPlanet, isNull);
    });

    test('aucun combat JvJ dans la zone : la case d\'un autre joueur '
        'dedans n\'est pas entrable', () {
      final Planet planet = _planet();
      final Position door = _door();
      final Planet cantina = mapService.generateCantinaPlanet();
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: planet,
        players: <Player>[
          _player(
            position: PlanetConstants.cantinaArrival,
            planet: PlanetType.cantina,
          ),
          _player(
            position: const Position(1, 1),
            planet: PlanetType.cantina,
            faction: Faction.sith,
            index: 1,
          ),
        ],
        door: door,
        planetType: PlanetType.cantina,
        cantinaPlanet: cantina,
      );

      final List<Position> targets = controller.validMoveTargets();

      expect(targets, isNot(contains(const Position(1, 1))),
          reason: 'pas d\'attaque ni d\'approche d\'un joueur dans la '
              'cantina');
    });

    test('le peuplement ne tire aucun contenu dans la cantina', () {
      final Planet cantina = mapService.generateCantinaPlanet();
      final Planet revealed = mapService.revealFogAround(
        cantina,
        PlanetConstants.cantinaArrival,
        radius: 10,
      );
      final populate = mapService.populateNewlyDiscoveredTiles(
        before: cantina,
        after: revealed,
        phase: GamePhase.fin,
        rng: Random(11),
        occupied: const <Position>{},
        existingPortals: const [],
        bossUnlocked: false,
      );
      for (final Tile tile in populate.planet.tiles) {
        expect(tile.monster, isNull, reason: 'pas de monstre dans la cantina');
        expect(tile.ally, isNull);
        expect(tile.weapon, isNull);
        expect(tile.armor, isNull);
        expect(tile.healSite, isFalse);
      }
    });
  });

  group('Sauvegarde de la cantina', () {
    test('roundtrip JSON : planète cantina, porte et visited conservés',
        () {
      const CantinaZone zone = CantinaZone(
        planet: PlanetType.endor,
        anchor: Position(4, 7),
        visited: true,
      );
      final GameState state = _state(
        planet: _planet(),
        players: <Player>[_player(position: const Position(0, 0))],
        door: const Position(4, 7),
      );
      final GameState restored =
          GameState.fromJson(state.toJson()..['cantina'] = zone.toJson());

      expect(restored.cantina, isNotNull);
      expect(restored.cantina!.planet, PlanetType.endor);
      expect(restored.cantina!.anchor, const Position(4, 7));
      expect(restored.cantina!.visited, isTrue);
      expect(restored.planets[PlanetType.cantina], isNotNull,
          reason: 'la mini-zone est sérialisée avec le reste des planètes');
      expect(restored.planets[PlanetType.cantina]!.width, 3);
    });

    test('une sauvegarde sans cantina charge avec cantina null', () {
      final GameState state = _state(
        planet: _planet(),
        players: <Player>[_player(position: const Position(0, 0))],
        door: _door(),
      );
      final Map<String, dynamic> json = state.toJson()..remove('cantina');
      final GameState restored = GameState.fromJson(json);
      expect(restored.cantina, isNull,
          reason: 'les parties d\'avant la cantina restent jouables');
    });
  });
}
