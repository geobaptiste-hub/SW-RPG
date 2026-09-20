import '../core/utils/json_utils.dart';
import 'ally.dart';
import 'armor.dart';
import 'monster.dart';
import 'weapon.dart';

/// Position sur une grille (colonne x, ligne y).
///
/// Sert au joueur (Architecture — Player.position), aux portails
/// (Portal.position) et aux boss (Boss.position).
class Position {
  final int x;
  final int y;

  const Position(this.x, this.y);

  /// Distance de Chebyshev : nombre de cases « en couronne » entre deux
  /// positions (utilisé par le rayon du brouillard).
  int chebyshevDistanceTo(Position other) {
    final int dx = (x - other.x).abs();
    final int dy = (y - other.y).abs();
    return dx > dy ? dx : dy;
  }

  /// Distance de Manhattan (nombre de déplacements orthogonaux minimum).
  int manhattanDistanceTo(Position other) =>
      (x - other.x).abs() + (y - other.y).abs();

  @override
  bool operator ==(Object other) =>
      other is Position && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Position($x, $y)';

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory Position.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Position(
      (json['x'] as num).toInt(),
      (json['y'] as num).toInt(),
    );
  }
}

/// Une case du plateau (Architecture v1.0 — modèle Tile).
///
///  - `walkable`   : la case est jouable (sinon elle est bloquée) ;
///  - `discovered` : la case a déjà été révélée au moins une fois
///    (une découverte est conservée définitivement — GDD §3) ;
///  - `visible`    : la case est actuellement dans le rayon visible du
///    joueur actif (6 cases — CDC §5).
class Tile {
  final int x;
  final int y;
  final bool walkable;
  final bool discovered;
  final bool visible;

  /// Monstre présent sur la case (Sprint 3). Le contenu d'une case n'est
  /// connu qu'au moment de sa première découverte (GDD addendum §4.1) et
  /// n'est rendu que si [discovered] (convention brouillard — Sprint 2).
  final Monster? monster;

  /// Allié proposé au recrutement sur la case (Sprint 4).
  final Ally? ally;

  /// Arme trouvée sur la case (Sprint 4).
  final Weapon? weapon;

  /// Tenue trouvée sur la case (Sprint 4).
  final Armor? armor;

  /// Case « Soin » : lancer le dé à l'entrée (règle du game design).
  final bool healSite;

  /// Case de la CANTINA (zone 3x3 — retours playtest 19/09) : sol de la
  /// zone (les 6 cases marchables ; la rangée du haut, le bar, est
  /// bloquée). Combats JvJ impossibles et aucun contenu tiré dedans.
  final bool cantina;

  /// Case de consommations de la cantina (ligne du milieu) : y marcher
  /// remet les PV au maximum.
  final bool cantinaDrink;

  /// Unique case d'entrée de la cantina (milieu de la rangée du bas) :
  /// on ne peut pénétrer dans la zone QUE par elle.
  final bool cantinaEntrance;

  const Tile({
    required this.x,
    required this.y,
    required this.walkable,
    this.discovered = false,
    this.visible = false,
    this.monster,
    this.ally,
    this.weapon,
    this.armor,
    this.healSite = false,
    this.cantina = false,
    this.cantinaDrink = false,
    this.cantinaEntrance = false,
  });

  Tile copyWith({
    bool? walkable,
    bool? discovered,
    bool? visible,
    Monster? monster,
    bool clearMonster = false,
    Ally? ally,
    bool clearAlly = false,
    Weapon? weapon,
    bool clearWeapon = false,
    Armor? armor,
    bool clearArmor = false,
    bool? healSite,
    bool? cantina,
    bool? cantinaDrink,
    bool? cantinaEntrance,
  }) {
    return Tile(
      x: x,
      y: y,
      walkable: walkable ?? this.walkable,
      discovered: discovered ?? this.discovered,
      visible: visible ?? this.visible,
      monster: clearMonster ? null : (monster ?? this.monster),
      ally: clearAlly ? null : (ally ?? this.ally),
      weapon: clearWeapon ? null : (weapon ?? this.weapon),
      armor: clearArmor ? null : (armor ?? this.armor),
      healSite: healSite ?? this.healSite,
      cantina: cantina ?? this.cantina,
      cantinaDrink: cantinaDrink ?? this.cantinaDrink,
      cantinaEntrance: cantinaEntrance ?? this.cantinaEntrance,
    );
  }

  @override
  String toString() => 'Tile($x, $y, walkable: $walkable)';

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'walkable': walkable,
        'discovered': discovered,
        'visible': visible,
        'monster': monster?.toJson(),
        'ally': ally?.toJson(),
        'weapon': weapon?.toJson(),
        'armor': armor?.toJson(),
        if (healSite) 'healSite': true,
        if (cantina) 'cantina': true,
        if (cantinaDrink) 'cantinaDrink': true,
        if (cantinaEntrance) 'cantinaEntrance': true,
      };

  factory Tile.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Tile(
      x: (json['x'] as num).toInt(),
      y: (json['y'] as num).toInt(),
      walkable: json['walkable'] as bool,
      discovered: json['discovered'] as bool? ?? false,
      visible: json['visible'] as bool? ?? false,
      monster:
          json['monster'] == null ? null : Monster.fromJson(json['monster']),
      ally: json['ally'] == null ? null : Ally.fromJson(json['ally']),
      weapon:
          json['weapon'] == null ? null : Weapon.fromJson(json['weapon']),
      armor: json['armor'] == null ? null : Armor.fromJson(json['armor']),
      healSite: json['healSite'] as bool? ?? false,
      cantina: json['cantina'] as bool? ?? false,
      cantinaDrink: json['cantinaDrink'] as bool? ?? false,
      cantinaEntrance: json['cantinaEntrance'] as bool? ?? false,
    );
  }
}
