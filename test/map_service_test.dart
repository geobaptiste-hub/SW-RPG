import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart' show GamePhase;
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/map_service.dart';

void main() {
  final MapService mapService = MapService();

  Planet generate({int seed = 42}) =>
      mapService.generateStartPlanet(PlanetType.tatooine, seed: seed);

  group('Génération du plateau principal (GDD §3, CDC §5)', () {
    test('grille 15x15 → 225 cases', () {
      final Planet planet = generate();
      expect(planet.width, BoardConstants.gridWidth);
      expect(planet.height, BoardConstants.gridHeight);
      expect(planet.tiles.length, BoardConstants.totalTiles);
    });

    test('168 cases jouables et 57 bloquées', () {
      final Planet planet = generate();
      expect(planet.playableTileCount, BoardConstants.playableTiles);
      expect(planet.blockedTileCount, BoardConstants.blockedTiles);
    });

    test('toutes les cases jouables sont connectées (parcours indépendant)',
        () {
      final Planet planet = generate();
      final Tile first = planet.tiles.firstWhere((Tile tile) => tile.walkable);

      final Set<Position> reached = <Position>{Position(first.x, first.y)};
      final List<Position> queue = <Position>[Position(first.x, first.y)];
      while (queue.isNotEmpty) {
        final Position current = queue.removeLast();
        for (final Position delta in const [
          Position(1, 0),
          Position(-1, 0),
          Position(0, 1),
          Position(0, -1),
        ]) {
          final Position next =
              Position(current.x + delta.x, current.y + delta.y);
          if (reached.contains(next)) continue;
          if (!planet.isWalkableAt(next.x, next.y)) continue;
          reached.add(next);
          queue.add(next);
        }
      }
      expect(reached.length, BoardConstants.playableTiles,
          reason: 'Toutes les cases jouables doivent être connectées');
    });

    test('génération déterministe pour un même seed', () {
      final Planet a = generate(seed: 7);
      final Planet b = generate(seed: 7);
      expect(
        a.tiles.map((Tile t) => t.walkable).join(),
        b.tiles.map((Tile t) => t.walkable).join(),
      );
    });

    test('les 8 départs fixes sont des cases jouables', () {
      final Planet planet = generate();
      for (final Position start in BoardConstants.startPositions) {
        expect(planet.isWalkableAt(start.x, start.y), isTrue,
            reason: 'Le départ (${start.x}, ${start.y}) doit être jouable');
      }
    });

    test('attribution des départs selon le nombre de joueurs (CDC §5)', () {
      expect(BoardConstants.startsForPlayerCount(2).length, 2);
      expect(BoardConstants.startsForPlayerCount(3).length, 3);
      expect(BoardConstants.startsForPlayerCount(4).length, 4);
      expect(BoardConstants.startsForPlayerCount(8).length, 8);
      // 2 joueurs : coins opposés (Start A et Start C).
      expect(BoardConstants.startsForPlayerCount(2),
          const [Position(0, 0), Position(19, 19)]);
    });
  });

  group('Cibles de déplacement (GDD §6, CDC §7)', () {
    test('voisins orthogonaux jouables uniquement, cases occupées exclues',
        () {
      final Planet planet = generate();
      // Une case jouable avec au moins 3 voisins jouables.
      Position spot = const Position(0, 0);
      for (final Tile tile in planet.tiles) {
        if (!tile.walkable) continue;
        int walkableNeighbors = 0;
        for (final Position delta in const [
          Position(1, 0),
          Position(-1, 0),
          Position(0, 1),
          Position(0, -1),
        ]) {
          if (planet.isWalkableAt(tile.x + delta.x, tile.y + delta.y)) {
            walkableNeighbors++;
          }
        }
        if (walkableNeighbors >= 3) {
          spot = Position(tile.x, tile.y);
          break;
        }
      }

      final Player active = _player('p1', spot);
      final Player other = _player('p2', Position(spot.x + 1, spot.y));

      final List<Position> targets = mapService.validMoveTargets(
        planet: planet,
        players: <Player>[active, other],
        activePlayerIndex: 0,
      );

      for (final Position target in targets) {
        expect(target.manhattanDistanceTo(spot), 1,
            reason: 'Seuls les voisins orthogonaux sont accessibles');
        expect(planet.isWalkableAt(target.x, target.y), isTrue);
      }
      if (planet.isWalkableAt(spot.x + 1, spot.y)) {
        // Sprint 3 : la case occupée par un adversaire est désormais
        // ciblable (combat entre joueurs — GDD §13).
        expect(targets.contains(Position(spot.x + 1, spot.y)), isTrue,
            reason: 'Entrer sur la case dun adversaire déclenche un combat');
        expect(targets.length, lessThanOrEqualTo(3));
      }
    });
  });

  group('Placement des cases de soin (fix 20/09)', () {
    test('populate : jamais deux soins sur des cases voisines', () {
      final Planet planet = generate(seed: 7);
      final Planet revealed = mapService.revealFogAround(
        planet,
        const Position(10, 10),
        radius: 30,
      );
      final populate = mapService.populateNewlyDiscoveredTiles(
        before: planet,
        after: revealed,
        phase: GamePhase.fin,
        rng: Random(5),
        occupied: const <Position>{},
        existingPortals: const [],
        bossUnlocked: false,
      );

      int healCount = 0;
      for (final Tile tile in populate.planet.tiles) {
        if (!tile.healSite) continue;
        healCount++;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final int nx = tile.x + dx;
            final int ny = tile.y + dy;
            if (nx < 0 ||
                ny < 0 ||
                nx >= planet.width ||
                ny >= planet.height) {
              continue;
            }
            expect(
              populate.planet.tileAt(nx, ny).healSite,
              isFalse,
              reason: 'deux soins voisins interdits : '
                  '(${tile.x},${tile.y}) et ($nx,$ny)',
            );
          }
        }
      }
      expect(healCount, greaterThan(0),
          reason: 'en phase fin sur tout le plateau, au moins un soin sort');
    });
  });
}

Player _player(String id, Position position) => Player(
      id: id,
      name: id,
      faction: Faction.jedi,
      position: position,
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
    );
