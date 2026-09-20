import '../core/utils/json_utils.dart';
import 'planet.dart';
import 'tile.dart';

/// Un portail menant vers une planète secondaire
/// (Architecture v1.0 — modèle Portal).
///
/// Règles (GDD §5) :
///  - les portails n'existent pas au début de la partie ;
///  - ils sont posés dès qu'au moins un joueur atteint le niveau 3 ;
///  - maximum 4 portails simultanés, chacun mène vers une planète
///    secondaire différente (une seule génération possible) ;
///  - Sprint 6 (retours playtest) : les 4 sont GARANTIS dès qu'un joueur
///    atteint le niveau 3 — posés d'un coup n'importe où sur des cases
///    libres de la planète principale, espacés d'au moins 4 cases ;
///  - fix playtest 19/09 : la pose reste SOUS le brouillard de guerre —
///    le marqueur ne s'affiche sur le plateau que lorsqu'un joueur
///    s'approche (case dans la zone visible), [discovered] signifiant
///    « le portail existe et est fonctionnel » (voyage) ;
///  - lorsqu'un portail est repéré, tous les joueurs sont informés
///    (brouillard partagé hot-seat — décision du 07/09/2026).
class Portal {
  /// Planète secondaire vers laquelle mène le portail.
  final PlanetType destination;

  /// Position du portail sur le plateau principal (case de bord).
  final Position position;

  /// Vrai lorsque le portail existe et est fonctionnel (le voyage se
  /// déclenche quand un joueur marche dessus). L'AFFICHAGE sur le plateau
  /// ne dépend pas de ce flag mais de l'état de brouillard de la case
  /// (visible uniquement dans la zone de vue — fix playtest 19/09).
  final bool discovered;

  /// Vrai lorsqu'au moins un joueur a traversé ce portail (retours
  /// playtest : son illustration devient celle de la planète de
  /// destination sur le plateau).
  final bool visited;

  const Portal({
    required this.destination,
    required this.position,
    this.discovered = false,
    this.visited = false,
  });

  Portal copyWith({bool? discovered, bool? visited}) => Portal(
        destination: destination,
        position: position,
        discovered: discovered ?? this.discovered,
        visited: visited ?? this.visited,
      );

  Map<String, dynamic> toJson() => {
        'destination': enumToName(destination),
        'position': position.toJson(),
        'discovered': discovered,
        'visited': visited,
      };

  factory Portal.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return Portal(
      destination: enumFromName(
          PlanetType.values, json['destination'], PlanetType.dagobah),
      position: Position.fromJson(json['position']),
      discovered: json['discovered'] as bool? ?? false,
      visited: json['visited'] as bool? ?? false,
    );
  }
}
