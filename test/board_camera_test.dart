import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/widgets/board_camera.dart';

void main() {
  final MapService mapService = MapService();

  Planet planet() =>
      mapService.generateStartPlanet(PlanetType.endor, seed: 42);

  List<Player> players() => <Player>[
        _player('p1', const Position(0, 0)),
        _player('p2', const Position(14, 14)),
      ];

  const Size viewport = Size(800, 600);

  group('BoardCamera — vue Galaxie', () {
    test('ajustement minimal : le plateau entier tient dans le viewport', () {
      final Matrix4 m = BoardCamera.matrixFor(
        viewport: viewport,
        galaxyView: true,
        planet: planet(),
        players: players(),
        activePlayerIndex: 0,
      );

      final double boardSize =
          BoardConstants.gridWidth * BoardConstants.tileExtent; // 840
      final double expectedScale = min(800 / boardSize, 600 / boardSize);
      expect(m.storage[0], closeTo(expectedScale, 0.0001));
      expect(m.storage[5], closeTo(expectedScale, 0.0001));
      // Centrage : marges égales gauche/droite et haut/bas.
      expect(m.storage[12],
          closeTo((800 - boardSize * expectedScale) / 2, 0.0001));
      expect(m.storage[13],
          closeTo((600 - boardSize * expectedScale) / 2, 0.0001));
    });
  });

  group('BoardCamera — vue joueur', () {
    test('zoom fixe et pion actif centré', () {
      final Matrix4 m = BoardCamera.matrixFor(
        viewport: viewport,
        galaxyView: false,
        planet: planet(),
        players: players(),
        activePlayerIndex: 1, // pion au coin bas-droit (14, 14)
      );

      final double scale = BoardConstants.followZoom;
      expect(m.storage[0], scale);
      expect(m.storage[5], scale);
      final double px = (14 + 0.5) * BoardConstants.tileExtent * scale;
      final double py = (14 + 0.5) * BoardConstants.tileExtent * scale;
      expect(m.storage[12], closeTo(viewport.width / 2 - px, 0.0001));
      expect(m.storage[13], closeTo(viewport.height / 2 - py, 0.0001));
    });
  });

  group('BoardCamera — cas limites', () {
    test('viewport vide : matrice identité, aucune valeur non finie', () {
      final Matrix4 m = BoardCamera.matrixFor(
        viewport: Size.zero,
        galaxyView: true,
        planet: planet(),
        players: players(),
        activePlayerIndex: 0,
      );
      expect(m.storage.every((double value) => value.isFinite), isTrue);
      expect(m, Matrix4.identity());
    });

    test('aucune valeur non finie pour un viewport normal', () {
      for (final bool galaxy in <bool>[true, false]) {
        final Matrix4 m = BoardCamera.matrixFor(
          viewport: viewport,
          galaxyView: galaxy,
          planet: planet(),
          players: players(),
          activePlayerIndex: 0,
        );
        expect(m.storage.every((double value) => value.isFinite), isTrue,
            reason: 'galaxyView: $galaxy');
      }
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
