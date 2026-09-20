import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';

/// SaveService de test : aucune écriture Hive réelle (path_provider est
/// indisponible en tests unitaires). Mémorise simplement la dernière partie.
class _FakeSaveService extends SaveService {
  int saveCount = 0;
  GameState? lastSaved;

  @override
  Future<bool> hasSave() async => lastSaved != null;

  @override
  Future<void> save(GameState state) async {
    saveCount++;
    lastSaved = state;
  }

  @override
  Future<GameState?> load() async => lastSaved;

  @override
  Future<void> deleteSave() async {
    lastSaved = null;
  }
}

ProviderContainer _container(_FakeSaveService saves) => ProviderContainer(
      overrides: <Override>[saveServiceProvider.overrideWithValue(saves)],
    );

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

void main() {
  late _FakeSaveService saves;
  late ProviderContainer container;

  setUp(() {
    saves = _FakeSaveService();
    container = _container(saves);
  });

  tearDown(() => container.dispose());

  group('Création de partie (CDC §4)', () {
    test('place les joueurs sur les départs, applique le brouillard, sauvegarde',
        () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);

      final GameState state =
          await controller.createNewGame(_config(PlanetType.coruscant));

      expect(state.players.length, 2);
      expect(state.turn, 1);
      expect(state.currentPlanet.playableTileCount, 300);
      // Départs attribués selon le nombre de joueurs : coins opposés A et C.
      expect(state.players[0].position, BoardConstants.startPositions[0]);
      expect(state.players[1].position, BoardConstants.startPositions[2]);
      // Brouillard de guerre : la case du premier joueur est révélée.
      final Position start = state.activePlayer.position;
      expect(state.currentPlanet.tileAt(start.x, start.y).discovered, isTrue);
      expect(saves.saveCount, 1);
    });
  });

  group('Dé (GDD §6)', () {
    test('valeur entre 1 et 6, égale aux points de déplacement restants',
        () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.endor));

      for (int i = 0; i < 20; i++) {
        await controller.endTurn(); // nouveau tour → nouveau lancer possible.
        controller.rollDice();
        final GameState state = container.read(gameControllerProvider)!;
        expect(state.lastDiceRoll, inInclusiveRange(1, 6));
        expect(state.movementPointsRemaining, state.lastDiceRoll);
      }
    });

    test('un second lancer pendant le tour est ignoré', () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.endor));

      controller.rollDice();
      final int firstRoll =
          container.read(gameControllerProvider)!.lastDiceRoll!;
      controller.rollDice();
      expect(container.read(gameControllerProvider)!.lastDiceRoll, firstRoll);
    });
  });

  group('Déplacement (GDD §6, CDC §7)', () {
    test('une case voisine valide déplace le joueur et décrémente le compteur',
        () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.hoth));

      controller.rollDice();
      final GameState rolled = container.read(gameControllerProvider)!;
      expect(rolled.movementPointsRemaining, greaterThan(0));

      final List<Position> targets = controller.validMoveTargets();
      expect(targets, isNotEmpty,
          reason: 'Un départ connecté a au moins un voisin libre');
      final Position target = targets.first;
      controller.moveActivePlayerTo(target.x, target.y);

      final GameState moved = container.read(gameControllerProvider)!;
      expect(moved.activePlayer.position, target);
      expect(
          moved.movementPointsRemaining, rolled.movementPointsRemaining - 1);
      // Le brouillard se révèle sur la case atteinte (GDD §3).
      expect(moved.currentPlanet.tileAt(target.x, target.y).discovered, isTrue);
    });

    test('une cible hors de portée est refusée', () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.hoth));

      controller.rollDice();
      final GameState before = container.read(gameControllerProvider)!;

      controller.moveActivePlayerTo(-1, -1); // hors grille → jamais une cible.

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.position, before.activePlayer.position);
      expect(after.movementPointsRemaining, before.movementPointsRemaining);
    });
  });

  group('Fin de tour (CDC §2)', () {
    test('passe au joueur suivant, réinitialise le dé, incrémente le tour',
        () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created =
          await controller.createNewGame(_config(PlanetType.hoth));
      final int firstIndex = created.currentPlayerIndex;

      await controller.endTurn();
      GameState state = container.read(gameControllerProvider)!;
      expect(state.currentPlayerIndex, (firstIndex + 1) % 2);
      expect(state.turn, firstIndex == 0 ? 1 : 2, reason: 'incrémenté seulement si retour au joueur 1');
      expect(state.lastDiceRoll, isNull);
      expect(state.movementPointsRemaining, 0);

      await controller.endTurn();
      state = container.read(gameControllerProvider)!;
      expect(state.currentPlayerIndex, firstIndex);
      expect(state.turn, 2, reason: 'La main est revenue au premier joueur');
      expect(saves.saveCount, 3, reason: 'création + 2 fins de tour');
    });
  });

  group('Chrono et sortie', () {
    test('tickGameTime incrémente le temps de jeu', () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.hoth));
      final int before =
          container.read(gameControllerProvider)!.gameTimeSeconds;

      controller.tickGameTime();

      expect(container.read(gameControllerProvider)!.gameTimeSeconds, before + 1);
    });

    test('exitGame réinitialise létat en conservant la sauvegarde', () async {
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      await controller.createNewGame(_config(PlanetType.hoth));

      controller.exitGame();

      expect(container.read(gameControllerProvider), isNull);
      expect(saves.lastSaved, isNotNull,
          reason: 'Quitter conserve la dernière sauvegarde');
    });
  });
}
