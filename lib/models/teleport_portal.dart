import '../core/utils/json_utils.dart';
import 'planet.dart' show PlanetType;
import 'tile.dart' show Position;

/// La CASE DE TÉLÉPORTATION (retours playtest 20/09) : une case de la
/// planète principale, cachée dès le début de la partie, qui téléporte le
/// joueur vers un point éloigné et aléatoire de la planète.
///
/// Règles :
///  - invisible tant qu'elle n'a jamais été utilisée (pas de logo) — il
///    faut marcher dessus pour la découvrir ;
///  - à la première utilisation, [visited] passe à vrai : le portail
///    « reste ouvert » et son image s'affiche sur la case ;
///  - chaque utilisation téléporte vers un point ÉLOIGNÉ et libre de la
///    planète (jamais à côté) ;
///  - le pas de déplacement sur la case est consommé normalement.
class TeleportPortal {
  /// Planète porteuse (toujours une planète de départ).
  final PlanetType planet;

  /// Position de la case-portail.
  final Position position;

  /// Vrai après la première téléportation (le portail devient visible).
  final bool visited;

  const TeleportPortal({
    required this.planet,
    required this.position,
    this.visited = false,
  });

  TeleportPortal copyWith({bool? visited}) => TeleportPortal(
        planet: planet,
        position: position,
        visited: visited ?? this.visited,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'planet': enumToName(planet),
        'position': position.toJson(),
        'visited': visited,
      };

  factory TeleportPortal.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return TeleportPortal(
      planet:
          enumFromName(PlanetType.values, json['planet'], PlanetType.hoth),
      position: Position.fromJson(json['position']),
      visited: json['visited'] as bool? ?? false,
    );
  }
}
