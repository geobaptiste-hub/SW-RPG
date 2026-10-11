import '../core/utils/json_utils.dart';
import 'planet.dart' show PlanetType;
import 'tile.dart' show Position;

/// Le FAUCON MILLÉNIUM : petite zone 3x3 sur la planète principale
/// (retours playtest 11/10).
///
/// Règles :
///  - la porte est ancrée par la seed sur la planète de départ (case
///    vide, jamais bloquée, logo jaune comme la cantina et les
///    portails), accessible dès le niveau 1 ;
///  - entrer amène sur la case d'arrivée (bas-milieu) de la zone :
///    9 cases marchables, toutes « blanches » SAUF celle du
///    haut-milieu (`PlanetConstants.falconBonusPosition`) où s'affiche
///    l'image déposée ;
///  - marcher sur la case du haut-milieu : le joueur actif gagne la
///    super attaque INRATABLE jusqu'à la fin de la partie (une seule
///    fois par joueur — revenir dessus ne fait plus que jouer le son) ;
///  - combats JvJ impossibles dedans, aucun contenu tiré (les cases
///    portent le marqueur sanctuaire `cantina`, réutilisé) ;
///  - on ressort en repassant par la case d'arrivée, comme la cantina.
class FalconZone {
  /// Planète porteuse (toujours une planète de départ).
  final PlanetType planet;

  /// Case-portail sur la planète principale.
  final Position anchor;

  /// Vrai dès qu'au moins un joueur est entré dans la zone (le
  /// médaillon `faucon/portail` remplace alors le logo jaune).
  final bool visited;

  const FalconZone({
    required this.planet,
    required this.anchor,
    this.visited = false,
  });

  FalconZone copyWith({bool? visited}) => FalconZone(
        planet: planet,
        anchor: anchor,
        visited: visited ?? this.visited,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'planet': enumToName(planet),
        'anchor': anchor.toJson(),
        'visited': visited,
      };

  factory FalconZone.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return FalconZone(
      planet: enumFromName(
          PlanetType.values, json['planet'], PlanetType.tatooine),
      anchor: Position.fromJson(json['anchor']),
      visited: json['visited'] as bool? ?? false,
    );
  }
}
