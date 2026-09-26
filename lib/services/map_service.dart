import 'dart:math';

import '../core/constants/board_constants.dart';
import '../core/constants/planet_constants.dart' show PlanetConstants;
import '../core/constants/enums.dart' show GamePhase;
import '../core/constants/game_constants.dart';
import '../core/constants/card_constants.dart';
import '../core/constants/monster_constants.dart';
import '../core/constants/planet_constants.dart';
import '../core/utils/direction.dart';
import '../models/boss.dart';
import '../models/planet.dart';
import '../models/player.dart';
import '../models/portal.dart';
import '../models/tile.dart';

/// Service responsable du plateau : génération procédurale, brouillard de
/// guerre, déplacement, portails et boss mobiles (Architecture v1.0).
class MapService {
  /// Génère la planète de départ : grille 15x15, 168 cases jouables,
  /// 57 cases bloquées, toutes les zones jouables connectées
  /// (GDD §3, CDC §5).
  ///
  /// La génération est procédurale (GDD addendum §4.1) mais déterministe :
  /// la graine [seed] est stockée dans le GameState, ce qui permet de
  /// reproduire le même plateau à l'identique si besoin.
  Planet generateStartPlanet(PlanetType type, {required int seed}) {
    final Random rng = Random(seed);
    // Nombre d'essais de sécurité : l'algorithme garantit la connectivité à
    // chaque pose de bloc, il aboutit statistiquement toujours.
    // L'ancre de la porte est tirée avec un RNG dédié (Cantina — 19/09).
    final Position? cantinaDoor = _pickCantinaAnchor(Random(seed + 0xC0FFEE));
    // Nombre d'essais de sécurité : l'algorithme garantit la connectivité à
    // chaque pose de bloc, il aboutit statistiquement toujours.
    for (int attempt = 0; attempt < 200; attempt++) {
      final Planet? planet = _tryGeneratePlanet(type, rng, cantinaDoor);
      if (planet != null) return planet;
    }
    throw StateError(
        'Génération du plateau impossible après 200 essais (seed: $seed).');
  }

  /// Position de la PORTE de la cantina pour une graine : déterministe,
  /// calculée avec un RNG dédié indépendant du reste de la génération.
  /// Candidates : toute case hors départs.
  Position? cantinaAnchorFor(int seed) =>
      _pickCantinaAnchor(Random(seed + 0xC0FFEE));

  Position? _pickCantinaAnchor(Random rng) {
    final Set<Position> starts = BoardConstants.startPositions.toSet();
    final List<Position> candidates = <Position>[
      for (int y = 0; y < BoardConstants.gridHeight; y++)
        for (int x = 0; x < BoardConstants.gridWidth; x++)
          if (!starts.contains(Position(x, y))) Position(x, y),
    ];
    if (candidates.isEmpty) return null;
    return candidates[rng.nextInt(candidates.length)];
  }

  /// La CANTINA intérieure : mini-zone 3x3 INDÉPENDANTE, comme une
  /// micro-planète (retours playtest 19/09 v2 — la case-portail de la
  /// planète principale y téléporte). Rangée du haut = bar en bois
  /// (bloquée), ligne du milieu = comptoir (PV remis au maximum),
  /// arrivée et départ = case (1,2) — [PlanetConstants.cantinaArrival].
  Planet generateCantinaPlanet() {
    final List<Tile> tiles = <Tile>[];
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        final bool bar = y == 0;
        tiles.add(Tile(
          x: x,
          y: y,
          walkable: !bar,
          cantina: !bar,
          cantinaDrink: y == 1,
          cantinaEntrance: x == 1 && y == 2,
        ));
      }
    }
    return Planet(
      name: PlanetConstants.displayNames[PlanetType.cantina] ?? 'Cantina',
      type: PlanetType.cantina,
      width: 3,
      height: 3,
      tiles: tiles,
    );
  }

  Planet? _tryGeneratePlanet(
    PlanetType type,
    Random rng,
    Position? cantinaDoor,
  ) {
    final int width = BoardConstants.gridWidth;
    final int height = BoardConstants.gridHeight;

    // 1) Toutes les cases jouables au départ ; les 8 départs restent jouables.
    final Set<Position> blocked = <Position>{};
    final Set<Position> starts = BoardConstants.startPositions.toSet();

    // La PORTE de la cantina reste jouable (1 case protégée du blocage —
    // retours playtest 19/09 v2).
    final Set<Position> protected = <Position>{
      if (cantinaDoor != null) cantinaDoor,
    };

    bool isBlocked(int x, int y) => blocked.contains(Position(x, y));

    // 2) Pose des 100 blocs, un par un, en conservant la connectivité.
    while (blocked.length < BoardConstants.blockedTiles) {
      final Position? candidate = _pickBlockCandidate(
        blocked: blocked,
        starts: starts,
        width: width,
        height: height,
        rng: rng,
        preferFrontier: true,
        protectedTiles: protected,
      );
      if (candidate == null) {
        // Aucun candidat « frontière » ne convient : dernier essai en
        // échantillonnage complètement aléatoire.
        final Position? fallback = _pickBlockCandidate(
          blocked: blocked,
          starts: starts,
          width: width,
          height: height,
          rng: rng,
          preferFrontier: false,
        );
        if (fallback == null) return null; // nouvel essai global
        blocked.add(fallback);
        continue;
      }
      blocked.add(candidate);
    }

    // 3) Construction des cases (la porte de la cantina est une case
    // ordinaire — son identité vient de CantinaZone.anchor).
    final List<Tile> tiles = <Tile>[];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        tiles.add(Tile(x: x, y: y, walkable: !isBlocked(x, y)));
      }
    }

    final Planet planet = Planet(
      name: PlanetConstants.displayNames[type] ?? type.name,
      type: type,
      width: width,
      height: height,
      tiles: tiles,
    );

    // 4) Vérification finale : 168 cases jouables et graphe connexe.
    if (planet.playableTileCount != BoardConstants.playableTiles) return null;
    if (!isFullyConnected(planet)) return null;
    return planet;
  }

  /// Choisit une case à bloquer parmi les candidates valides (jouable, hors
  /// départs, hors cases protégées — le sol de la cantina, pas déjà
  /// bloquée). Avec [preferFrontier], privilégie les cases adjacentes à un
  /// bloc existant pour obtenir des formes organiques. Chaque candidate est
  /// testée par connectivité avant d'être retenue.
  Position? _pickBlockCandidate({
    required Set<Position> blocked,
    required Set<Position> starts,
    required int width,
    required int height,
    required Random rng,
    required bool preferFrontier,
    Set<Position> protectedTiles = const <Position>{},
  }) {
    final List<Position> candidates = <Position>[];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final Position p = Position(x, y);
        if (blocked.contains(p) ||
            starts.contains(p) ||
            protectedTiles.contains(p)) {
          continue;
        }
        if (preferFrontier &&
            !_isFrontierOfBlocked(p, blocked, width, height)) {
          continue;
        }
        candidates.add(p);
      }
    }
    candidates.shuffle(rng);

    for (final Position candidate in candidates) {
      blocked.add(candidate);
      final bool connected = _remainingWalkableConnected(
          blocked: blocked, width: width, height: height);
      if (connected) {
        return candidate; // on garde le bloc
      }
      blocked.remove(candidate); // ce bloc déconnecterait la carte : rejeté
    }
    return null;
  }

  bool _isFrontierOfBlocked(
      Position p, Set<Position> blocked, int width, int height) {
    for (final Direction direction in Direction.orthogonal) {
      final int nx = p.x + direction.dx;
      final int ny = p.y + direction.dy;
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      if (blocked.contains(Position(nx, ny))) return true;
    }
    return false;
  }

  /// Vérifie que toutes les cases non bloquées forment un seul ensemble
  /// connexe (parcours en largeur).
  bool _remainingWalkableConnected({
    required Set<Position> blocked,
    required int width,
    required int height,
  }) {
    Position? start;
    int walkableCount = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!blocked.contains(Position(x, y))) {
          walkableCount++;
          start ??= Position(x, y);
        }
      }
    }
    if (start == null) return false;

    final Set<Position> visited = <Position>{start};
    final List<Position> queue = <Position>[start];
    while (queue.isNotEmpty) {
      final Position current = queue.removeLast();
      for (final Direction direction in Direction.orthogonal) {
        final int nx = current.x + direction.dx;
        final int ny = current.y + direction.dy;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        final Position neighbor = Position(nx, ny);
        if (blocked.contains(neighbor)) continue;
        if (visited.add(neighbor)) queue.add(neighbor);
      }
    }
    return visited.length == walkableCount;
  }

  /// Vérifie que toutes les cases jouables d'une planète sont connectées
  /// entre elles (CDC §5 : « Toutes les zones jouables doivent être
  /// connectées »).
  bool isFullyConnected(Planet planet) {
    final Set<Position> blocked = <Position>{
      for (final Tile tile in planet.tiles)
        if (!tile.walkable) Position(tile.x, tile.y),
    };
    return _remainingWalkableConnected(
      blocked: blocked,
      width: planet.width,
      height: planet.height,
    );
  }

  // ---------------------------------------------------------------------------
  // Déplacement (GDD §6, CDC §7)
  // ---------------------------------------------------------------------------

  /// Trouve une case libre pour un portail garanti (retours playtest :
  /// n'importe où sur la planète — pas seulement les bords —, hors départs,
  /// hors contenus, hors cases occupées, à distance de Chebyshev ≥ 4 des
  /// portails existants). Null si aucune.
  Position? findGuaranteedPortalSpot({
    required Planet planet,
    required List<Portal> portals,
    required Set<Position> occupied,
    required Random rng,
    Position? cantinaDoor,
  }) {
    final Set<Position> starts = BoardConstants.startPositions.toSet();
    final List<Position> candidates = <Position>[];
    for (final Tile tile in planet.tiles) {
      final Position position = Position(tile.x, tile.y);
      if (!tile.walkable ||
          starts.contains(position) ||
          occupied.contains(position)) {
        continue;
      }
      // Jamais de portail SUR la porte de la cantina ni DANS la cantina
      // (retours playtest 19/09).
      if (tile.cantina || position == cantinaDoor) {
        continue;
      }
      if (tile.monster != null ||
          tile.ally != null ||
          tile.weapon != null ||
          tile.armor != null ||
          tile.healSite) {
        continue;
      }
      if (portals.any((Portal portal) => portal.position == position)) {
        continue;
      }
      if (portals.any((Portal portal) =>
          portal.position.chebyshevDistanceTo(position) < 4)) {
        continue;
      }
      candidates.add(position);
    }
    if (candidates.isEmpty) return null;
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Cases voisines orthogonales dans les limites de la grille.
  List<Position> neighborPositions(Position position, Planet planet) {
    final List<Position> result = <Position>[];
    for (final Direction direction in Direction.orthogonal) {
      final int x = position.x + direction.dx;
      final int y = position.y + direction.dy;
      if (planet.tileAtOrNull(x, y) != null) result.add(Position(x, y));
    }
    return result;
  }

  /// Cibles de déplacement valides pour le joueur actif : cases voisines
  /// jouables. Depuis le Sprint 3, les cases occupées par un autre joueur
  /// sont ciblables (combat entre joueurs — GDD §13) de même que les cases
  /// à monstre (rencontre — GDD §10). Les joueurs éliminés n'occupent plus
  /// de case.
  List<Position> validMoveTargets({
    required Planet planet,
    required List<Player> players,
    required int activePlayerIndex,
  }) {
    final Player active = players[activePlayerIndex];
    bool enterable(Position p) {
      if (!planet.isWalkableAt(p.x, p.y)) return false;
      final Tile target = planet.tileAt(p.x, p.y);
      for (int i = 0; i < players.length; i++) {
        if (i == activePlayerIndex) continue;
        final Player other = players[i];
        if (other.eliminated) continue;
        // FIX 19/09 : comparer AUSSI la planète — sans ça, un joueur
        // situé sur une AUTRE planète aux mêmes coordonnées bloquait la
        // case de façon fantôme (très fréquent en Big Four / équipes :
        // 8 pions répartis sur des grilles qui se recouvrent).
        if (other.planet == planet.type && other.position == p) {
          // Cantina (retours playtest 19/09) : AUCUN combat JvJ dans la
          // zone — la case d'un autre joueur qui s'y trouve n'est pas
          // entrable (on ne peut ni l'attaquer ni l'y côtoyer).
          if (target.cantina) return false;
          // Mode Équipes : la case d'un COÉQUIPIER n'est pas entrable —
          // on combat les ennemis, pas les alliés (GDD §13).
          if (active.team != null &&
              other.team != null &&
              other.team == active.team) {
            return false;
          }
        }
      }
      return true;
    }

    return neighborPositions(active.position, planet)
        .where(enterable)
        .toList();
  }

  /// Peuple les cases qui viennent d'être découvertes (GDD addendum §4.1) :
  /// le contenu d'une case est tiré au moment de sa première découverte,
  /// selon la [phase] courante. Sprint 3 : seul l'événement « monstre »
  /// produit du contenu. Jamais sur les départs ni sur une case occupée,
  /// et une case ne se peuple qu'une seule fois.
  ({Planet planet, List<Portal> newPortals}) populateNewlyDiscoveredTiles({
    required Planet before,
    required Planet after,
    required GamePhase phase,
    required Random rng,
    required Set<Position> occupied,
    required List<Portal> existingPortals,
    required bool bossUnlocked,
    Set<Position> avoidPositions = const <Position>{},
  }) {
    final Set<Position> starts = BoardConstants.startPositions.toSet();
    final List<double> probabilities = switch (phase) {
      GamePhase.debut => GameConstants.eventProbabilitiesDebut,
      GamePhase.milieu => GameConstants.eventProbabilitiesMilieu,
      GamePhase.fin => GameConstants.eventProbabilitiesFin,
    };

    final List<Tile> tiles = <Tile>[];
    final List<Portal> newPortals = <Portal>[];
    for (int i = 0; i < after.tiles.length; i++) {
      final Tile old = before.tiles[i];
      final Tile newTile = after.tiles[i];
      final Position position = Position(newTile.x, newTile.y);

      if (old.discovered || !newTile.discovered || !newTile.walkable) {
        tiles.add(newTile);
        continue;
      }
      if (starts.contains(position) || occupied.contains(position)) {
        tiles.add(newTile);
        continue;
      }
      // Jamais de contenu sur une case de BOSS (retours playtest 19/09 :
      // un boss partageait sa case avec un monstre), ni de portail, ni
      // dans la CANTINA (zone sanctuarisée — aucun monstre, objet, allié
      // ou soin dedans).
      if (avoidPositions.contains(position) ||
          newTile.cantina ||
          existingPortals.any((Portal portal) => portal.position == position)) {
        tiles.add(newTile);
        continue;
      }

      // Tirage du type d'événement.
      final double roll = rng.nextDouble();
      double cumulative = 0.0;
      String event = GameConstants.eventTypes.last;
      for (int e = 0; e < probabilities.length; e++) {
        cumulative += probabilities[e];
        if (roll < cumulative) {
          event = GameConstants.eventTypes[e];
          break;
        }
      }

      switch (event) {
        case 'monstre':
          tiles.add(
              newTile.copyWith(monster: MonsterConstants.randomMonster(rng)));
        case 'allie':
          tiles.add(newTile.copyWith(
              ally: CardConstants.randomAllyCard(rng)));
        case 'objet':
          if (rng.nextBool()) {
            tiles.add(newTile.copyWith(
                weapon: CardConstants.randomWeaponCard(rng)));
          } else {
            tiles.add(newTile.copyWith(
                armor: CardConstants.randomArmorCard(rng)));
          }
        case 'soin':
          // Retours playtest 20/09 : jamais deux soins sur des cases
          // voisines (Chebyshev 1) — on vérifie l'état révélé ET les
          // cases déjà décidées dans CE passage.
          bool healNearby = false;
          for (int dy = -1; dy <= 1 && !healNearby; dy++) {
            for (int dx = -1; dx <= 1 && !healNearby; dx++) {
              if (dx == 0 && dy == 0) continue;
              final int nx = newTile.x + dx;
              final int ny = newTile.y + dy;
              if (nx < 0 || ny < 0 || nx >= after.width || ny >= after.height) {
                continue;
              }
              final int neighborIndex = ny * after.width + nx;
              if (after.tiles[neighborIndex].healSite ||
                  (neighborIndex < tiles.length && tiles[neighborIndex].healSite)) {
                healNearby = true;
              }
            }
          }
          tiles.add(newTile.copyWith(healSite: !healNearby));
        case 'portail':
          // Sprint 5 : uniquement sur le bord du plateau, max 4, destinations
          // différentes. La planète liée est générée par le GameService.
          // Fix playtest 10/09 : compter AUSSI les portails posés dans CE
          // populate (une grosse révélation pouvait en poser 6+ d'un coup).
          if (existingPortals.length + newPortals.length < 4 &&
              after.isOnEdge(newTile.x, newTile.y)) {
            final Set<PlanetType> linked =
                existingPortals.map((Portal p) => p.destination).toSet();
            final List<PlanetType> free = PlanetConstants.secondaryPlanets
                .where((PlanetType t) => !linked.contains(t))
                .toList();
            if (free.isNotEmpty) {
              final PlanetType destination =
                  free[rng.nextInt(free.length)];
              newPortals.add(Portal(
                destination: destination,
                position: position,
                discovered: true,
              ));
            }
            tiles.add(newTile);
          } else {
            tiles.add(newTile);
          }
        default:
          tiles.add(newTile);
      }
    }
    return (planet: after.withTiles(tiles), newPortals: newPortals);
  }

  /// Révèle le brouillard autour de [center] (rayon 3 cases — CDC §5).
  ///
  ///  - les cases dans le rayon passent à `discovered = true` (une
  ///    découverte est conservée définitivement — GDD §3) ;
  ///  - `visible` est réinitialisé partout puis posé sur le rayon courant :
  ///    seules les cases actuellement dans le rayon du joueur actif sont
  ///    « visibles » (brouillard partagé hot-seat : les découvertes des
  ///    joueurs fusionnent, décision du 07/09/2026) ;
  ///  - le rayon est une distance de Chebyshev : carré de 7x7 cases
  ///    (décision du 07/09/2026, rayon réduit de 6 à 3 cases).
  Planet revealFogAround(Planet planet, Position center, {int? radius}) {
    final int r = radius ?? GameConstants.fogVisibleRadius;
    final List<Tile> newTiles = <Tile>[];

    for (final Tile tile in planet.tiles) {
      final bool within =
          Position(tile.x, tile.y).chebyshevDistanceTo(center) <= r;
      newTiles.add(tile.copyWith(
        discovered: tile.discovered || within,
        visible: within,
      ));
    }
    return planet.withTiles(newTiles);
  }

  // ---------------------------------------------------------------------------
  // Portails (GDD §5) — Sprint 5
  // ---------------------------------------------------------------------------

  /// Fait apparaître des portails si les conditions du GDD sont remplies :
  ///  - au moins un joueur a atteint le niveau 3 ;
  ///  - uniquement sur une case libre située sur le bord du plateau (CDC §8) ;
  ///  - maximum 4 portails, chacun vers une planète secondaire différente.
  // TODO(Sprint 5) : implémenter l'apparition, la découverte et le voyage
  // via les portails, ainsi que la génération des planètes secondaires
  // (50 cases chacune, une seule génération possible — GDD §4).
  // (L'apparition des portails est gérée dans populateNewlyDiscoveredTiles —
  // événement « portail » du GDD addendum §4.1.)

  // ---------------------------------------------------------------------------
  // Boss mobiles (GDD §12) — Sprint 5
  // ---------------------------------------------------------------------------

  /// À la fin de chaque tour de joueur : 50 % de chance que chaque boss se
  /// déplace d'une case vers une case jouable adjacente.
  // TODO(Sprint 5) : déplacement des boss (50 % de chance, une case, fin de
  // chaque tour de joueur), fuite et réapparition en zone non visible après
  // une victoire, mort définitive quand tous les joueurs l'ont vaincu.
  /// Sprint 5 : à chaque fin de tour, chaque boss actif bouge à 50 % vers
  /// une case jouable libre adjacente de sa planète ; les boss fugqués
  /// réapparaissent en zone non découverte de leur planète ; les boss
  /// définitivement morts ne bougent plus.
  /// La case contient-elle du contenu d'événement (monstre, allié, objet,
  /// soin) ? Les boss ne doivent JAMAIS partager leur case avec un contenu
  /// (retours playtest 19/09) ni bloquer le portail central.
  static bool tileHasEvent(Planet planet, Position position) {
    final Tile tile = planet.tileAt(position.x, position.y);
    return tile.monster != null ||
        tile.ally != null ||
        tile.weapon != null ||
        tile.armor != null ||
        tile.healSite;
  }

  /// Case libre pour un boss : jouable, hors joueurs, sans contenu et hors
  /// portail central (retours playtest 19/09).
  static bool isFreeForBoss(Planet planet, Position position,
      Set<Position> occupied) {
    if (!planet.isWalkableAt(position.x, position.y)) return false;
    if (occupied.contains(position)) return false;
    if (position == PlanetConstants.secondaryPortalPosition) return false;
    return !tileHasEvent(planet, position);
  }

  ({List<Boss> bosses, Map<PlanetType, Planet> planets}) moveBossesAtTurnEnd({
    required List<Boss> bosses,
    required Map<PlanetType, Planet> planets,
    required List<Player> players,
    required Random rng,
  }) {
    final int aliveCount =
        players.where((Player p) => !p.eliminated).length;
    final List<Boss> result = List<Boss>.of(bosses);
    final Map<PlanetType, Planet> updatedPlanets = <PlanetType, Planet>{
      ...planets,
    };

    for (int i = 0; i < result.length; i++) {
      Boss boss = result[i];
      if (boss.isDefinitivelyDead(aliveCount)) continue;
      final Planet? planet = updatedPlanets[boss.planet];
      if (planet == null) continue;
      final Set<Position> occupied = players
          .where((Player p) => p.planet == boss.planet && !p.eliminated)
          .map((Player p) => p.position)
          .toSet();

      if (boss.isGone) {
        // Réapparition en zone non VISIBLE (GDD §12) — ordre de repli :
        // 1) cases non découvertes (idéal) ;
        // 2) sinon cases hors du rayon de vue des joueurs (fix playtest :
        //    une planète entièrement découverte laissait le boss fugué
        //    pour toujours, impossible à rebattre) ;
        // 3) sinon toute case libre. Toujours SANS contenu et hors portail
        //    central (fix 19/09) — repli non filtré en dernier ressort
        //    pour ne jamais laisser un boss fugué sans case.
        final List<Position> hidden = <Position>[];
        final List<Position> outOfSight = <Position>[];
        final List<Position> free = <Position>[];
        final List<Position> anyFree = <Position>[];
        for (final Tile tile in planet.tiles) {
          final Position position = Position(tile.x, tile.y);
          if (!tile.walkable || occupied.contains(position)) continue;
          if (position == PlanetConstants.secondaryPortalPosition) continue;
          anyFree.add(position);
          if (tileHasEvent(planet, position)) continue;
          free.add(position);
          if (!tile.discovered) {
            hidden.add(position);
          } else if (!tile.visible) {
            outOfSight.add(position);
          }
        }
        final List<Position> candidates =
            hidden.isNotEmpty ? hidden : (outOfSight.isNotEmpty ? outOfSight : free);
        final List<Position> pool =
            candidates.isNotEmpty ? candidates : anyFree;
        if (pool.isEmpty) continue;
        result[i] = boss.copyWith(
          position: pool[rng.nextInt(pool.length)],
          isGone: false,
        );
        continue;
      }

      if (rng.nextDouble() >= GameConstants.bossMoveChance) continue;
      final List<Position> free = <Position>[
        for (final Position neighbor
            in neighborPositions(boss.position, planet))
          if (isFreeForBoss(planet, neighbor, occupied)) neighbor,
      ];
      if (free.isEmpty) continue;
      result[i] =
          boss.copyWith(position: free[rng.nextInt(free.length)]);
    }
    return (bosses: result, planets: updatedPlanets);
  }

  /// Génère une planète secondaire (Sprint 5) : grille 8x7 (56 cases),
  /// 50 jouables / 6 bloquées, connectivité garantie, portail de retour
  /// protégé au centre (3,3).
  Planet generateSecondaryPlanet(PlanetType type, {required int seed}) {
    final Random rng = Random(seed);
    const int width = PlanetConstants.secondaryGridWidth;
    const int height = PlanetConstants.secondaryGridHeight;
    const int blockedCount = PlanetConstants.secondaryBlockedTiles;
    const Position portal = PlanetConstants.secondaryPortalPosition;

    for (int attempt = 0; attempt < 200; attempt++) {
      final Set<Position> blocked = <Position>{};
      while (blocked.length < blockedCount) {
        final Position candidate =
            Position(rng.nextInt(width), rng.nextInt(height));
        if (candidate == portal || blocked.contains(candidate)) continue;
        blocked.add(candidate);
        if (!_remainingWalkableConnected(
            blocked: blocked, width: width, height: height)) {
          blocked.remove(candidate);
        }
      }
      final List<Tile> tiles = <Tile>[];
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          tiles.add(Tile(x: x, y: y, walkable: !blocked.contains(Position(x, y))));
        }
      }
      final Planet planet = Planet(
        name: PlanetConstants.displayNames[type] ?? type.name,
        type: type,
        width: width,
        height: height,
        tiles: tiles,
      );
      if (planet.playableTileCount !=
          PlanetConstants.secondaryPlanetTileCount) {
        continue;
      }
      if (!isFullyConnected(planet)) continue;
      return planet;
    }
    throw StateError(
        'Génération de la planète secondaire impossible (type: $type).');
  }
}
