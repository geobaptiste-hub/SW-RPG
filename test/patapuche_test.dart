import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/monster.dart';
import 'package:star_wars_rpg/models/patapuche.dart';
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

Player _player({
  Position position = const Position(0, 0),
  Faction faction = Faction.jedi,
  int level = 1,
  int xp = 0,
  int hp = 500,
  int maxHp = 500,
  int index = 0,
}) {
  final int lvl = level.clamp(1, 6);
  return Player(
    id: 'p${index + 1}',
    name: 'Joueur ${index + 1}',
    faction: faction,
    position: position,
    planet: PlanetType.hoth,
    level: lvl,
    xp: xp,
    attack: GameConstants.attackForLevel(lvl),
    hp: hp,
    maxHp: maxHp,
  );
}

GameState _state({
  required Planet planet,
  required List<Player> players,
  Patapuche? patapuche,
  int movement = 1,
}) {
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'patapuche_test',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.hoth,
    currentPlanet: planet,
    planets: <PlanetType, Planet>{PlanetType.hoth: planet},
    players: players,
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: movement,
    lastDiceRoll: movement == 0 ? null : movement,
    bosses: const [],
    portals: const [],
    patapuche: patapuche,
    status: GameStatus.inProgress,
  );
}

/// Trouve une case intérieure jouable entourée de cases jouables (pour y
/// poser un décor ou une créature sans effet de bord de grille).
Position _findOpenSpot(Planet planet) {
  for (final Tile tile in planet.tiles) {
    if (!tile.walkable) continue;
    final Position p = Position(tile.x, tile.y);
    if (p.x < 2 || p.y < 2) continue;
    if (p.x > planet.width - 3 || p.y > planet.height - 3) continue;
    int libres = 0;
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        if (planet.isWalkableAt(p.x + dx, p.y + dy)) libres++;
      }
    }
    if (libres >= 24) return p; // quasi tout l'anneau 5x5 est jouable
  }
  return const Position(10, 10);
}

void main() {
  group('Apparition de Patapuche (retours playtest 20/09)', () {
    test('au premier joueur niveau 2 : spawn sur case valide + annonce',
        () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(level: 2, xp: 250);
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: planet,
        players: <Player>[player],
      );

      // ignore: avoid_print
      print('DEBUG anchor=${mapService.patapucheAnchorFor(42)}');
      controller.endTurn();

      final GameState after = container.read(gameControllerProvider)!;
      // ignore: avoid_print
      print('DEBUG après endTurn: patapuche=${after.patapuche} '
          'level=${after.players[0].level} '
          'status=${after.status}');
      expect(after.patapuche, isNotNull,
          reason: 'Patapuche apparaît dès qu\'un joueur atteint le N2');
      expect(after.patapuche!.planet, PlanetType.hoth);
      final Tile tile = after.currentPlanet.tileAt(
          after.patapuche!.position.x, after.patapuche!.position.y);
      expect(tile.walkable, isTrue, reason: 'case jouable');
      expect(
        BoardConstants.startPositions.contains(after.patapuche!.position),
        isFalse,
        reason: 'jamais sur un départ',
      );
      expect(container.read(gameControllerProvider.notifier).patapuchePending,
          isTrue, reason: 'annonce au plateau');
    });

    test('une seule Patapuche par partie (déjà présente)', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = _player(level: 2, xp: 250);
      final GameState state = _state(
        planet: planet,
        players: <Player>[player],
        patapuche: Patapuche(
            planet: PlanetType.hoth, position: const Position(6, 6)),
      );
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;

      controller.endTurn();

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.patapuche, isNotNull,
          reason: 'une seule Patapuche par partie');
      expect(after.patapuche!.position, isNot(const Position(6, 6)),
          reason: 'elle se déplace à chaque fin de tour');
    });
  });

  group('Apparition au premier N2 — depuis une vraie partie (fix 28/09)', () {
    test('createNewGame ne crée PAS Patapuche : elle attend le premier N2',
        () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await controller.createNewGame(
          NewGameConfig(
        mode: GameMode.chacunPourSoi,
        playerCount: 2,
        teamSize: 0,
        planetType: PlanetType.hoth,
        characters: <CharacterDefinition>[
          CharacterConstants.characters[0],
          CharacterConstants.characters[2],
        ],
      ));

      // Fix 28/09 : Patapuche était créée dès le départ → _maybeSpawn
      // partait aussitôt (patapuche != null) et l'annonce « Patapuche
      // apparaît » ne s'affichait JAMAIS.
      expect(created.patapuche, isNull,
          reason: 'Patapuche n’existe pas avant le premier niveau 2');
      expect(controller.patapuchePending, isFalse);
      // Sa case est malgré tout réservée : l'ancre seedée est jouable et
      // sans contenu, prête à l'accueillir.
      final Position? anchor = mapService.patapucheAnchorFor(created.seed);
      expect(anchor, isNotNull);
      final Tile tile =
          created.currentPlanet.tileAt(anchor!.x, anchor.y);
      expect(tile.walkable, isTrue, reason: 'l’ancre est protégée du blocage');
      expect(tile.monster, isNull);
      expect(tile.ally, isNull);
      expect(tile.weapon, isNull);
      expect(tile.armor, isNull);
    });

    test('victoire de monstre qui fait passer N2 : spawn + annonce au plateau',
        () async {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await controller.createNewGame(
          NewGameConfig(
        mode: GameMode.chacunPourSoi,
        playerCount: 2,
        teamSize: 0,
        planetType: PlanetType.hoth,
        characters: <CharacterDefinition>[
          CharacterConstants.characters[0],
          CharacterConstants.characters[2],
        ],
      ));

      // Le joueur actif est à 5 XP du palier N2 (200 XP).
      final List<Player> players = List<Player>.of(created.players);
      players[created.currentPlayerIndex] =
          created.activePlayer.copyWith(xp: 195);
      controller.state = created.copyWith(players: players);

      // Victoire sur un monstre N1 (+10 XP) → 205 XP → niveau 2.
      controller.applyMonsterVictory(
        tile: created.activePlayer.position,
        xp: 10,
        playerHp: created.activePlayer.hp,
      );

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[after.currentPlayerIndex].level, 2,
          reason: 'le combat a bien fait passer le joueur niveau 2');
      expect(after.patapuche, isNotNull,
          reason: 'Patapuche apparaît au premier niveau 2');
      expect(after.patapuche!.planet, PlanetType.hoth);
      expect(after.patapuche!.position,
          mapService.patapucheAnchorFor(created.seed),
          reason: 'elle apparaît sur l’ancre seedée');
      expect(controller.patapuchePending, isTrue,
          reason: 'l’annonce « Patapuche apparaît » est déclenchée '
              '(dialog au retour plateau)');
    });

    test('l’ancre est protégée du blocage pour toute graine (constante '
        'partagée génération/accesseur)', () {
      for (final int seed in <int>[1, 7, 42, 123, 999, 2026, 0x7FFFFFFF]) {
        final Planet planet =
            mapService.generateStartPlanet(PlanetType.hoth, seed: seed);
        final Position? anchor = mapService.patapucheAnchorFor(seed);
        expect(anchor, isNotNull, reason: 'seed $seed');
        final Tile tile = planet.tileAt(anchor!.x, anchor.y);
        expect(tile.walkable, isTrue,
            reason: 'seed $seed : l’ancre renvoyée doit être la case '
                'protégée pendant la génération');
      }
    });
  });

  group('Don de Patapuche (retours playtest 20/09)', () {
    test('marcher sur elle : +100 ATK / +100 PV, une fois par joueur', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Position pos = _findOpenSpot(planet);
      final Position from = mapService
          .neighborPositions(pos, planet)
          .firstWhere((Position p) => planet.isWalkableAt(p.x, p.y));
      final Player player = _player(position: from, hp: 500, maxHp: 500);
      final GameState state = _state(
        planet: planet,
        players: <Player>[player],
        patapuche: Patapuche(planet: PlanetType.hoth, position: pos),
      );
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;

      final MoveResult result =
          controller.moveActivePlayerTo(pos.x, pos.y);
      expect(result, MoveResult.patapuche);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[0].patapucheAtkBonus, 100);
      expect(after.players[0].patapucheHpBonus, 100);
      expect(after.players[0].hp, greaterThanOrEqualTo(600),
          reason: '+100 PV actuels (500 de base + le don)');
      expect(after.patapuche!.claimedBy, contains('p1'));
    });

    test('re-marcher dessus ne cumule pas le don (une fois par joueur)',
        () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Position pos = _findOpenSpot(planet);
      final Player player = _player(
        position: pos,
        hp: 500,
        maxHp: 500,
      ).copyWith(
        patapucheAtkBonusDelta: 100,
        patapucheHpBonusDelta: 100,
      );
      final GameState state = _state(
        planet: planet,
        players: <Player>[player],
        patapuche: Patapuche(
          planet: PlanetType.hoth,
          position: pos,
        ),
      );
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;

      final MoveResult result =
          controller.moveActivePlayerTo(pos.x, pos.y);

      expect(result, MoveResult.moved,
          reason: 'déjà reçu par CE joueur : plus rien à gagner');
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[0].patapucheAtkBonus, 100,
          reason: 'pas de cumul : le don reste à +100 (et non +200)');
    });
  });

  group('Déplacement de Patapuche (fin de tour)', () {
    test('elle se déplace d\'une case valide (jamais sur un monstre)', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Position depart = _findOpenSpot(planet);
      final Player player = _player(position: const Position(0, 0));
      final GameState state = _state(
        planet: planet,
        players: <Player>[player],
        patapuche: Patapuche(planet: PlanetType.hoth, position: depart),
      );
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;

      controller.endTurn();

      final GameState after = container.read(gameControllerProvider)!;
      final Position arrivee = after.patapuche!.position;
      // ignore: avoid_print
      print('DEBUG move: depart=$depart arrivee=$arrivee '
          'monstre=${after.currentPlanet.tileAt(arrivee.x, arrivee.y).monster != null} '
          'arme=${after.currentPlanet.tileAt(arrivee.x, arrivee.y).weapon != null}');
      expect(arrivee, isNot(depart),
          reason: 'elle se déplace à chaque fin de tour (case libre '
              'disponible autour)');
      final Tile tile = after.currentPlanet.tileAt(arrivee.x, arrivee.y);
      expect(tile.walkable, isTrue);
      expect(tile.monster, isNull,
          reason: 'elle évite les cases monstres');
      expect(tile.healSite, isFalse);
      expect(tile.ally, isNull);
      expect(tile.weapon, isNull);
      expect(tile.armor, isNull);
    });

    test('bloquée par des monstres : elle SAUTE à la case libre la plus '
        'proche', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      // Entoure Patapuche (6,6) de 8 monstres : l'anneau 1 est bloqué.
      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final int index = (6 + dy) * planet.width + (6 + dx);
          if (dx == 0 && dy == 0) continue;
          tiles[index] =
              tiles[index].copyWith(monster: Monster.forCard('Wampa', 3));
        }
      }
      final Planet crafted = planet.withTiles(tiles);
      final Player player = _player(position: const Position(0, 0));
      final GameState state = _state(
        planet: crafted,
        players: <Player>[player],
        patapuche: Patapuche(
            planet: PlanetType.hoth, position: const Position(6, 6)),
      );
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = state;

      controller.endTurn();

      final GameState after = container.read(gameControllerProvider)!;
      final Position arrivee = after.patapuche!.position;
      expect(
        arrivee.chebyshevDistanceTo(const Position(6, 6)),
        2,
        reason: 'elle SAUTE par-dessus les monstres : la case libre la '
            'plus proche est sur l\'anneau 2',
      );
      final Tile tile =
          after.currentPlanet.tileAt(arrivee.x, arrivee.y);
      expect(tile.monster, isNull, reason: 'jamais sur un monstre');
    });
  });
}
