import '../core/utils/json_utils.dart';
import 'planet.dart' show PlanetType;
import 'tile.dart' show Position;

/// PATAPUCHE (retours playtest 20/09) : petite créature non jouable qui
/// apparaît sur la planète principale dès qu'un joueur atteint le niveau 2.
///
/// Règles :
///  - elle se déplace d'une case aléatoirement à CHAQUE fin de tour (et
///    saute par-dessus les monstres/contenus si bloquée — jamais coincée) ;
///  - quand un joueur marche sur sa case, elle offre son don :
///    +100 ATK et +100 PV (maximum ET points actuels) — UNE SEULE FOIS
///    par joueur pour toute la partie ([claimedBy]) ;
///  - son pion est visible sur la carte (image 3 du dossier
///    `assets/images/patapuche/`).
class Patapuche {
  /// Planète porteuse (toujours une planète de départ).
  final PlanetType planet;

  /// Position actuelle de Patapuche.
  final Position position;

  /// Identifiants des joueurs ayant déjà reçu le don (une fois par joueur
  /// pour toute la partie).
  final List<String> claimedBy;

  const Patapuche({
    required this.planet,
    required this.position,
    this.claimedBy = const <String>[],
  });

  /// Le joueur [playerId] a-t-il déjà reçu le don ?
  bool hasClaimed(String playerId) => claimedBy.contains(playerId);

  Patapuche copyWith({
    Position? position,
    List<String>? claimedBy,
  }) =>
      Patapuche(
        planet: planet,
        position: position ?? this.position,
        claimedBy: claimedBy ?? this.claimedBy,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'planet': enumToName(planet),
        'position': position.toJson(),
        'claimedBy': claimedBy,
      };

  factory Patapuche.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Patapuche(
      planet:
          enumFromName(PlanetType.values, json['planet'], PlanetType.hoth),
      position: Position.fromJson(json['position']),
      claimedBy: (json['claimedBy'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic id) => id as String)
          .toList(),
    );
  }
}
