import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/armor.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/screens/board/board_screen.dart';
import 'package:star_wars_rpg/widgets/card_image.dart';
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

Player _player({Armor? armor, Armor? storedArmor}) => Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.jedi,
      position: const Position(0, 0),
      level: 4,
      xp: 0,
      attack: 800,
      hp: 1100,
      maxHp: 1100,
      armor: armor,
      storedArmor: storedArmor,
    );

GameState _state(Player player) => GameState(
      schemaVersion: GameState.currentSchemaVersion,
      gameId: 'dialog_test',
      seed: 42,
      mode: GameMode.chacunPourSoi,
      teamSize: 0,
      planetType: PlanetType.hoth,
      currentPlanet:
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42),
      players: <Player>[player],
      turn: 1,
      currentPlayerIndex: 0,
      gameTimeSeconds: 0,
      movementPointsRemaining: 0,
      lastDiceRoll: null,
      bosses: const [],
      portals: const [],
      status: GameStatus.inProgress,
    );

/// Retours playtest v3 : la ligne « Réserve : … » du dialog de trouvaille
/// n'affiche un bonus QUE si la réserve est réellement occupée (l'ancienne
/// coquille lisait la tenue ÉQUIPÉE : « — vide (+500 PV) »).
void main() {
  late ProviderContainer container;
  final Armor equipped =
      CardConstants.armors.firstWhere((Armor a) => a.hpBonus == 500);
  final Armor stored =
      CardConstants.armors.firstWhere((Armor a) => a.hpBonus == 200);

  setUp(() {
    container = ProviderContainer(overrides: <Override>[
      saveServiceProvider.overrideWithValue(_FakeSaveService()),
    ]);
  });

  tearDown(() => container.dispose());

  Future<void> pumpDialog(WidgetTester tester, Player player) async {
    container.read(gameControllerProvider.notifier).state = _state(player);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ItemFoundDialog(
              active: player,
              imageId: 'tenue_de_palpatine',
              name: 'Tenue de Palpatine',
              rarity: Rarity.legendaire,
              bonus: 1000,
              unit: 'PV',
              isWeapon: false,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('réserve vide : pas de bonus fantôme sur la ligne Réserve',
      (WidgetTester tester) async {
    await pumpDialog(tester, _player(armor: equipped));

    // La carte de l'objet est affichée en grand (retours playtest).
    expect(find.byType(CardImage), findsOneWidget);
    expect(find.textContaining('— vide'), findsOneWidget);
    expect(find.textContaining('— vide (+'), findsNothing,
        reason: 'l ancienne coquille collait le bonus de la tenue équipée '
            'à la réserve vide');
  });

  testWidgets('réserve occupée : bonus affiché et mention sera remplacée',
      (WidgetTester tester) async {
    await pumpDialog(tester, _player(armor: equipped, storedArmor: stored));

    expect(find.textContaining('Réserve : '), findsOneWidget);
    expect(find.textContaining('(sera remplacée)'), findsOneWidget);
    expect(find.textContaining('+${stored.hpBonus} PV'), findsOneWidget);
  });

  testWidgets('légendaire au niveau 4 : le niveau requis est affiché',
      (WidgetTester tester) async {
    await pumpDialog(tester, _player(armor: equipped));

    expect(find.textContaining('Niveau 5 requis'), findsOneWidget,
        reason: 'fini le vague « rareté non autorisée »');
  });
}
