import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';

/// SaveService de test : aucune écriture Hive réelle.
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

ProviderContainer _container() => ProviderContainer(overrides: <Override>[
      saveServiceProvider.overrideWithValue(_FakeSaveService()),
    ]);

NewGameConfig _config(PlanetType planet) => NewGameConfig(
      mode: GameMode.chacunPourSoi,
      playerCount: 2,
      teamSize: 0,
      planetType: planet,
      characters: <CharacterDefinition>[
        CharacterConstants.characters[0],
        CharacterConstants.characters[2],
      ],
    );

int _visibleCount(Planet planet) =>
    planet.tiles.where((Tile tile) => tile.visible).length;

void main() {
  final MapService mapService = MapService();

  group('revealFogAround (GDD §3, CDC §6)', () {
    test('rayon 3 : carré de Chebyshev 7x7 autour du centre', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.coruscant, seed: 42);
      final Planet revealed =
          mapService.revealFogAround(planet, const Position(7, 7));

      expect(revealed.tileAt(7, 7).discovered, isTrue);
      // Diagonale exacte à distance 3 : révélée.
      expect(revealed.tileAt(4, 4).discovered, isTrue);
      expect(revealed.tileAt(10, 10).discovered, isTrue);
      // Distance 4 : hors du rayon.
      expect(revealed.tileAt(3, 4).discovered, isFalse);
      expect(revealed.tileAt(11, 10).discovered, isFalse);
    });

    test('discovered est cumulatif, visible suit le dernier centre', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.coruscant, seed: 42);
      Planet revealed = mapService.revealFogAround(planet, const Position(2, 2));
      expect(revealed.tileAt(2, 2).visible, isTrue);

      // Un second reveal plus loin : la découverte est conservée, la
      // visibilité suit le nouveau centre.
      revealed = mapService.revealFogAround(revealed, const Position(10, 10));
      expect(revealed.tileAt(2, 2).discovered, isTrue,
          reason: 'une découverte est conservée définitivement');
      expect(revealed.tileAt(2, 2).visible, isFalse,
          reason: 'hors du rayon du nouveau centre');
      expect(revealed.tileAt(10, 10).visible, isTrue);
    });

    test('rayon paramétrable', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.coruscant, seed: 42);
      final Planet revealed =
          mapService.revealFogAround(planet, const Position(7, 7), radius: 1);
      expect(revealed.tileAt(8, 7).discovered, isTrue);
      expect(revealed.tileAt(9, 7).discovered, isFalse);
    });

    test('la constante du rayon est bien 3 (décision du 07/09/2026)', () {
      expect(GameConstants.fogVisibleRadius, 3);
    });
  });

  group('Brouillard intégré à la partie (GDD §3, CDC §6)', () {
    test('à la création, seule la zone du premier joueur est découverte',
        () async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);

      final GameState state =
          await controller.createNewGame(_config(PlanetType.coruscant));

      final Position activeStart = state.activePlayer.position;
      expect(state.currentPlanet.tileAt(activeStart.x, activeStart.y).discovered,
          isTrue);
      expect(state.currentPlanet.tileAt(activeStart.x, activeStart.y).visible,
          isTrue);

      // Le second joueur démarre au coin opposé (distance 14 > rayon 3) :
      // sa zone est encore masquée.
      final int otherIndex = 1 - state.currentPlayerIndex;
      final Position otherStart = state.players[otherIndex].position;
      expect(state.currentPlanet.tileAt(otherStart.x, otherStart.y).discovered,
          isFalse);

      // Une seule zone visible : au plus un carré 7x7.
      expect(_visibleCount(state.currentPlanet),
          lessThanOrEqualTo(7 * 7));
    });

    test('après déplacement, la visibilité suit le joueur (invariant rayon 3)',
        () async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.hoth));

      controller.rollDice();
      final GameState rolled = container.read(gameControllerProvider)!;
      final List<Position> visibleBefore = <Position>[
        for (final Tile tile in rolled.currentPlanet.tiles)
          if (tile.visible) Position(tile.x, tile.y),
      ];
      expect(visibleBefore, isNotEmpty);

      final Position target = controller.validMoveTargets().first;
      controller.moveActivePlayerTo(target.x, target.y);
      final GameState moved = container.read(gameControllerProvider)!;

      // La case atteinte est visible ; l'ancienne zone reste découverte.
      expect(moved.currentPlanet.tileAt(target.x, target.y).visible, isTrue);
      for (final Position position in visibleBefore) {
        expect(moved.currentPlanet.tileAt(position.x, position.y).discovered,
            isTrue, reason: 'découverte conservée en $position');
      }
      // Invariant : toute case visible est à distance de Chebyshev ≤ 3 du
      // joueur actif.
      for (final Tile tile in moved.currentPlanet.tiles) {
        if (tile.visible) {
          expect(
            Position(tile.x, tile.y).chebyshevDistanceTo(target),
            lessThanOrEqualTo(GameConstants.fogVisibleRadius),
          );
        }
      }
    });

    test('en fin de tour, la visibilité passe au nouveau joueur actif',
        () async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created =
          await controller.createNewGame(_config(PlanetType.hoth));
      final Position previous = created.activePlayer.position;

      await controller.endTurn();
      final GameState state = container.read(gameControllerProvider)!;

      // L'ancien joueur actif est au coin opposé (distance 19 > 3) : sa zone
      // n'est plus visible mais reste découverte.
      expect(state.currentPlanet.tileAt(previous.x, previous.y).visible,
          isFalse);
      final Position now = state.activePlayer.position;
      expect(state.currentPlanet.tileAt(now.x, now.y).visible, isTrue);
      expect(state.currentPlanet.tileAt(now.x, now.y).discovered, isTrue);
    });
  });
}
