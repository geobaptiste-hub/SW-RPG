import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/router/app_router.dart';
import 'package:star_wars_rpg/main.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/models/player.dart';
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

GameState _fixedState() {
  final MapService mapService = MapService();
  final Planet planet =
      mapService.generateStartPlanet(PlanetType.alderande, seed: 7);
  final Player player = Player(
    id: 'p1',
    name: 'Luke Skywalker',
    faction: Faction.jedi,
    position: BoardConstants.startPositions[0],
    level: 1,
    xp: 0,
    attack: 125,
    hp: 200,
    maxHp: 200,
  );
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'test',
    seed: 7,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.alderande,
    currentPlanet: planet,
    players: <Player>[player],
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: 2,
    lastDiceRoll: 2,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
}

class _StubGameController extends GameController {
  static GameState? fixedState;

  @override
  GameState? build() => fixedState;
}

class _StubCombatController extends CombatController {
  static CombatSession? fixedSession;

  @override
  CombatSession? build() => fixedSession;
}

Widget _app() => ProviderScope(
      overrides: <Override>[
        saveServiceProvider.overrideWithValue(_FakeSaveService()),
        gameControllerProvider.overrideWith(_StubGameController.new),
        combatControllerProvider.overrideWith(_StubCombatController.new),
      ],
      child: const StarWarsRpgApp(),
    );

CombatSession _session({bool finished = false}) {
  final Monster monster = Monster.forCard('Wampa', 3);
  return CombatSession(
    kind: CombatKind.monster,
    targetTile: const Position(1, 0),
    monster: monster,
    monsterHpRemaining: finished ? 0 : monster.hp,
    playerAttackTotal: 125,
    playerHp: 200,
    playerMaxHp: 200,
    attacksUsed: finished ? 6 : 0,
    finished: finished,
    victory: finished,
    xpGained: finished ? 50 : 0,
    damageTaken: finished ? 120 : 0,
  );
}

void main() {
  setUpAll(() {
    _StubGameController.fixedState = _fixedState();
  });

  testWidgets("l'écran Combat affiche les deux cartes et le dé (CDC §15)",
      (WidgetTester tester) async {
    _StubCombatController.fixedSession = _session();
    await tester.pumpWidget(_app());
    // Splash 1 s : on fait écoulé son Timer avant les assertions.
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/combat');
    await tester.pump();
    await tester.pump();

    expect(find.text('Combat — Wampa'), findsOneWidget);
    expect(find.text('Lancer le dé'), findsOneWidget);
    expect(find.text('ATK'), findsNWidgets(2));
    expect(find.text('PV'), findsWidgets,
        reason: 'une ligne PV par carte (joueur et monstre)');
    // Jauge d'XP du joueur (retours playtest v3).
    expect(find.textContaining('vers le niveau 2'), findsOneWidget);
  });

  testWidgets('le bouton Lancer le dé résout une attaque',
      (WidgetTester tester) async {
    _StubCombatController.fixedSession = _session();
    await tester.pumpWidget(_app());
    // Splash 1 s : on fait écoulé son Timer avant les assertions.
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/combat');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Lancer le dé'));
    await tester.pump();

    expect(find.textContaining('Dé : '), findsOneWidget);
    expect(find.textContaining('-'), findsWidgets,
        reason: 'les dégâts du coup sont affichés');
  });

  testWidgets('combat résolu : messages de victoire puis retour PAR CLIC '
      'au plateau (retours playtest — plus de retour automatique)',
      (WidgetTester tester) async {
    // Session vivante : le combat est mené jusqu'à la victoire à l'écran
    // (le monstre 500 PV tombe en 2 à 4 coups à 125/250 dégâts).
    _StubCombatController.fixedSession = _session();
    await tester.pumpWidget(_app());
    // Splash 1 s : on fait écoulé son Timer avant les assertions.
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/combat');
    await tester.pump();
    await tester.pump();

    int guard = 0;
    while (find.text('Victoire !').evaluate().isEmpty && guard < 10) {
      await tester.tap(find.text('Lancer le dé'));
      await tester.pump();
      guard++;
    }
    expect(find.text('Victoire !'), findsOneWidget);
    expect(find.textContaining('XP'), findsWidgets);

    // Le retour n'est plus automatique : le bouton reste affiché même après
    // le délai de lecture (le joueur garde le temps de voir son niveau).
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.text('Retour au plateau'), findsOneWidget);
    expect(find.text('Tour 1'), findsNothing,
        reason: 'toujours sur l écran de combat');

    // Clic → retour au plateau.
    await tester.tap(find.text('Retour au plateau'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tour 1'), findsOneWidget,
        reason: 'de retour sur le plateau');
  });

  testWidgets('SUPER ATTAQUE (10/10) : bouton entre « Lancer le dé » et '
      '« Fuir », résultat « Bim ! » ou « Loupé... »', (WidgetTester tester) async {
    _StubGameController.fixedState = _fixedState();
    _StubCombatController.fixedSession = _session();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/combat');
    await tester.pump();
    await tester.pump();

    // Les trois boutons, dans cet ordre vertical.
    final double rollTop =
        tester.getTopLeft(find.text('Lancer le dé')).dy;
    final double superTop =
        tester.getTopLeft(find.text('Super attaque')).dy;
    final double fleeTop = tester.getTopLeft(find.text('Fuir')).dy;
    expect(rollTop, lessThan(superTop));
    expect(superTop, lessThan(fleeTop));

    // Utilisation : un des deux messages s'affiche, le bouton passe à ✓.
    await tester.tap(find.text('Super attaque'));
    await tester.pump();
    expect(
      find.text('💥 Bim !').evaluate().isNotEmpty ||
          find.text('💨 Loupé...').evaluate().isNotEmpty,
      isTrue,
      reason: 'la super attaque réussit (« Bim ! ») ou échoue (« Loupé... »)',
    );
    expect(find.text('Super attaque ✓'), findsOneWidget,
        reason: 'une seule utilisation par combat');
  });

  testWidgets('SUPER ATTAQUE en recharge : bouton grisé + message',
      (WidgetTester tester) async {
    final GameState state = _fixedState();
    state.players[0] =
        state.players[0].copyWith(superAttackReadyTurn: 9);
    _StubGameController.fixedState = state;
    _StubCombatController.fixedSession = _session();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/combat');
    await tester.pump();
    await tester.pump();

    // Grisée : le libellé porte la recharge restante (8 tours).
    await tester.tap(find.text('Super attaque (8)'));
    await tester.pump();
    expect(find.textContaining('réutilisable dans 8 tours'), findsOneWidget,
        reason: 'message « En recharge » au tap sur le bouton grisé');
  });

  testWidgets('popup « -N » : les dégâts infligés s\'affichent sur la cible',
      (WidgetTester tester) async {
    _StubGameController.fixedState = _fixedState();
    _StubCombatController.fixedSession = _session();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 2));
    appRouter.go('/combat');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Lancer le dé'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Le popup est un Text exact « -N » (le panneau central affiche « -N PV »).
    expect(
      find
          .byWidgetPredicate(
              (Widget w) => w is Text && RegExp(r'^-\d+$').hasMatch(w.data ?? ''))
          .evaluate()
          .isNotEmpty,
      isTrue,
      reason: 'le popup « -N » est visible ~0,55 s après l\'attaque',
    );
  });
}
