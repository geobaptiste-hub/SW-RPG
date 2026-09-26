import '../core/utils/json_utils.dart';
import 'planet.dart' show PlanetType;
import 'tile.dart' show Position;

/// La CASE DE TÉLÉPORTATION (retours playtest 20/09, v2 bidirectionnelle) :
/// DEUX cases liées de la planète principale — marcher sur l'une projette
/// vers l'autre, dans les deux sens.
///
/// Règles :
///  - la première case ([position]) est cachée dès le début de la partie
///    et INVISIBLE (aucun logo) : il faut marcher dessus pour la
///    découvrir ;
///  - à la première utilisation, la destination devient la seconde case
///    fixe ([position2]) : les deux portails « restent ouverts »
///    ([visited] = vrai, images affichées sur les deux cases) ;
///  - ensuite, chaque case téléporte vers l'autre, indéfiniment.
class TeleportPortal {
  /// Planète porteuse (toujours une planète de départ).
  final PlanetType planet;

  /// Première case du couple (celle placée à la création de la partie).
  final Position position;

  /// Seconde case du couple (tirée au hasard LOIN de [position] lors de
  /// la première téléportation) ; null tant que le portail n'a jamais
  /// servi.
  final Position? position2;

  /// Vrai dès la première téléportation (les deux cases deviennent
  /// visibles avec l'image du portail).
  final bool visited;

  const TeleportPortal({
    required this.planet,
    required this.position,
    this.position2,
    this.visited = false,
  });

  TeleportPortal copyWith({Position? position2, bool? visited}) =>
      TeleportPortal(
        planet: planet,
        position: position,
        position2: position2 ?? this.position2,
        visited: visited ?? this.visited,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'planet': enumToName(planet),
        'position': position.toJson(),
        if (position2 != null) 'position2': position2!.toJson(),
        'visited': visited,
      };

  factory TeleportPortal.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return TeleportPortal(
      planet:
          enumFromName(PlanetType.values, json['planet'], PlanetType.hoth),
      position: Position.fromJson(json['position']),
      position2: json['position2'] == null
          ? null
          : Position.fromJson(json['position2']),
      visited: json['visited'] as bool? ?? false,
    );
  }
}
