import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/router/app_router.dart';
import 'package:star_wars_rpg/main.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';
import 'package:star_wars_rpg/widgets/board_widget.dart';
import 'package:star_wars_rpg/widgets/player_token.dart';

/// SaveService de test : aucun accès Hive réel.
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

/// Contrôleur figé sur un état de partie : permet de tester l'écran plateau
/// sans jouer (le vrai contrôleur démarre à null).
class _StubGameController extends GameController {
  static GameState? fixedState;

  @override
  GameState? build() => fixedState;
}

/// Partie figée : Luke au start A (joueur actif), Leia au start C opposé,
/// brouillard révélé uniquement autour de Luke (rayon 3).
GameState _fixedState() {
  final MapService mapService = MapService();
  final Planet planet =
      mapService.generateStartPlanet(PlanetType.alderande, seed: 7);
  final List<Position> starts = BoardConstants.startsForPlayerCount(2);
  final List<Player> players = <Player>[
    Player(
      id: 'p1',
      name: 'Luke Skywalker',
      faction: Faction.rebel,
      position: starts[0],
      planet: PlanetType.alderande,
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
    ),
    Player(
      id: 'p2',
      name: 'Princesse Leia',
      faction: Faction.rebel,
      position: starts[1],
      planet: PlanetType.alderande,
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
    ),
  ];
  final GameState state = GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'test',
    seed: 7,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.alderande,
    currentPlanet: planet,
    players: players,
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: 0,
    lastDiceRoll: null,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
  return state.copyWith(
    currentPlanet: mapService.revealFogAround(planet, players[0].position),
  );
}

Widget _app() => ProviderScope(
      overrides: <Override>[
        saveServiceProvider.overrideWithValue(_FakeSaveService()),
        gameControllerProvider.overrideWith(_StubGameController.new),
      ],
      child: const StarWarsRpgApp(),
    );

void main() {
  setUpAll(() {
    _StubGameController.fixedState = _fixedState();
  });

  Future<void> openBoard(WidgetTester tester) async {
    await tester.pumpWidget(_app());
    // Splash 1 s : on fait écoulé son Timer avant les assertions.
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/board');
    // Deux frames : la navigation GoRouter se concrétise à la frame suivante.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('le plateau affiche le HUD, le dé et la barre de boutons',
      (WidgetTester tester) async {
    await openBoard(tester);

    expect(find.text('Tour 1'), findsOneWidget);
    expect(find.text('Luke Skywalker'), findsOneWidget);
    expect(find.text('Lancer le dé'), findsOneWidget);
    expect(find.text('Personnage'), findsOneWidget);
    expect(find.text('Équipe'), findsOneWidget);
    expect(find.text('Inventaire'), findsOneWidget);
    expect(find.text('Joueurs'), findsOneWidget);
    expect(find.text('Vue Galaxie'), findsOneWidget);
    // Garde-fou régression : le plateau occupe réellement une largeur (un
    // enfant Stack non positionné peut faire s'effondrer sa largeur à 0).
    final Size boardSize = tester.getSize(find.byType(BoardWidget));
    expect(boardSize.width, greaterThan(600));
    expect(boardSize.height, greaterThan(300));
  });

  testWidgets(
      'le pion actif est rendu, les pions sur cases non découvertes '
      'sont masqués (GDD §3)', (WidgetTester tester) async {
    await openBoard(tester);

    // Luke, joueur actif (case découverte) : son pion est rendu — avec la
    // photo du personnage si l'image est déposée, sinon l'initiale (Sprint 6).
    expect(
      find.byWidgetPredicate((Widget widget) =>
          widget is PlayerToken && widget.player.name == 'Luke Skywalker'),
      findsOneWidget,
    );
    // Leia au coin opposé, hors du rayon révélé : pion masqué.
    expect(
      find.byWidgetPredicate((Widget widget) =>
          widget is PlayerToken && widget.player.name == 'Princesse Leia'),
      findsNothing,
    );
  });

  testWidgets('le bouton Vue Galaxie bascule vers Vue Joueur puis retour',
      (WidgetTester tester) async {
    await openBoard(tester);

    await tester.tap(find.text('Vue Galaxie'));
    await tester.pump();
    expect(find.text('Vue Joueur'), findsOneWidget);
    expect(find.text('Vue Galaxie'), findsNothing);

    await tester.tap(find.text('Vue Joueur'));
    await tester.pump();
    expect(find.text('Vue Galaxie'), findsOneWidget);
    expect(find.text('Vue Joueur'), findsNothing);
  });
}
