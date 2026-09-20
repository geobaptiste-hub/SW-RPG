import 'dart:math';

import 'package:flutter/material.dart';

import '../core/constants/board_constants.dart';
import '../models/planet.dart';
import '../models/player.dart';

/// Math de caméra du plateau (CDC §5) :
///  - vue joueur : zoom fixe, centrée sur le pion du joueur actif ;
///  - vue Galaxie : dézoom global cadrant le plateau entier.
///
/// Fonctions pures, sans widget : testables unitairement
/// (Sprint 2 — amélioration de la navigation).
class BoardCamera {
  BoardCamera._();

  /// Matrice de transformation de l'InteractiveViewer pour un viewport
  /// de [viewport].
  ///
  /// Un viewport vide (premier layout non réalisé) renvoie la matrice
  /// identité plutôt qu'une matrice infinie/NaN.
  static Matrix4 matrixFor({
    required Size viewport,
    required bool galaxyView,
    required Planet planet,
    required List<Player> players,
    required int activePlayerIndex,
  }) {
    if (viewport.width <= 0 || viewport.height <= 0) {
      return Matrix4.identity();
    }

    final double boardWidth = planet.width * BoardConstants.tileExtent;
    final double boardHeight = planet.height * BoardConstants.tileExtent;

    if (galaxyView) {
      // Vue Galaxie : ajustement minimal pour cadrer tout le plateau.
      final double scale = min(
        viewport.width / boardWidth,
        viewport.height / boardHeight,
      );
      final double dx = (viewport.width - boardWidth * scale) / 2;
      final double dy = (viewport.height - boardHeight * scale) / 2;
      return Matrix4(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
    }

    // Vue joueur : zoom fixe, centré sur le pion du joueur actif.
    final double scale = BoardConstants.followZoom;
    final Player active = players[activePlayerIndex];
    final double px =
        (active.position.x + 0.5) * BoardConstants.tileExtent * scale;
    final double py =
        (active.position.y + 0.5) * BoardConstants.tileExtent * scale;
    final double dx = viewport.width / 2 - px;
    final double dy = viewport.height / 2 - py;
    return Matrix4(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
  }

  /// Vrai lorsque [a] et [b] décrivent pratiquement la même transformation
  /// (tolérance [epsilon] par composante). Utilisé pour savoir si la caméra
  /// est « recentrée » sur sa cible.
  static bool almostEquals(Matrix4 a, Matrix4 b, {double epsilon = 0.5}) {
    final List<double> sa = a.storage;
    final List<double> sb = b.storage;
    for (int i = 0; i < sa.length; i++) {
      if ((sa[i] - sb[i]).abs() > epsilon) return false;
    }
    return true;
  }
}
