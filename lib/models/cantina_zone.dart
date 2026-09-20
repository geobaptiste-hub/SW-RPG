import '../core/utils/json_utils.dart';
import 'planet.dart' show PlanetType;
import 'tile.dart' show Position;

/// La CANTINA : petite zone 3x3 sur la planète principale (retours
/// playtest 19/09).
///
/// Règles :
///  - 9 cases ancrées en [anchor] (haut-gauche) : la rangée du haut est
///    le bar en bois (bloquée), la rangée du milieu porte les
///    consommations (PV remis au maximum), l'entrée unique est la case
///    du milieu de la rangée du bas ;
///  - combats JvJ impossibles dedans, aucun contenu tiré (pas de
///    monstre/allié/objet/soin) ;
///  - accessible à tous les niveaux : il suffit de la TROUVER — cachée
///    sous le brouillard, le logo jaune (même icône que les portails)
///    s'affiche sur la case centrale tant qu'elle est dans la zone
///    visible, puis [visited] passe à true à la première entrée et
///    l'image de la cantina remplace le logo ;
///  - musique en boucle dédiée tant que le joueur actif y reste.
class CantinaZone {
  /// Planète porteuse (toujours une planète de départ).
  final PlanetType planet;

  /// Case HAUT-GAUCHE de la zone 3x3.
  final Position anchor;

  /// Vrai dès qu'au moins un joueur est entré dans la zone (l'image
  /// remplace alors le logo jaune).
  final bool visited;

  const CantinaZone({
    required this.planet,
    required this.anchor,
    this.visited = false,
  });

  CantinaZone copyWith({bool? visited}) => CantinaZone(
        planet: planet,
        anchor: anchor,
        visited: visited ?? this.visited,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'planet': enumToName(planet),
        'anchor': anchor.toJson(),
        'visited': visited,
      };

  factory CantinaZone.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return CantinaZone(
      planet: enumFromName(
          PlanetType.values, json['planet'], PlanetType.tatooine),
      anchor: Position.fromJson(json['anchor']),
      visited: json['visited'] as bool? ?? false,
    );
  }
}
