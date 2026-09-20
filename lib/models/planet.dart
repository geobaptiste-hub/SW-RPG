import '../core/utils/json_utils.dart';
import 'tile.dart';

/// Types de planètes : 5 planètes de départ + 4 planètes secondaires
/// accessibles par portail (GDD §4) + la CANTINA (mini-zone 3x3 —
/// retours playtest 19/09). `cantina` est en DERNIER pour ne pas
/// déplacer les index des planètes existantes (utilisés dans les seeds).
enum PlanetType {
  coruscant,
  alderande,
  endor,
  hoth,
  tatooine,
  mustafar,
  yavin4,
  etoileNoire,
  dagobah,
  cantina,
}

/// Une planète : son nom, ses dimensions et l'ensemble de ses cases
/// (Architecture v1.0 — modèle Planet).
///
/// Le champ `type` est un ajout au modèle d'architecture : il permet de
/// relier la planète aux portails (Portal.destination) et aux boss
/// (Boss.planet).
class Planet {
  final String name;
  final PlanetType type;
  final int width;
  final int height;
  final List<Tile> tiles;

  const Planet({
    required this.name,
    required this.type,
    required this.width,
    required this.height,
    required this.tiles,
  });

  /// Nombre de cases jouables (168 sur le plateau principal).
  int get playableTileCount => tiles.where((Tile tile) => tile.walkable).length;

  /// Nombre de cases bloquées (57 sur le plateau principal).
  int get blockedTileCount => tiles.where((Tile tile) => !tile.walkable).length;

  /// Case aux coordonnées [x]/[y], ou `null` si hors grille.
  Tile? tileAtOrNull(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    return tiles[y * width + x];
  }

  /// Case aux coordonnées [x]/[y] (doit exister).
  Tile tileAt(int x, int y) => tileAtOrNull(x, y)!;

  /// La case aux coordonnées [x]/[y] existe-t-elle et est-elle jouable ?
  bool isWalkableAt(int x, int y) => tileAtOrNull(x, y)?.walkable ?? false;

  /// La position est-elle sur le pourtour de la planète ?
  bool isOnEdge(int x, int y) =>
      x == 0 || y == 0 || x == width - 1 || y == height - 1;

  /// Remplace la liste des cases (utilisé par la révélation du brouillard).
  Planet withTiles(List<Tile> newTiles) => Planet(
      name: name, type: type, width: width, height: height, tiles: newTiles);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': enumToName(type),
        'width': width,
        'height': height,
        'tiles': tiles.map((Tile tile) => tile.toJson()).toList(),
      };

  factory Planet.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Planet(
      name: json['name'] as String,
      type: enumFromName(PlanetType.values, json['type'], PlanetType.coruscant),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      tiles: asJsonList(json['tiles'])
          .map((dynamic t) => Tile.fromJson(t))
          .toList(),
    );
  }
}
