import '../core/constants/enums.dart';
import '../core/utils/json_utils.dart';
import 'boss.dart';
import 'cantina_zone.dart';
import 'planet.dart';
import 'player.dart';
import 'portal.dart';

/// État complet d'une partie — le cœur du jeu (Architecture v1.0).
///
/// Champs de l'architecture : `turn`, `currentPlayerIndex`,
/// `gameTimeSeconds`, `currentPlanet`, `players`, `bosses`, `portals`.
///
/// Champs ajoutés pour couvrir les règles et la sauvegarde :
///  - `schemaVersion` / `gameId` / `seed` : gestion de la sauvegarde Hive et
///    régénération déterministe du plateau ;
///  - `mode` / `teamSize` : configuration choisie à la création (CDC §4) ;
///  - `planetType` : type de la planète courante (doublé pour lecture rapide) ;
///  - `movementPointsRemaining` / `lastDiceRoll` : état du déplacement en
///    cours (GDD §6) ;
///  - `status` : partie en cours ou terminée ;
///  - `savedAt` : horodatage de la dernière sauvegarde automatique.
class GameState {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String gameId;

  /// Graine utilisée pour la génération du plateau (génération procédurale
  /// du GDD addendum §4.1).
  final int seed;

  final GameMode mode;

  /// Taille des équipes en mode Équipes (2, 3 ou 4) ; 0 en chacun pour soi.
  final int teamSize;

  final PlanetType planetType;
  final Planet currentPlanet;

  /// Toutes les planètes générées, indexées par type (Sprint 5) : la
  /// principale + les planètes secondaires découvertes via portails.
  final Map<PlanetType, Planet> planets;
  final List<Player> players;

  /// Numéro du tour (manche complète : un « tour » s'incrémente lorsque la
  /// main revient au premier joueur).
  final int turn;

  final int currentPlayerIndex;
  final int gameTimeSeconds;

  /// Points de déplacement restants pour le joueur actif (0 → fin du tour
  /// possible). Découle du dernier lancer de dé (GDD §6).
  final int movementPointsRemaining;

  /// Dernier lancer de dé du joueur actif (`null` tant qu'il n'a pas lancé).
  final int? lastDiceRoll;

  final List<Boss> bosses;
  final List<Portal> portals;

  /// La cantina (zone 3x3 sur la planète principale — retours playtest
  /// 19/09) ; `null` pour les parties créées avant cette fonctionnalité.
  final CantinaZone? cantina;

  final GameStatus status;
  final DateTime? savedAt;

  const GameState({
    required this.schemaVersion,
    required this.gameId,
    required this.seed,
    required this.mode,
    required this.teamSize,
    required this.planetType,
    required this.currentPlanet,
    this.planets = const {},
    required this.players,
    required this.turn,
    required this.currentPlayerIndex,
    required this.gameTimeSeconds,
    required this.movementPointsRemaining,
    required this.lastDiceRoll,
    required this.bosses,
    required this.portals,
    this.cantina,
    required this.status,
    this.savedAt,
  });

  /// Joueur dont c'est le tour.
  Player get activePlayer => players[currentPlayerIndex];

  /// L'heure de jeu formatée `mm:ss` (CDC §10).
  String get formattedGameTime {
    final int minutes = gameTimeSeconds ~/ 60;
    final int seconds = gameTimeSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  GameState copyWith({
    int? schemaVersion,
    String? gameId,
    int? seed,
    GameMode? mode,
    int? teamSize,
    PlanetType? planetType,
    Planet? currentPlanet,
    Map<PlanetType, Planet>? planets,
    List<Player>? players,
    int? turn,
    int? currentPlayerIndex,
    int? gameTimeSeconds,
    int? movementPointsRemaining,
    int? lastDiceRoll,
    bool clearLastDiceRoll = false,
    List<Boss>? bosses,
    List<Portal>? portals,
    CantinaZone? cantina,
    GameStatus? status,
    DateTime? savedAt,
  }) {
    return GameState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      gameId: gameId ?? this.gameId,
      seed: seed ?? this.seed,
      mode: mode ?? this.mode,
      teamSize: teamSize ?? this.teamSize,
      planetType: planetType ?? this.planetType,
      currentPlanet: currentPlanet ?? this.currentPlanet,
      planets: planets ?? this.planets,
      players: players ?? this.players,
      turn: turn ?? this.turn,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      gameTimeSeconds: gameTimeSeconds ?? this.gameTimeSeconds,
      movementPointsRemaining:
          movementPointsRemaining ?? this.movementPointsRemaining,
      lastDiceRoll:
          clearLastDiceRoll ? null : (lastDiceRoll ?? this.lastDiceRoll),
      bosses: bosses ?? this.bosses,
      portals: portals ?? this.portals,
      cantina: cantina ?? this.cantina,
      status: status ?? this.status,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'gameId': gameId,
        'seed': seed,
        'mode': enumToName(mode),
        'teamSize': teamSize,
        'planetType': enumToName(planetType),
        'currentPlanet': currentPlanet.toJson(),
        'planets': <Map<String, dynamic>>[
          for (final MapEntry<PlanetType, Planet> entry in planets.entries)
            <String, dynamic>{
              'type': enumToName(entry.key),
              'planet': entry.value.toJson(),
            },
        ],
        'players': players.map((Player player) => player.toJson()).toList(),
        'turn': turn,
        'currentPlayerIndex': currentPlayerIndex,
        'gameTimeSeconds': gameTimeSeconds,
        'movementPointsRemaining': movementPointsRemaining,
        'lastDiceRoll': lastDiceRoll,
        'bosses': bosses.map((Boss boss) => boss.toJson()).toList(),
        'portals': portals.map((Portal portal) => portal.toJson()).toList(),
        if (cantina != null) 'cantina': cantina!.toJson(),
        'status': enumToName(status),
        'savedAt': savedAt?.toIso8601String(),
      };

  factory GameState.fromJson(dynamic raw) {
    final Map<String, dynamic> json = asJsonMap(raw);
    return GameState(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      gameId: json['gameId'] as String,
      seed: (json['seed'] as num).toInt(),
      mode: enumFromName(GameMode.values, json['mode'], GameMode.chacunPourSoi),
      teamSize: (json['teamSize'] as num?)?.toInt() ?? 0,
      planetType: enumFromName(
          PlanetType.values, json['planetType'], PlanetType.coruscant),
      currentPlanet: Planet.fromJson(json['currentPlanet']),
      planets: <PlanetType, Planet>{
        for (final Map<String, dynamic> entry in asJsonList(json['planets']))
          enumFromName(PlanetType.values, entry['type'], PlanetType.hoth):
            Planet.fromJson(entry['planet']),
      },
      players: asJsonList(json['players'])
          .map((dynamic player) => Player.fromJson(player))
          .toList(),
      turn: (json['turn'] as num).toInt(),
      currentPlayerIndex: (json['currentPlayerIndex'] as num).toInt(),
      gameTimeSeconds: (json['gameTimeSeconds'] as num).toInt(),
      movementPointsRemaining:
          (json['movementPointsRemaining'] as num?)?.toInt() ?? 0,
      lastDiceRoll: (json['lastDiceRoll'] as num?)?.toInt(),
      bosses: asJsonList(json['bosses'])
          .map((dynamic boss) => Boss.fromJson(boss))
          .toList(),
      portals: asJsonList(json['portals'])
          .map((dynamic portal) => Portal.fromJson(portal))
          .toList(),
      cantina: json['cantina'] == null
          ? null
          : CantinaZone.fromJson(json['cantina']),
      status: enumFromName(
          GameStatus.values, json['status'], GameStatus.inProgress),
      savedAt: json['savedAt'] == null
          ? null
          : DateTime.tryParse(json['savedAt'] as String),
    );
  }
}
