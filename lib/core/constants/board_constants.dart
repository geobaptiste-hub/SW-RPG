import '../../models/tile.dart';

/// Constantes du plateau principal (GDD §3, CDC §5).
class BoardConstants {
  BoardConstants._();

  /// Grille 20 x 20 → 400 cases théoriques (Sprint 4.1 — carte agrandie
  /// pour l'équilibrage, décision du 07/09/2026).
  static const int gridWidth = 20;
  static const int gridHeight = 20;

  /// 400 cases théoriques = 300 cases jouables + 100 cases bloquées.
  static const int totalTiles = gridWidth * gridHeight; // 400
  static const int playableTiles = 300;
  static const int blockedTiles = 100;

  /// 8 positions de départ fixes sur le pourtour (CDC §5).
  static const int startCount = 8;

  /// Taille d'affichage d'une case en pixels logiques (choix d'interface,
  /// aucune valeur imposée par le GDD/CDC).
  static const double tileExtent = 56.0;

  /// Zoom utilisé quand la caméra suit le joueur actif.
  static const double followZoom = 1.6;

  /// Zoom minimal autorisé (utilisé par la Vue Galaxie).
  static const double minZoom = 0.35;
  static const double maxZoom = 3.0;

  /// Marge autour du plateau autorisée par l'InteractiveViewer.
  static const double cameraBoundaryMargin = 120.0;

  /// Positions de départ fixes « Start A » à « Start H », toutes sur le
  /// pourtour de la grille 15x15 :
  ///
  /// ```text
  ///   A ─── E ─── B
  ///   │            │
  ///   H            F
  ///   │            │
  ///   D ─── G ─── C
  /// ```
  static const List<Position> startPositions = [
    Position(0, 0), // Start A — coin haut-gauche
    Position(19, 0), // Start B — coin haut-droit
    Position(19, 19), // Start C — coin bas-droit
    Position(0, 19), // Start D — coin bas-gauche
    Position(10, 0), // Start E — milieu haut
    Position(19, 10), // Start F — milieu droit
    Position(10, 19), // Start G — milieu bas
    Position(0, 10), // Start H — milieu gauche
  ];

  /// Attribution des départs selon le nombre de joueurs (CDC §5) :
  ///  - 2 joueurs  : coins opposés ;
  ///  - 3 joueurs  : triangle ;
  ///  - 4 joueurs  : 4 coins ;
  ///  - 5 à 8      : positions prédéfinies sur le pourtour (A..H).
  ///
  /// TODO(Sprint 2+) : le GDD ne précise pas exactement quels sommets forment
  /// le « triangle » à 3 joueurs ni l'ordre d'attribution des 8 starts à
  /// 5-8 joueurs. Choix actuel : A, B, D pour le triangle (3 coins) et
  /// l'ordre A,B,C,D puis E,F,G,H (coins d'abord, puis milieux) pour 5-8.
  static List<Position> startsForPlayerCount(int playerCount) {
    assert(playerCount >= 2 && playerCount <= 8,
        'Le nombre de joueurs doit être compris entre 2 et 8.');
    const corners = startPositions; // A, B, C, D
    return switch (playerCount) {
      2 => [corners[0], corners[2]], // coins opposés : A et C
      3 => [corners[0], corners[1], corners[3]], // triangle : A, B, D
      4 => corners.sublist(0, 4), // 4 coins : A, B, C, D
      _ => startPositions.sublist(0, playerCount), // 5 à 8 : A..H
    };
  }
}
