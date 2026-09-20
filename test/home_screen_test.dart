import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/main.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';

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

void main() {
  testWidgets("l'écran d'accueil affiche le menu principal (CDC §3)",
      (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        saveServiceProvider.overrideWithValue(_FakeSaveService()),
      ],
      child: const StarWarsRpgApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('STAR WARS'), findsOneWidget);
    expect(find.text('Nouvelle Partie'), findsOneWidget);
    expect(find.text('Reprendre Partie'), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Crédits'), findsOneWidget);
  });
}
