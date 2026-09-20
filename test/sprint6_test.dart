import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/utils/slug.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/image_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';
import 'package:star_wars_rpg/services/settings_service.dart';
import 'package:star_wars_rpg/widgets/card_image.dart';

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

/// PNG minimal valide (1 x 1 pixel transparent) pour tester la résolution
/// de fichiers sans dépendance d'encodage.
final List<int> _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  group('slugify (convention images-cartes.md)', () {
    test('exemples de noms de cartes', () {
      expect(slugify('Ki-Adi-Mundi'), 'ki_adi_mundi');
      expect(slugify("L'empereur"), 'l_empereur');
      expect(slugify('Chirrut Îmwe'), 'chirrut_imwe');
      expect(slugify('IG-88'), 'ig_88');
      expect(slugify('Général Grievous'), 'general_grievous');
      expect(slugify('Droïde sonde'), 'droide_sonde');
      expect(slugify('Hommes des sables'), 'hommes_des_sables');
      expect(slugify('  Padawan  '), 'padawan');
    });
  });

  group('ImageService (images déposées sans recompilation)', () {
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('swrpg_images_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('résout le fichier déposé, renvoie null sinon (cache)', () {
      final File image = File(
          '${tempDir.path}/assets/images/monsters/wampa.png');
      image.createSync(recursive: true);
      image.writeAsBytesSync(_tinyPng);

      final ImageService service = ImageService(roots: <String>[
        Directory.systemTemp.path,
        tempDir.path,
      ]);
      final File? resolved = service.resolveFile('monsters', 'wampa');
      expect(resolved, isNotNull);
      expect(resolved!.readAsBytesSync(), _tinyPng);

      // Absente → null (le widget affichera le placeholder).
      expect(service.resolveFile('monsters', 'sarlacc'), isNull);
      expect(service.resolveFile('monsters', 'wampa'), isNotNull,
          reason: 'le cache conserve la résolution positive');
    });

    testWidgets('CardImage rectangulaire : rend Image.file pour un fichier '
        'déposé, placeholder sinon', (WidgetTester tester) async {
      final Directory tempDir =
          Directory.systemTemp.createTempSync('swrpg_cardimage_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final File image =
          File('${tempDir.path}/assets/images/weapons/sabre_luke.png');
      image.createSync(recursive: true);
      image.writeAsBytesSync(_tinyPng);

      final ProviderContainer imageContainer = ProviderContainer(
        overrides: <Override>[
          imageServiceProvider.overrideWithValue(
              ImageService(roots: <String>[tempDir.path])),
        ],
      );
      addTearDown(imageContainer.dispose);

      // Fichier présent → Image.file rendu dans la boîte rectangulaire.
      await tester.pumpWidget(UncontrolledProviderScope(
        container: imageContainer,
        child: const MaterialApp(
          home: Scaffold(
            body: CardImage(
              category: 'weapons',
              id: 'sabre_luke',
              width: 220,
              height: 340,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);

      // Fichier absent → placeholder (aucune image).
      await tester.pumpWidget(UncontrolledProviderScope(
        container: imageContainer,
        child: const MaterialApp(
          home: Scaffold(
            body: CardImage(
              category: 'weapons',
              id: 'arme_inconnue',
              width: 220,
              height: 340,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });
  });

  group('Journal de partie (GDD §14 — Sprint 6)', () {
    test('montée de niveau inscrite au journal après une victoire', () {
      final ProviderContainer container = _container(9);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final Planet planet =
          MapService().generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = Player(
        id: 'p1',
        name: 'Luke Skywalker',
        faction: Faction.jedi,
        position: const Position(0, 0),
        level: 1,
        xp: 150, // + 50 XP du Wampa L3 → palier 200 → niveau 2.
        attack: 125,
        hp: 10000,
        maxHp: 10000,
      );
      final Position target = MapService()
          .validMoveTargets(planet: planet, players: <Player>[player],
              activePlayerIndex: 0)
          .first;
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      final int index = target.y * planet.width + target.x;
      tiles[index] =
          tiles[index].copyWith(monster: Monster.forCard('Wampa', 3));
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'sprint6',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet: planet.withTiles(tiles),
        players: <Player>[player],
        turn: 3,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 3,
        lastDiceRoll: 3,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );

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

      expect(controller.gameLogVersion.value, greaterThan(0));
      expect(
        controller.gameLog.join('\n'),
        contains('⬆ Luke Skywalker atteint le niveau 2 !'),
        reason: 'la montée de niveau est journalisée (GDD §14)',
      );
      expect(controller.gameLog.first, startsWith('Tour 3 —'),
          reason: 'les entrées sont horodatées au tour courant');
    });

    test('exitGame remet le journal à zéro', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.log('événement de test');
      expect(controller.gameLog, isNotEmpty);
      controller.exitGame();
      expect(controller.gameLog, isEmpty);
    });
  });

  group('Réglages persistés (Sprint 6)', () {
    late Directory tempDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('swrpg_settings_test');
      Hive.init(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    test('son : vrai par défaut, persisté après bascule', () async {
      final SettingsService service = SettingsService();
      expect(await service.loadSoundEnabled(), isTrue);
      await service.setSoundEnabled(false);
      expect(await service.loadSoundEnabled(), isFalse);
      await service.setSoundEnabled(true);
      expect(await service.loadSoundEnabled(), isTrue);
    });
  });
}
