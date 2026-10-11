import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/planet_constants.dart'
    show PlanetConstants;
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';
import 'package:star_wars_rpg/widgets/card_image.dart'
    show planetImageId;

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

Future<GameState> _newGame(GameController controller,
    {PlanetType type = PlanetType.hoth}) async {
  return controller.createNewGame(NewGameConfig(
    mode: GameMode.chacunPourSoi,
    playerCount: 2,
    teamSize: 0,
    planetType: type,
    characters: <CharacterDefinition>[
      CharacterConstants.characters[0],
      CharacterConstants.characters[2],
    ],
  ));
}

/// Place le joueur actif sur une case voisine de [target] avec des points
/// de mouvement, pour marcher dessus au test suivant.
void _placeNextTo(ProviderContainer container, Position target) {
  final GameController controller =
      container.read(gameControllerProvider.notifier);
  final GameState state = container.read(gameControllerProvider)!;
  final Planet planet = state.currentPlanet;
  final Position from = mapService
      .neighborPositions(target, planet)
      .firstWhere((Position p) => planet.isWalkableAt(p.x, p.y));
  final List<Player> players = List<Player>.of(state.players);
  players[state.currentPlayerIndex] =
      state.activePlayer.copyWith(position: from);
  controller.state = state.copyWith(
    players: players,
    movementPointsRemaining: 4,
  );
}

void main() {
  group('Porte du Faucon — ancrage par graine (retours playtest 11/10)',
      () {
    test('déterministe, distincte des 3 autres cases spéciales et des '
        'départs, jouable (toute graine)', () {
      for (final int seed in <int>[1, 7, 42, 123, 999, 2026, 0x7FFFFFFF]) {
        final Position? falcon = mapService.falconDoorAnchorFor(seed);
        expect(falcon, isNotNull, reason: 'seed $seed');
        final Position? cantina = mapService.cantinaAnchorFor(seed);
        final Position? teleport = mapService.teleportAnchorFor(seed);
        final Position? patapuche = mapService.patapucheAnchorFor(seed);
        expect(falcon, isNot(cantina), reason: 'seed $seed');
        expect(falcon, isNot(teleport), reason: 'seed $seed');
        expect(falcon, isNot(patapuche), reason: 'seed $seed');
        expect(BoardConstants.startPositions.contains(falcon), isFalse,
            reason: 'seed $seed');
        final Planet planet =
            mapService.generateStartPlanet(PlanetType.hoth, seed: seed);
        expect(planet.tileAt(falcon!.x, falcon.y).walkable, isTrue,
            reason: 'seed $seed : la porte est protégée du blocage');
      }
    });

    test('dès la création : zone FalconZone + planète 3x3 + case vierge',
        () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await _newGame(controller);

      expect(created.falcon, isNotNull);
      expect(created.falcon!.planet, PlanetType.hoth);
      expect(created.falcon!.anchor,
          mapService.falconDoorAnchorFor(created.seed));
      expect(created.falcon!.visited, isFalse);

      // La planète Faucon existe : 9 cases marchables, case bonus (1,0),
      // entrée/sortie (1,2), aucune consommation.
      final Planet faucon = created.planets[PlanetType.faucon]!;
      expect(faucon.tiles.length, 9);
      for (final Tile t in faucon.tiles) {
        expect(t.walkable, isTrue);
        expect(t.cantina, isTrue, reason: 'zone sanctuarisée');
        expect(t.cantinaDrink, isFalse);
      }
      expect(
          faucon
              .tileAt(PlanetConstants.falconBonusPosition.x,
                  PlanetConstants.falconBonusPosition.y)
              .walkable,
          isTrue);
      expect(faucon.tileAt(1, 2).cantinaEntrance, isTrue);

      // La case-portail est vierge : jamais de contenu tiré dessus.
      final Position door = created.falcon!.anchor;
      final Tile doorTile = created.currentPlanet.tileAt(door.x, door.y);
      expect(doorTile.monster, isNull);
      expect(doorTile.ally, isNull);
      expect(doorTile.weapon, isNull);
      expect(doorTile.armor, isNull);
      expect(doorTile.healSite, isFalse);
    });
  });

  group('Faucon — entrée, bonus, sortie', () {
    test('marcher sur la porte : falconTravel + arrivée (1,2) + visited',
        () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await _newGame(controller);
      final Position door = created.falcon!.anchor;

      _placeNextTo(container, door);
      final MoveResult result = controller.moveActivePlayerTo(door.x, door.y);
      expect(result, MoveResult.falconTravel);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.planetType, PlanetType.faucon);
      expect(after.activePlayer.planet, PlanetType.faucon);
      expect(after.activePlayer.position, PlanetConstants.falconArrival);
      expect(after.activePlayer.returnPlanet, PlanetType.hoth);
      expect(after.activePlayer.returnPosition, door);
      expect(after.falcon!.visited, isTrue,
          reason: 'le médaillon remplace le logo jaune');
    });

    test('sortie : repasser par la case d’arrivée ramène à la porte',
        () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await _newGame(controller);
      final Position door = created.falcon!.anchor;

      _placeNextTo(container, door);
      controller.moveActivePlayerTo(door.x, door.y);

      // Un pas à l'intérieur puis retour sur la case d'arrivée.
      final GameState inside = container.read(gameControllerProvider)!;
      final List<Player> players = List<Player>.of(inside.players);
      players[inside.currentPlayerIndex] =
          inside.activePlayer.copyWith(position: const Position(1, 1));
      controller.state = inside.copyWith(
        players: players,
        movementPointsRemaining: 4,
      );
      final MoveResult result =
          controller.moveActivePlayerTo(1, 2);
      expect(result, MoveResult.portalTravel);

      final GameState back = container.read(gameControllerProvider)!;
      expect(back.activePlayer.planet, PlanetType.hoth);
      expect(back.activePlayer.position, door);
      expect(back.activePlayer.returnPlanet, isNull);
    });

    test('case bonus : 1re visite → falconBonus + super attaque '
        'inratable ; 2e visite → falconBonusAgain sans effet', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await _newGame(controller);
      final Position door = created.falcon!.anchor;

      _placeNextTo(container, door);
      controller.moveActivePlayerTo(door.x, door.y);

      // Marche vers la case bonus (1,0) depuis (1,1).
      final GameState inside = container.read(gameControllerProvider)!;
      final List<Player> players = List<Player>.of(inside.players);
      players[inside.currentPlayerIndex] =
          inside.activePlayer.copyWith(position: const Position(1, 1));
      controller.state = inside.copyWith(
        players: players,
        movementPointsRemaining: 4,
      );
      final MoveResult first =
          controller.moveActivePlayerTo(1, 0);
      expect(first, MoveResult.falconBonus);
      GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.superAttackGuaranteed, isTrue);

      // Deuxième visite : message seul, aucun changement.
      final Player before = after.activePlayer;
      final List<Player> playersBack = List<Player>.of(after.players);
      playersBack[after.currentPlayerIndex] =
          before.copyWith(position: const Position(1, 1));
      controller.state = after.copyWith(
        players: playersBack,
        movementPointsRemaining: 4,
      );
      final MoveResult again =
          controller.moveActivePlayerTo(1, 0);
      expect(again, MoveResult.falconBonusAgain);
      after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.superAttackGuaranteed, isTrue);
      expect(after.activePlayer.patapucheAtkBonus, before.patapucheAtkBonus,
          reason: 'aucun autre effet');
    });
  });

  group('SUPER ATTAQUE inratable (Faucon)', () {
    test('superAttackGuaranteed → « Bim » à CHAQUE coup, recharge posée',
        () async {
      int hits = 0;
      for (int seed = 1; seed <= 40; seed++) {
        final ProviderContainer container = _container(seed);
        addTearDown(container.dispose);
        final GameController controller =
            container.read(gameControllerProvider.notifier);
        final GameState created = await _newGame(controller);

        // Wampa (500 PV) posé sur une cible voisine + joueur garanti.
        final Player active = created.activePlayer
            .copyWith(superAttackGuaranteed: true);
        final Position target = mapService
            .validMoveTargets(
                planet: created.currentPlanet,
                players: <Player>[active],
                activePlayerIndex: 0)
            .first;
        final List<Tile> tiles =
            List<Tile>.of(created.currentPlanet.tiles);
        tiles[target.y * created.currentPlanet.width + target.x] =
            tiles[target.y * created.currentPlanet.width + target.x]
                .copyWith(monster: Monster.forCard('Wampa', 3));
        controller.state = created.copyWith(
          players: <Player>[
            for (final Player p in created.players)
              p.id == active.id ? active : p,
          ],
          currentPlanet: created.currentPlanet.withTiles(tiles),
        );

        final CombatController combat =
            container.read(combatControllerProvider.notifier);
        combat.startMonsterCombat(target);
        combat.superAttack();

        final CombatSession session =
            container.read(combatControllerProvider)!;
        expect(session.superAttackUsed, isTrue, reason: 'seed $seed');
        expect(session.superAttackResult, 1,
            reason: 'seed $seed : JAMAIS de loupé avec le bonus');
        expect(session.lastDamage, inInclusiveRange(336, 411),
            reason: 'seed $seed : 3 × ATK ±10 %');
        expect(
            container
                .read(gameControllerProvider)!
                .players[created.currentPlayerIndex]
                .superAttackReadyTurn,
            created.turn + 5,
            reason: 'seed $seed : recharge inchangée');
        hits++;
      }
      expect(hits, 40);
    });
  });

  group('Sérialisation Faucon (sauvegarde)', () {
    test('round-trip : falcon et superAttackGuaranteed conservés ; '
        'ancienne sauvegarde sans les champs → null / false', () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      GameState state = await _newGame(controller);
      state = state.copyWith(
        falcon: state.falcon!.copyWith(visited: true),
        players: <Player>[
          state.players[0].copyWith(superAttackGuaranteed: true),
          state.players[1],
        ],
      );

      final GameState round = GameState.fromJson(state.toJson());
      expect(round.falcon!.visited, isTrue);
      expect(round.falcon!.anchor, state.falcon!.anchor);
      expect(round.players[0].superAttackGuaranteed, isTrue);

      // Ancienne sauvegarde : zone absente → null (les joueurs gardent
      // leurs propres champs, non touchés ici).
      final Map<String, dynamic> old = state.toJson()
        ..remove('falcon');
      final GameState legacy = GameState.fromJson(old);
      expect(legacy.falcon, isNull);

      // Ancien joueur : champ absent → bonus non acquis (défaut).
      final Map<String, dynamic> oldPlayer =
          state.players[0].toJson()..remove('superAttackGuaranteed');
      expect(Player.fromJson(oldPlayer).superAttackGuaranteed, isFalse);
    });

    test('gardes anti-crash : image, visuel et nom du Faucon déclarés',
        () {
      expect(planetImageId(PlanetType.faucon), 'faucon');
      expect(PlanetConstants.visualFor(PlanetType.faucon), isNotNull);
      expect(
          PlanetConstants.displayNames[PlanetType.faucon],
          'Faucon Millénium');
    });
  });
}
