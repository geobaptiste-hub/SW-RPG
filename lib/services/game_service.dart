import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/board_constants.dart';
import '../core/constants/character_constants.dart';
import '../core/constants/planet_constants.dart'
    show PlanetConstants;
import '../core/constants/enums.dart'
    show AllyType, GamePhase, GameMode, GameStatus, Rarity, TeamSide;
import '../core/constants/game_constants.dart';
import '../core/constants/monster_constants.dart';
import '../models/ally.dart';
import '../models/boss.dart';
import '../models/cantina_zone.dart';
import '../models/game_state.dart';
import '../models/planet.dart';
import '../models/player.dart';
import '../models/portal.dart';
import '../models/armor.dart';
import '../models/patapuche.dart';
import '../models/teleport_portal.dart';
import '../models/tile.dart';
import '../models/weapon.dart';
import 'map_service.dart';
import 'save_service.dart';

/// Type d'événement à retirer d'une case consommée.
enum TileEventKind { ally, weapon, armor, healSite, none }

/// Résultat de la victoire sur un monstre, appliqué à la partie.
class MonsterVictoryOutcome {
  final int playerHp;
  final bool playerEliminated;
  final int xpGained;

  const MonsterVictoryOutcome({
    required this.playerHp,
    required this.playerEliminated,
    this.xpGained = 0,
  });
}

/// Résultat d'un déplacement du joueur actif (Sprint 3) : le pion entre
/// toujours dans la case ; le résultat indique la rencontre éventuelle.
enum MoveResult {
  /// Déplacement simple, aucune rencontre.
  moved,

  /// La case contient un monstre : combat direct (GDD §10).
  monsterEncounter,

  /// La case contient un autre joueur : combat entre joueurs (GDD §13).
  playerEncounter,

  /// La case propose un allié au recrutement (Sprint 4).
  allyEncounter,

  /// La case contient une arme ou une tenue (Sprint 4).
  itemEncounter,

  /// La case « Soin » : lancer le dé (règle du game design, Sprint 4).
  healEncounter,

  /// La case contient un boss déverrouillé : combat de boss (Sprint 5).
  bossEncounter,

  /// Boss présent mais verrouillé (aucun joueur niveau 5) : entrée refusée.
  bossBlocked,

  /// Voyage par portail accompli (Sprint 5).
  portalTravel,

  /// Entrée dans la CANTINA par sa case-portail (retours playtest 19/09).
  cantinaTravel,

  /// Case de TÉLÉPORTATION utilisée : projection vers un point éloigné
  /// (retours playtest 20/09).
  teleport,

  /// Don de PATAPUCHE récupéré : +100 ATK et +100 PV (retours playtest
  /// 20/09).
  patapuche,

  /// Case de consommations de la CANTINA : PV remis au maximum (retours
  /// playtest 19/09).
  cantinaDrink,
}

/// Phase de partie courante (GDD addendum §4.1) : pilote la distribution
/// des événements lors des découvertes.
GamePhase phaseOf(GameState state) {
  if (state.players.any((Player p) => !p.eliminated && p.level >= 5)) {
    return GamePhase.fin;
  }
  if (state.players.any((Player p) => !p.eliminated && p.level >= 3)) {
    return GamePhase.milieu;
  }
  return GamePhase.debut;
}

/// Configuration d'une nouvelle partie, construite par l'assistant de
/// création (CDC §4) : mode, nombre de joueurs / équipes, planète et
/// personnages choisis à tour de rôle.
class NewGameConfig {
  final GameMode mode;

  /// Nombre total de joueurs (2 à 8).
  final int playerCount;

  /// Taille des équipes en mode Équipes (2, 3 ou 4) ; 0 en chacun pour soi.
  final int teamSize;

  /// Planète de départ choisie à l'étape 3.
  final PlanetType planetType;

  /// Personnages choisis à l'étape 4, dans l'ordre des joueurs
  /// (le joueur 1 correspond à l'index 0).
  final List<CharacterDefinition> characters;

  const NewGameConfig({
    required this.mode,
    required this.playerCount,
    required this.teamSize,
    required this.planetType,
    required this.characters,
  }) : assert(characters.length == playerCount);
}

/// Providers Riverpod.
final mapServiceProvider = Provider<MapService>((ref) => MapService());

final saveServiceProvider = Provider<SaveService>((ref) => SaveService());

final gameControllerProvider =
    NotifierProvider<GameController, GameState?>(GameController.new);

/// Joueur actif dérivé de l'état (null si aucune partie en cours).
final activePlayerProvider = Provider<Player?>((ref) {
  final GameState? state = ref.watch(gameControllerProvider);
  if (state == null) return null;
  return state.activePlayer;
});

/// Indique si une sauvegarde existe (bouton « Reprendre Partie »).
final hasSaveProvider = FutureProvider<bool>((ref) async {
  final SaveService saveService = ref.watch(saveServiceProvider);
  return saveService.hasSave();
});

/// Contrôleur global de la partie : création, reprise, dé, déplacement,
/// fin de tour, autosave, chrono (Architecture v1.0 — GameService).
class GameController extends Notifier<GameState?> {
  final Random _diceRandom = Random();

  /// Offres de rencontre en attente de décision (transitoire, non
  /// sauvegardé) — lus par les dialogs du plateau après un déplacement.
  Ally? pendingAllyOffer;
  Weapon? pendingWeaponOffer;
  Armor? pendingArmorOffer;

  /// Résultat du dernier lancer de soin (pour le dialog).
  int? lastHealRoll;
  int? lastHealAmount;

  /// Dégâts d'une Carte Spéciale ennemie rencontrée (transitoire, pour le
  /// dialog — Sprint 4.3). Null si la rencontre n'est pas une spéciale
  /// ennemie.
  int? pendingSpecialDamage;

  /// Planètes secondaires dévoilées lors du dernier déplacement
  /// (transitoire — notification « 🌌 ... se dévoile ! »).
  final List<PlanetType> lastPortalDiscoveries = <PlanetType>[];

  /// Planètes où un boss vient de s'éveiller (transitoire — notification).
  final List<PlanetType> bossAwakeningPlanets = <PlanetType>[];

  /// Vrai au premier passage d'un joueur au niveau 4 (transitoire —
  /// annonce « 👥 Des doubles monstres apparaissent ! »).
  bool doubleMonstersPending = false;

  /// Vrai à l'apparition de PATAPUCHE (transitoire — dialog d'annonce
  /// avec l'illustration `patapuche/apparition`).
  bool patapuchePending = false;

  /// Nom de l'allié ennemi qui vient d'attaquer (transitoire — dialog).
  String? pendingEnemyAllyName;

  /// Journal de partie (GDD §14 — Sprint 6) : événements marquants, en
  /// mémoire (non sauvegardé, remis à zéro à la sortie de partie).
  final List<String> gameLog = <String>[];

  /// Compteur incrémenté à chaque entrée : permet à l'écran Journal de se
  /// rafraîchir (ValueListenableBuilder).
  final ValueNotifier<int> gameLogVersion = ValueNotifier<int>(0);

  /// Inscrit un événement horodaté au tour courant dans le journal.
  void log(String line) {
    gameLog.add('Tour ${state?.turn ?? 1} — $line');
    if (gameLog.length > 300) {
      gameLog.removeRange(0, gameLog.length - 300);
    }
    gameLogVersion.value++;
  }

  @override
  GameState? build() => null;

  MapService get _mapService => ref.read(mapServiceProvider);
  SaveService get _saveService => ref.read(saveServiceProvider);

  // ---------------------------------------------------------------------------
  // Création / reprise de partie
  // ---------------------------------------------------------------------------

  /// Crée une nouvelle partie à partir de la configuration de l'assistant
  /// (CDC §4), place les joueurs, applique le brouillard, tire le premier
  /// joueur au hasard, puis sauvegarde.
  Future<GameState> createNewGame(NewGameConfig config) async {
    // FIX web 19/09 : `1 << 32` est évalué à 0 par les opérations 32 bits
    // de JavaScript (dart2js) — `nextInt(0)` lançait une RangeError et la
    // création de partie échouait sur l'iPad. Borne explicite sûre partout.
    final int seed = _diceRandom.nextInt(0x7FFFFFFF);
    final Planet planet =
        _mapService.generateStartPlanet(config.planetType, seed: seed);

    // Attribution des départs selon le nombre de joueurs (CDC §5).
    final List<Position> starts =
        BoardConstants.startsForPlayerCount(config.playerCount);

    final List<Player> players = <Player>[];
    for (int i = 0; i < config.playerCount; i++) {
      final CharacterDefinition character = config.characters[i];
      players.add(Player(
        id: 'player_${i + 1}',
        name: character.name,
        faction: character.faction,
        position: starts[i],
        level: 1,
        xp: 0,
        attack: GameConstants.attackForLevel(1),
        hp: GameConstants.hpForLevel(1),
        maxHp: GameConstants.hpForLevel(1),
        team: _teamForPlayer(config, i),
      ));
    }

    // Premier joueur tiré aléatoirement (CDC §4).
    final int firstPlayerIndex = _diceRandom.nextInt(players.length);

    // La PORTE de la cantina est ancrée de façon déterministe par la seed
    // (une case de la planète principale qui sert de portail vers la
    // mini-zone 3x3 — retours playtest 19/09 v2). La CASE DE TÉLÉPORTATION
    // est ancrée de la même façon (retours playtest 20/09).
    final Position? cantinaDoor = _mapService.cantinaAnchorFor(seed);
    final Position? teleportDoor = _mapService.teleportAnchorFor(seed);
    final Position? patapucheDoor = _mapService.patapucheAnchorFor(seed);

    GameState state = GameState(
      schemaVersion: GameState.currentSchemaVersion,
      gameId:
          'game_${DateTime.now().millisecondsSinceEpoch}_${_diceRandom.nextInt(9999)}',
      seed: seed,
      mode: config.mode,
      teamSize: config.teamSize,
      planetType: config.planetType,
      currentPlanet: planet,
      players: players,
      turn: 1,
      currentPlayerIndex: firstPlayerIndex,
      gameTimeSeconds: 0,
      movementPointsRemaining: 0,
      lastDiceRoll: null,
      bosses: const [],
      portals: const [],
      cantina: cantinaDoor == null
          ? null
          : CantinaZone(planet: config.planetType, anchor: cantinaDoor),
      teleport: teleportDoor == null
          ? null
          : TeleportPortal(planet: config.planetType, position: teleportDoor),
      patapuche: patapucheDoor == null
          ? null
          : Patapuche(planet: config.planetType, position: patapucheDoor),
      status: GameStatus.inProgress,
    );

    // Brouillard de guerre appliqué : la carte est cachée, seul le rayon
    // autour du premier joueur est révélé (GDD §3, CDC §6).
    final Set<Position> occupied =
        players.map((Player p) => p.position).toSet();
    final populate = _mapService.populateNewlyDiscoveredTiles(
      before: planet,
      after: _mapService.revealFogAround(
          planet, players[firstPlayerIndex].position),
      phase: phaseOf(state),
      rng: _diceRandom,
      occupied: occupied,
      existingPortals: const [],
      bossUnlocked: false,
      allyBiasPlayer: players[firstPlayerIndex],
      avoidPositions: <Position>{
        ..._bossPositions(state, planet.type),
        // Aucun contenu tiré sur la porte de la cantina, de téléport, ni
        // sur la case de Patapuche.
        if (state.cantina != null) state.cantina!.anchor,
        if (state.teleport != null) state.teleport!.position,
        if (state.patapuche != null) state.patapuche!.position,
      },
    );
    final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
      planet.type: populate.planet,
      // La mini-zone cantina 3x3 existe dès la création (retours playtest
      // 19/09 v2).
      if (cantinaDoor != null)
        PlanetType.cantina: _mapService.generateCantinaPlanet(),
    };
    final List<Player> placed = <Player>[
      for (final Player p in players)
        p.copyWith(planet: planet.type),
    ];
    state = state.copyWith(
      currentPlanet: populate.planet,
      planets: planets,
      players: placed,
    );

    state = state.copyWith(savedAt: DateTime.now());
    this.state = state;
    log('🎮 La partie commence sur '
        '${PlanetConstants.displayNames[config.planetType] ?? config.planetType.name} '
        'avec ${config.playerCount} joueurs !');
    await _saveService.save(state);
    return state;
  }

  /// En mode Équipes, les joueurs 1..N/2 forment l'équipe A et les suivants
  /// l'équipe B.
  ///
  /// TODO(Design) : le GDD/CDC ne précisent pas la répartition des équipes
  /// dans l'ordre de jeu. Choix actuel : blocs contigus (Équipe A d'abord,
  /// puis Équipe B). Une répartition alternée A,B,A,B est une alternative.
  /// À confirmer avec le game design.
  TeamSide? _teamForPlayer(NewGameConfig config, int playerIndex) {
    if (config.mode == GameMode.chacunPourSoi) return null;
    // Blocs contigus de teamSize joueurs : 0..1 → Équipe A, 2..3 → B, etc.
    final List<TeamSide> sides = TeamSide.values;
    return sides[(playerIndex ~/ config.teamSize).clamp(0, sides.length - 1)];
  }

  /// Reprend la partie sauvegardée (bouton « Reprendre Partie »).
  /// Renvoie vrai si la reprise a réussi.
  Future<bool> resumeGame() async {
    final GameState? loaded = await _saveService.load();
    if (loaded == null) return false;
    state = loaded;
    return true;
  }

  /// Quitte l'écran de jeu en conservant la dernière sauvegarde.
  void exitGame() {
    state = null;
    gameLog.clear();
    gameLogVersion.value++;
  }

  /// Sauvegarde l'état courant sans quitter (fix 19/09 : utilisée par
  /// « Sauvegarder et quitter » — l'autosave ne s'appliquant qu'à la fin
  /// du tour, quitter en pleine partie perdait la progression du tour
  /// en cours : déplacements, combats, trouvailles…).
  Future<void> saveGame() async {
    final GameState? current = state;
    if (current == null || current.status != GameStatus.inProgress) return;
    await _saveService.save(current.copyWith(savedAt: DateTime.now()));
  }

  // ---------------------------------------------------------------------------
  // Dé (GDD §6)
  // ---------------------------------------------------------------------------

  /// Lance le dé à 6 faces : la valeur devient le nombre de points de
  /// déplacement du joueur actif.
  ///
  /// TODO(V2) : certaines cartes ou compétences modifieront le déplacement
  /// (GDD §6) — à intégrer ici lors de l'arrivée des cartes.
  void rollDice() {
    final GameState? current = state;
    if (current == null || current.status != GameStatus.inProgress) return;
    // Un seul lancer par tour : impossible tant que des points restent.
    if (current.movementPointsRemaining > 0) return;
    if (current.lastDiceRoll != null) return;

    final int roll = _diceRandom.nextInt(GameConstants.diceSides) + 1;
    // Soutien « doubleMoveDice » : la valeur du dé est multipliée par deux
    // pour le déplacement (retours playtest 10/09/2026). Le dé affiché
    // reste la valeur brute.
    final int points =
        current.activePlayer.hasDoubleMoveDice ? roll * 2 : roll;
    state = current.copyWith(lastDiceRoll: roll, movementPointsRemaining: points);
  }

  // ---------------------------------------------------------------------------
  // Déplacement (GDD §6, CDC §7)
  // ---------------------------------------------------------------------------

  /// Cibles de déplacement valides pour le joueur actif. Les cases des
  /// boss DÉJÀ VAINCUS par ce joueur sont exclues (retours playtest : un
  /// vainqueur ne peut pas rebattre le même boss — il reste disponible
  /// pour les autres joueurs).
  List<Position> validMoveTargets() {
    final GameState? current = state;
    if (current == null) return const [];
    final List<Position> targets = _mapService.validMoveTargets(
      planet: current.currentPlanet,
      players: current.players,
      activePlayerIndex: current.currentPlayerIndex,
    );
    final Player active = current.activePlayer;
    final int aliveCount =
        current.players.where((Player p) => !p.eliminated).length;
    bool bossUnavailable(Position p) => current.bosses.any((Boss boss) =>
        boss.planet == current.planetType &&
        !boss.isGone &&
        !boss.isDefinitivelyDead(aliveCount) &&
        boss.position == p &&
        // Déjà vaincu par CE joueur : il ne peut pas le rebattre.
        (boss.defeatedByPlayerIds.contains(active.id) ||
            // Boss de SA PROPRE faction : il ne compte pas pour la victoire
            // et n'est pas combattable (retours playtest).
            PlanetConstants.bossFactionByType[boss.type] == active.faction));
    return targets
        .where((Position p) => !bossUnavailable(p))
        .toList();
  }

  /// Déplace le joueur actif sur la case voisine ([x], [y]) :
  /// le pion avance, le brouillard se révèle, le compteur diminue (CDC §7).
  /// Le joueur recommence jusqu'à atteindre 0 points (GDD §6).
  MoveResult moveActivePlayerTo(int x, int y) {
    final GameState? current = state;
    if (current == null || current.status != GameStatus.inProgress) {
      return MoveResult.moved;
    }
    if (current.movementPointsRemaining <= 0) return MoveResult.moved;

    final Position target = Position(x, y);
    if (!validMoveTargets().contains(target)) return MoveResult.moved;

    // Boss sur la case cible ? Verrouille tant qu'aucun joueur n'est N5
    // (Sprint 5) : l'entree est refusee, le point de deplacement est perdu.
    final Player movingBefore = current.activePlayer;
    Boss? bossAtTarget;
    final int aliveCount =
        current.players.where((Player p) => !p.eliminated).length;
    for (final Boss boss in current.bosses) {
      if (boss.planet != movingBefore.planet || boss.isGone) continue;
      if (boss.isDefinitivelyDead(aliveCount)) continue;
      if (boss.position == target) {
        bossAtTarget = boss;
        break;
      }
    }
    final bool unlocked =
        current.players.any((Player p) => !p.eliminated && p.level >= 5);
    if (bossAtTarget != null && !unlocked) {
      state = current.copyWith(
          movementPointsRemaining: current.movementPointsRemaining - 1);
      return MoveResult.bossBlocked;
    }

    final List<Player> newPlayers = List<Player>.of(current.players);
    final Player moving = newPlayers[current.currentPlayerIndex];
    final PlanetType movingPlanet = moving.planet;
    newPlayers[current.currentPlayerIndex] =
        moving.copyWith(position: target);

    final Planet before =
        current.planets[movingPlanet] ?? current.currentPlanet;
    final populate = _mapService.populateNewlyDiscoveredTiles(
      before: before,
      after: _mapService.revealFogAround(before, target),
      phase: phaseOf(current),
      rng: _diceRandom,
      occupied: newPlayers
          .where((Player p) => p.planet == movingPlanet)
          .map((Player p) => p.position)
          .toSet(),
      existingPortals: current.portals,
      avoidPositions: <Position>{
        ..._bossPositions(current, movingPlanet),
        // Aucun contenu tiré sur la porte de la cantina ni de téléport.
        if (current.cantina?.planet == movingPlanet)
          current.cantina!.anchor,
        if (current.teleport?.planet == movingPlanet) ...<Position>[
          current.teleport!.position,
          if (current.teleport!.position2 != null)
            current.teleport!.position2!,
        ],
        // Aucun contenu tiré sur la case de Patapuche.
        if (current.patapuche?.planet == movingPlanet)
          current.patapuche!.position,
      },
      bossUnlocked: current.players
          .any((Player p) => !p.eliminated && p.level >= 5),
      // Doubles monstres (retours playtest 20/09) : débloqués au 1er N4.
      doubleMonstersUnlocked: current.players
          .any((Player p) => !p.eliminated && p.level >= 4),
      // Ratio allié ami/ennemi selon le niveau du joueur actif (20/09).
      allyBiasPlayer: movingBefore,
    );

    // Planètes secondaires dévoilées par un portail découvert (Sprint 5).
    final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
      ...current.planets,
    };
    final List<Portal> portals = List<Portal>.of(current.portals);
    for (final Portal portal in populate.newPortals) {
      portals.add(portal);
      log('🌌 Un portail vers '
          '${PlanetConstants.displayNames[portal.destination] ?? portal.destination.name} '
          'a été découvert !');
      if (!planets.containsKey(portal.destination)) {
        planets[portal.destination] = _mapService.generateSecondaryPlanet(
            portal.destination,
            seed: current.seed + portal.destination.index * 977);
        lastPortalDiscoveries.add(portal.destination);
      }
    }
    planets[movingPlanet] = populate.planet;

    state = current.copyWith(
      players: newPlayers,
      planets: planets,
      portals: portals,
      currentPlanet: populate.planet,
      planetType: movingPlanet,
      movementPointsRemaining: current.movementPointsRemaining - 1,
    );

    // Boss déverrouillé sur la case cible : combat de boss (Sprint 5) —
    // SAUF si CE joueur l'a déjà vaincu, ou si c'est le boss de SA PROPRE
    // faction (il ne compte pas pour la victoire et n'est pas combattable
    // — retours playtest) ; le pion entre alors sur la case sans combat.
    if (bossAtTarget != null &&
        !bossAtTarget.defeatedByPlayerIds.contains(movingBefore.id) &&
        PlanetConstants.bossFactionByType[bossAtTarget.type] !=
            movingBefore.faction) {
      return MoveResult.bossEncounter;
    }

    // Rencontres : le pion entre toujours dans la case ; priorité au
    // monstre, puis au joueur adverse, puis aux événements Sprint 4.
    final Tile targetTile = populate.planet.tileAt(x, y);
    if (targetTile.monster != null) return MoveResult.monsterEncounter;

    for (int i = 0; i < newPlayers.length; i++) {
      if (i != current.currentPlayerIndex &&
          !newPlayers[i].eliminated &&
          newPlayers[i].planet == movingPlanet &&
          newPlayers[i].position == target) {
        return MoveResult.playerEncounter;
      }
    }

    final Player active = newPlayers[current.currentPlayerIndex];
    if (targetTile.ally != null) {
      final Ally offered = targetTile.ally!;
      pendingSpecialDamage = null;

      final bool enemyAlly = offered.faction != active.faction &&
          offered.faction != active.faction.alliedFaction;
      if (enemyAlly) {
        // Allié de faction ENNEMIE (Sprint 4.2 bis) : il attaque directe-
        // ment — aucun recrutement, la carte est consommée. Dégâts selon
        // la rareté/nuker/spéciale, tempérés par le niveau et plafonnés
        // (retours playtest : plus de mort instantanée en une carte).
        // pendingAllyOffer est rempli aussi : le dialog du plateau en a
        // besoin pour afficher la carte (bug « case sans effet » du
        // playtest — le dialog ne s'affichait jamais).
        pendingAllyOffer = offered;
        final int malus = GameConstants.scaleIncomingDamage(
          enemyRecruitMalus(offered, active.faction),
          level: active.level,
          maxHp: active.totalMaxHp,
        );
        pendingSpecialDamage = malus;
        pendingEnemyAllyName = offered.name;
        final int hp = max(active.hp - malus, 0);
        final Player victim = newPlayers[current.currentPlayerIndex];
        if (hp > 0) {
          newPlayers[current.currentPlayerIndex] = victim.copyWith(hp: hp);
        } else {
          // Mort imminente : le soutien « empêche la mort » fait survivre à
          // 1 PV. La carte est retirée DIRECTEMENT dans newPlayers (pas
          // d'écriture d'état intermédiaire : elle serait écrasée par
          // l'affectation finale).
          final int cardIndex = victim.allies.indexWhere((Ally a) =>
              a.type == AllyType.soutien && a.ability == 'preventDeath');
          if (cardIndex >= 0) {
            final List<Ally> allies =
                List<Ally>.of(victim.allies)..removeAt(cardIndex);
            newPlayers[current.currentPlayerIndex] =
                victim.copyWith(hp: 1, eliminated: false, allies: allies);
          } else {
            newPlayers[current.currentPlayerIndex] =
                victim.copyWith(hp: 0, eliminated: true);
          }
        }
      } else {
        pendingAllyOffer = offered;
        pendingEnemyAllyName = null;
      }

      _clearTileEvent(populate.planet, target, TileEventKind.ally);
      state = _applySurvivorCheck(
        state!.copyWith(players: newPlayers),
      );
      return MoveResult.allyEncounter;
    }
    if (targetTile.weapon != null) {
      final Weapon weapon = targetTile.weapon!;
      if (weapon.rarity.index >= Rarity.epique.index) {
        log('⚔ ${active.name} a trouvé ${weapon.name} '
            '(${weapon.rarity.displayName}) !');
      }
      pendingWeaponOffer = targetTile.weapon;
      _clearTileEvent(populate.planet, target, TileEventKind.weapon);
      return MoveResult.itemEncounter;
    }
    if (targetTile.armor != null) {
      final Armor armor = targetTile.armor!;
      if (armor.rarity.index >= Rarity.epique.index) {
        log('🛡 ${active.name} a trouvé ${armor.name} '
            '(${armor.rarity.displayName}) !');
      }
      pendingArmorOffer = targetTile.armor;
      _clearTileEvent(populate.planet, target, TileEventKind.armor);
      return MoveResult.itemEncounter;
    }
    if (targetTile.healSite) {
      final int roll = _diceRandom.nextInt(6) + 1;
      final int heal =
          GameConstants.healForRoll(roll, maxHp: active.totalMaxHp);
      final int hp = min(active.hp + heal, active.totalMaxHp);
      lastHealRoll = roll;
      lastHealAmount = hp - active.hp;
      final List<Player> healedPlayers = List<Player>.of(newPlayers);
      healedPlayers[current.currentPlayerIndex] =
          active.copyWith(hp: hp);
      _clearTileEvent(populate.planet, target, TileEventKind.healSite);
      state = state!.copyWith(players: healedPlayers);
      return MoveResult.healEncounter;
    }
    // Consommation à la cantina (retours playtest 19/09) : PV remis au
    // MAXIMUM, sans dé ni consommation de la case — le verre est
    // illimité, il suffit d'avoir trouvé la cantina.
    if (targetTile.cantinaDrink) {
      final List<Player> refreshed = List<Player>.of(newPlayers);
      refreshed[current.currentPlayerIndex] =
          active.copyWith(hp: active.totalMaxHp);
      state = state!.copyWith(players: refreshed);
      return MoveResult.cantinaDrink;
    }

    // PORTE DE LA CANTINA (retours playtest 19/09 v2) : la case sert de
    // portail vers la mini-zone 3x3 — arrivée sur sa case d'entrée (1,2).
    // Vérifiée APRÈS les rencontres (un joueur adverse sur la porte se
    // combat normalement) et AVANT la recherche des portails.
    final CantinaZone? cantinaZone = current.cantina;
    if (cantinaZone != null &&
        moving.planet == cantinaZone.planet &&
        target == cantinaZone.anchor) {
      return _enterCantina(newPlayers, current);
    }

    // PATAPUCHE (retours playtest 20/09) : marcher sur sa case offre le
    // don (+100 ATK / +100 PV) — UNE SEULE FOIS par joueur. Sa case est
    // toujours sans monstre ni contenu (il les évite).
    final Patapuche? patapuche = current.patapuche;
    if (patapuche != null &&
        moving.planet == patapuche.planet &&
        target == patapuche.position) {
      if (patapuche.hasClaimed(moving.id)) {
        return MoveResult.moved; // déjà donné à ce joueur : rien ne se passe
      }
      // Le don : +100 ATK, +100 PV max et +100 PV actuels (permanents).
      final List<Player> rewarded = List<Player>.of(newPlayers);
      rewarded[current.currentPlayerIndex] =
          rewarded[current.currentPlayerIndex].copyWith(
        patapucheAtkBonusDelta: 100,
        patapucheHpBonusDelta: 100,
        hp: min(rewarded[current.currentPlayerIndex].hp + 100,
            rewarded[current.currentPlayerIndex].totalMaxHp + 100),
      );
      final List<String> claimed = <String>[...patapuche.claimedBy, moving.id];
      state = _applySurvivorCheck(current.copyWith(
        players: rewarded,
        patapuche: patapuche.copyWith(claimedBy: claimed),
      ));
      log('🎁 ${rewarded[current.currentPlayerIndex].name} reçoit le don de '
          'Patapuche : +100 ATK et +100 PV !');
      return MoveResult.patapuche;
    }

    // CASE DE TÉLÉPORTATION (retours playtest 20/09, v2 bidirectionnelle) :
    // deux cases liées — marcher sur l'une projette vers l'autre.
    final TeleportPortal? teleportPortal = current.teleport;
    if (teleportPortal != null &&
        moving.planet == teleportPortal.planet &&
        (target == teleportPortal.position ||
            target == teleportPortal.position2)) {
      return _useTeleportPortal(
          newPlayers, current, teleportPortal, target);
    }

    // Voyage par portail (Sprint 5) : aller-retour miroir.
    if (!PlanetConstants.startPlanets.contains(moving.planet)) {
      // CANTINA : la case d'entrée (1,2) sert de sortie (retours playtest
      // 19/09 v2).
      if (moving.planet == PlanetType.cantina) {
        if (targetTile.cantinaEntrance) {
          return _travelBack(newPlayers, current);
        }
        return MoveResult.moved;
      }
      // Planète secondaire : SEUL le portail central déclenche le retour
      // (fix 19/09 — LE bug du « coincé sur l'Étoile Noire » : la recherche
      // ci-dessous s'appliquait AUSSI sur les planètes secondaires, or les
      // positions des portails de la planète principale (jusqu'à x=19)
      // coïncident souvent avec une case de la grille 9x9 → un « voyage
      // fantôme » téléportait au centre d'une autre planète ET écrasait
      // returnPlanet/returnPosition avec la planète secondaire, si bien
      // que le portail central ne ramenait plus qu'à cette planète).
      if (target == PlanetConstants.secondaryPortalPosition) {
        return _travelBack(newPlayers, current);
      }
      return MoveResult.moved;
    }
    final Portal? portal = current.portals
        .where((Portal p) => p.position == target && p.discovered)
        .firstOrNull;
    if (portal != null) {
      return _travelThroughPortal(portal, newPlayers, current);
    }
    return MoveResult.moved;
  }

  /// CASE DE TÉLÉPORTATION (retours playtest 20/09, v2 bidirectionnelle) :
  /// DEUX cases liées — marcher sur l'une téléporte vers l'autre, dans les
  /// deux sens. À la première utilisation, la seconde case est tirée au
  /// hasard ÉLOIGNÉE (≥ 12 cases) et devient fixe ; les deux portails
  /// « restent ouverts » (images affichées).
  MoveResult _useTeleportPortal(List<Player> newPlayers, GameState current,
      TeleportPortal portal, Position target) {
    final Planet planet = current.currentPlanet;
    final Set<Position> occupied = <Position>{
      for (final Player p in current.players)
        if (!p.eliminated && p.id != current.activePlayer.id) p.position,
    };

    // L'ARRIVÉE : la case du couple opposée à celle foulée.
    TeleportPortal used = portal;
    Position arrival;
    if (portal.position2 == null) {
      // Première utilisation : tire la seconde case LOIN (≥ 12 cases),
      // libre de tout contenu et de tout autre joueur.
      final List<Position> far = <Position>[];
      final List<Position> any = <Position>[];
      for (final Tile t in planet.tiles) {
        final Position p = Position(t.x, t.y);
        if (!t.walkable ||
            occupied.contains(p) ||
            p == portal.position ||
            p == target ||
            t.monster != null ||
            t.monster2 != null ||
            t.ally != null ||
            t.weapon != null ||
            t.armor != null ||
            t.healSite ||
            t.cantina) {
          continue;
        }
        any.add(p);
        if (p.chebyshevDistanceTo(target) >= 12) far.add(p);
      }
      final List<Position> pool = far.isNotEmpty ? far : any;
      if (pool.isEmpty) return MoveResult.moved;
      final Position second = pool[_diceRandom.nextInt(pool.length)];
      used = portal.copyWith(position2: second, visited: true);
      arrival = second;
    } else {
      arrival = target == portal.position ? portal.position2! : portal.position;
    }

    final int index = current.currentPlayerIndex;
    final List<Player> players = List<Player>.of(newPlayers);
    players[index] = players[index].copyWith(position: arrival);
    log('🌀 ${players[index].name} est téléporté via le portail jumeau !');

    // Révélation autour du point d'arrivée.
    final Planet revealed =
        _mapService.revealFogAround(planet, arrival);
    final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
      ...current.planets,
      planet.type: revealed,
    };

    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: planets,
      currentPlanet: revealed,
      // Première utilisation : le couple de portails devient visible.
      teleport: used,
      movementPointsRemaining: current.movementPointsRemaining - 1,
    ));
    return MoveResult.teleport;
  }

  /// Entrée dans la CANTINA (retours playtest 19/09 v2) : la porte de la
  /// planète principale téléporte dans la mini-zone 3x3 — arrivée sur sa
  /// case d'entrée (1,2), retour mémorisé (returnPlanet/returnPosition).
  MoveResult _enterCantina(List<Player> newPlayers, GameState current) {
    final CantinaZone zone = current.cantina!;
    final int index = current.currentPlayerIndex;
    Planet cantina = current.planets[PlanetType.cantina] ??
        _mapService.generateCantinaPlanet();

    final List<Player> players = List<Player>.of(newPlayers);
    players[index] = players[index].copyWith(
      position: PlanetConstants.cantinaArrival,
      planet: PlanetType.cantina,
      returnPlanet: current.planetType,
      returnPosition: zone.anchor,
    );
    log('🍺 ${players[index].name} entre dans la cantina.');

    // Révélation autour du point d'arrivée + population (aucun contenu
    // n'est tiré : toutes les cases portent le marqueur cantina).
    final populate = _mapService.populateNewlyDiscoveredTiles(
      before: cantina,
      after: _mapService.revealFogAround(
          cantina, PlanetConstants.cantinaArrival),
      phase: phaseOf(current),
      rng: _diceRandom,
      occupied: players
          .where((Player p) =>
              p.planet == PlanetType.cantina && !p.eliminated)
          .map((Player p) => p.position)
          .toSet(),
      existingPortals: current.portals,
      avoidPositions: _bossPositions(current, PlanetType.cantina),
      bossUnlocked:
          current.players.any((Player p) => !p.eliminated && p.level >= 5),
    );
    cantina = populate.planet;

    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: <PlanetType, Planet>{
        ...current.planets,
        PlanetType.cantina: cantina,
      },
      currentPlanet: cantina,
      planetType: PlanetType.cantina,
      // Première entrée : `visited` → l'image remplace le logo jaune.
      cantina: zone.visited ? null : zone.copyWith(visited: true),
      // Le pas sur la case-portail coûte 1 point, comme tout déplacement.
      movementPointsRemaining: current.movementPointsRemaining - 1,
    ));
    return MoveResult.cantinaTravel;
  }

  /// Voyage ALLER : la planète courante devient la planète secondaire liée
  /// au portail, arrivée sur son portail central.
  MoveResult _travelThroughPortal(
      Portal portal, List<Player> newPlayers, GameState current) {
    final PlanetType destination = portal.destination;
    Planet secondary = current.planets[destination] ??
        _mapService.generateSecondaryPlanet(
            destination,
            seed: current.seed + destination.index * 977);
    final Position arrival = PlanetConstants.secondaryPortalPosition;

    final List<Player> players = List<Player>.of(newPlayers);
    final int index = current.currentPlayerIndex;
    players[index] = players[index].copyWith(
      position: arrival,
      planet: destination,
      returnPlanet: current.planetType,
      returnPosition: portal.position,
    );
    log('🚀 ${players[index].name} a voyagé vers '
        '${PlanetConstants.displayNames[destination] ?? destination.name}.');
    // Le portail traversé est marqué « visité » (retours playtest : son
    // illustration devient celle de la planète de destination).
    final List<Portal> traveledPortals = <Portal>[
      for (final Portal p in current.portals)
        if (p.position == portal.position &&
            p.destination == portal.destination)
          p.copyWith(visited: true)
        else
          p,
    ];

    // Révélation autour du point d'arrivée + population des nouvelles cases.
    final populate = _mapService.populateNewlyDiscoveredTiles(
      before: secondary,
      after: _mapService.revealFogAround(secondary, arrival),
      phase: phaseOf(current),
      rng: _diceRandom,
      occupied: players
          .where((Player p) => p.planet == destination)
          .map((Player p) => p.position)
          .toSet(),
      existingPortals: current.portals,
      avoidPositions: _bossPositions(current, destination),
      bossUnlocked: current.players
          .any((Player p) => !p.eliminated && p.level >= 5),
      doubleMonstersUnlocked: current.players
          .any((Player p) => !p.eliminated && p.level >= 4),
      allyBiasPlayer: players[index],
    );
    secondary = populate.planet;

    final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
      ...current.planets,
      destination: secondary,
    };
    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: planets,
      portals: traveledPortals,
      currentPlanet: secondary,
      planetType: destination,
      // Le pas sur la case du portail coûte 1 point (comme tout déplacement) ;
      // le voyage lui-même est gratuit — pas de second décrément.
      movementPointsRemaining: current.movementPointsRemaining - 1,
    ));
    return MoveResult.portalTravel;
  }

  /// Voyage RETOUR : le portail central de la planète secondaire ramène à la
  /// position du portail d'origine sur la planète principale.
  MoveResult _travelBack(List<Player> newPlayers, GameState current) {
    final int index = current.currentPlayerIndex;
    final Player traveler = newPlayers[index];
    // Garde-fou (fix 19/09) : sans planète/position d'origine connue
    // (partie sauvegardée corrompue…), le portail ne fait RIEN — surtout
    // pas une téléportation par défaut ; le pas n'est pas consommé.
    final PlanetType? originType = traveler.returnPlanet;
    final Position? originPos = traveler.returnPosition;
    if (originType == null || originPos == null) return MoveResult.moved;
    final PlanetType origin = originType;
    final Position originPosition = originPos;
    final Planet originPlanet = current.planets[origin] ?? current.currentPlanet;

    final List<Player> players = List<Player>.of(newPlayers);
    players[index] = players[index].copyWith(
      position: originPosition,
      planet: origin,
      clearReturn: true,
    );
    log('🚀 ${players[index].name} est revenu sur '
        '${PlanetConstants.displayNames[origin] ?? origin.name}.');

    final Planet revealed = _mapService.revealFogAround(
        originPlanet, originPosition);
    final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
      ...current.planets,
      origin: revealed,
    };
    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: planets,
      currentPlanet: revealed,
      planetType: origin,
      // Le pas sur le portail central coûte 1 point, comme à l'aller.
      movementPointsRemaining: current.movementPointsRemaining - 1,
    ));
    return MoveResult.portalTravel;
  }

  /// Retire l'événement consommé d'une case et le RE-DÉPOSE sur une autre
  /// case libre au hasard (retours playtest : la carte ne disparaît pas,
  /// elle change d'endroit — impossible de farmer une même case, et de
  /// nouvelles opportunités apparaissent au fil de l'exploration).
  void _clearTileEvent(Planet planet, Position target, TileEventKind kind) {
    final Tile tile = planet.tileAt(target.x, target.y);
    final Tile cleared = switch (kind) {
      TileEventKind.ally => tile.copyWith(clearAlly: true),
      TileEventKind.weapon => tile.copyWith(clearWeapon: true),
      TileEventKind.armor => tile.copyWith(clearArmor: true),
      TileEventKind.healSite => tile.copyWith(healSite: false),
      _ => tile,
    };

    // Case de repli : jouable, libre de tout contenu, hors départs, hors
    // cases occupées et hors case d'origine — de préférence non découverte.
    final Set<Position> occupied = state!.players
        .where((Player p) => p.planet == planet.type && !p.eliminated)
        .map((Player p) => p.position)
        .toSet();
    // Les positions des portails ne sont JAMAIS des candidates (retours
    // playtest : un soin redéposé sur la case du portail bloquait le
    // voyage).
    bool isPortalTile(Position p) =>
        state!.portals.any((Portal portal) => portal.position == p) ||
        (!PlanetConstants.startPlanets.contains(planet.type) &&
            p == PlanetConstants.secondaryPortalPosition);
    // Ni sur la case d'un BOSS actif (retours playtest 19/09 : un boss
    // partageait sa case avec un monstre), ni sur la PORTE de la cantina.
    final Set<Position> bossPositions = _bossPositions(state!, planet.type);
    final Position? cantinaDoor =
        (state!.cantina?.planet == planet.type) ? state!.cantina!.anchor : null;
    final Position? teleportDoor = (state!.teleport?.planet == planet.type)
        ? state!.teleport!.position
        : null;
    final Position? teleportDoor2 =
        (state!.teleport?.planet == planet.type && state!.teleport!.position2 != null)
            ? state!.teleport!.position2
            : null;
    final Position? patapuchePos = (state!.patapuche?.planet == planet.type)
        ? state!.patapuche!.position
        : null;
    // Un SOIN redéposé ne doit pas être voisin d'un autre soin (retours
    // playtest 20/09 : jamais deux soins sur des cases voisines).
    bool healSiteNearby(Position p) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final int nx = p.x + dx;
          final int ny = p.y + dy;
          if (nx < 0 || ny < 0 || nx >= planet.width || ny >= planet.height) {
            continue;
          }
          if (planet.tileAt(nx, ny).healSite) return true;
        }
      }
      return false;
    }

    final List<Tile> candidates = <Tile>[
      for (final Tile t in planet.tiles)
        if (t.walkable &&
            !(t.x == target.x && t.y == target.y) &&
            Position(t.x, t.y).chebyshevDistanceTo(target) >= 5 &&
            !t.visible &&
            !BoardConstants.startPositions.contains(Position(t.x, t.y)) &&
            !occupied.contains(Position(t.x, t.y)) &&
            !isPortalTile(Position(t.x, t.y)) &&
            !bossPositions.contains(Position(t.x, t.y)) &&
            Position(t.x, t.y) != cantinaDoor &&
            Position(t.x, t.y) != teleportDoor &&
            Position(t.x, t.y) != teleportDoor2 &&
            Position(t.x, t.y) != patapuchePos &&
            // Jamais de carte redéposée DANS la cantina (retours playtest
            // 19/09 : zone sans combat ni contenu).
            !t.cantina &&
            t.monster == null &&
            t.ally == null &&
            t.weapon == null &&
            t.armor == null &&
            !t.healSite &&
            !(kind == TileEventKind.healSite &&
                healSiteNearby(Position(t.x, t.y))))
          t,
    ];

    final List<Tile> tiles = List<Tile>.of(planet.tiles);
    tiles[target.y * planet.width + target.x] = cleared;

    if (candidates.isNotEmpty) {
      final List<Tile> hidden =
          candidates.where((Tile t) => !t.discovered).toList();
      final List<Tile> pool =
          hidden.isNotEmpty ? hidden : candidates;
      final Tile spot = pool[_diceRandom.nextInt(pool.length)];
      final Tile relocated = switch (kind) {
        TileEventKind.ally => spot.copyWith(ally: tile.ally),
        TileEventKind.weapon => spot.copyWith(weapon: tile.weapon),
        TileEventKind.armor => spot.copyWith(armor: tile.armor),
        TileEventKind.healSite => spot.copyWith(healSite: true),
        _ => spot,
      };
      tiles[spot.y * planet.width + spot.x] = relocated;
    }

    // FIX playtest : synchroniser currentPlanet ET la copie planets[type]
    // (l'ancien code ne mettait à jour que currentPlanet — au endTurn, la
    // planète restaurée depuis planets[type] faisait RÉAPPARAÎTRE la carte
    // consommée sur sa case d'origine).
    final Planet updated = planet.withTiles(tiles);
    state = state!.copyWith(
      currentPlanet: updated,
      planets: <PlanetType, Planet>{...state!.planets, planet.type: updated},
    );
  }

  /// Vrai lorsque le tour ne peut pas continuer normalement : des points de
  /// déplacement restent mais aucune case voisine n'est valide (joueur
  /// bloqué par des cases bloquées ou occupées). Permet de terminer le tour
  /// sans bloquer la partie.
  bool isMovementBlocked() {
    final GameState? current = state;
    if (current == null) return false;
    if (current.movementPointsRemaining <= 0) return false;
    return validMoveTargets().isEmpty;
  }

  /// Défausse l'allié à l'index [index] de l'équipe du joueur actif
  /// (CDC §12 : « possibilité de défausse »).
  void discardAlly(int index) {
    final GameState? current = state;
    if (current == null) return;
    final Player active = current.activePlayer;
    if (index < 0 || index >= active.allies.length) return;

    final List<Ally> allies = List<Ally>.of(active.allies)..removeAt(index);
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(allies: allies);
    state = current.copyWith(players: players);
  }

  // ---------------------------------------------------------------------------
  // Alliés, équipement et réserve (Sprint 4 — GDD §8, §9)
  // ---------------------------------------------------------------------------

  /// Rareté d'équipement autorisée pour un niveau joueur (GDD — Restrictions).
  static bool rarityAllowedForLevel(Rarity rarity, int level) {
    final int maxIndex =
        GameConstants.maxRarityLevelIndexPerLevel[(level - 1).clamp(0, 5)];
    return rarity.index <= maxIndex;
  }

  /// L'allié en attente peut-il être recruté (places d'équipe suffisantes) ?
  bool canRecruitPendingAlly() {
    final Ally? ally = pendingAllyOffer;
    if (ally == null || state == null) return false;
    return state!.activePlayer.canRecruit(ally.teamCost);
  }

  /// Malus de PV à l'enrôlement d'un allié de faction ennemie, selon la
  /// rareté (règle du game design — les nukers utilisent leurs valeurs
  /// Excel par porteur).
  static int enemyRecruitMalus(Ally ally, Faction playerFaction) {
    // Carte Spéciale (personnage) : -500 PV fixes (données Excel).
    if (ally.type == AllyType.special) {
      return GameConstants.specialEnemyDamage;
    }
    if (ally.type == AllyType.nuker) {
      final int? effect = ally.nukerOwnerEffect(playerFaction);
      return effect == null ? 0 : effect.abs();
    }
    return switch (ally.rarity) {
      Rarity.commun => 50,
      Rarity.rare => 100,
      Rarity.epique => 200,
      Rarity.legendaire => 300,
      Rarity.mythique => 400,
    };
  }

  /// Recrute l'allié proposé : +cost places d'équipe ; un healer soigne
  /// instantanément le joueur ; un allié de faction ENNEMIE inflige un
  /// malus de PV (nuker : valeur Excel du porteur, sinon selon rareté).
  /// La rareté doit être autorisée par le niveau et les doublons (hors
  /// escouades) sont interdits (retours playtest).
  void recruitPendingAlly() {
    final Ally? ally = pendingAllyOffer;
    final GameState? current = state;
    if (ally == null || current == null) return;
    final Player active = current.activePlayer;
    // Un allié de faction ENNEMIE n'est jamais recrutable (Sprint 4.2 bis) :
    // il a attaqué, la carte est consommée — pendingAllyOffer n'est rempli
    // que pour que le dialog puisse l'afficher.
    if (ally.faction != active.faction &&
        ally.faction != active.faction.alliedFaction) {
      return;
    }
    if (!active.canRecruit(ally.teamCost)) return;
    if (!rarityAllowedForLevel(ally.rarity, active.level)) return;
    if (ally.type != AllyType.escouade && active.hasAllyNamed(ally.name)) {
      return;
    }

    // Soin instantané du healer : plus d'application automatique au
    // recrutement (retours playtest) — c'est désormais une CHARGE que le
    // joueur active quand il veut depuis l'écran Équipe
    // (GameController.useHealerHeal).
    Player updated = active.copyWith(allies: <Ally>[...active.allies, ally]);
    if (ally.faction != active.faction &&
        ally.faction != active.faction.alliedFaction) {
      final int malus = GameConstants.scaleIncomingDamage(
        enemyRecruitMalus(ally, active.faction),
        level: active.level,
        maxHp: active.totalMaxHp,
      );
      final int hp = max(updated.hp - malus, 0);
      updated = updated.copyWith(hp: hp, eliminated: hp <= 0);
    }
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = updated;
    state = current.copyWith(players: players);
    pendingAllyOffer = null;
  }

  /// Refuse l'allié proposé (la rencontre est consommée).
  void declinePendingAlly() => pendingAllyOffer = null;

  /// Met l'allié proposé en réserve (retours playtest 10/09/2026 : utile
  /// quand la rareté dépasse le niveau ou que les PP manquent ; remplace
  /// l'éventuel allié déjà en réserve).
  void storePendingAlly() {
    final Ally? found = pendingAllyOffer;
    final GameState? current = state;
    if (found == null || current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(storedAlly: found);
    state = current.copyWith(players: players);
    pendingAllyOffer = null;
  }

  /// Transfère un allié de l'équipe vers la réserve. Si la réserve est
  /// occupée, ÉCHANGE les deux (retours playtest : l'allié stocké rejoint
  /// l'équipe — places vérifiées après la libération) ; échoue si les
  /// places ne suffisent pas.
  bool storeTeamAlly(int index) {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    if (index < 0 || index >= active.allies.length) return false;
    final Ally outgoing = active.allies[index];
    final Ally? reserved = active.storedAlly;
    if (reserved != null) {
      final int slotsAfter = active.usedTeamSlots - outgoing.teamCost;
      if (slotsAfter + reserved.teamCost > active.teamCapacity) {
        return false;
      }
    }
    final List<Ally> allies = List<Ally>.of(active.allies)..removeAt(index);
    if (reserved != null) allies.add(reserved);
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        active.copyWith(allies: allies, storedAlly: outgoing);
    state = current.copyWith(players: players);
    return true;
  }

  /// Recrute l'allié en réserve (rareté autorisée, places suffisantes,
  /// pas de doublon hors escouades). Le soin instantané des healers ne se
  /// déclenche qu'au recrutement initial — pas depuis la réserve (sinon
  /// boucle de soin infinie).
  bool recruitStoredAlly() {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    final Ally? ally = active.storedAlly;
    if (ally == null) return false;
    if (!rarityAllowedForLevel(ally.rarity, active.level)) return false;
    if (!active.canRecruit(ally.teamCost)) return false;
    // Doublon : comparer l'équipe seulement — l'allié vient DE la réserve
    // (sinon il se bloquerait lui-même).
    if (ally.type != AllyType.escouade &&
        active.allies.any((Ally a) => a.name == ally.name)) {
      return false;
    }
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      allies: <Ally>[...active.allies, ally],
      clearStoredAlly: true,
    );
    state = current.copyWith(players: players);
    return true;
  }

  /// Défausse l'allié en réserve.
  void discardStoredAlly() {
    final GameState? current = state;
    if (current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(clearStoredAlly: true);
    state = current.copyWith(players: players);
  }

  /// Refuse l'arme proposée : la carte est détruite (la case est déjà
  /// vidée — retours playtest 10/09/2026).
  void declinePendingWeapon() => pendingWeaponOffer = null;

  /// Refuse la tenue proposée : la carte est détruite.
  void declinePendingArmor() => pendingArmorOffer = null;

  /// Défausse l'arme en réserve.
  void discardStoredWeapon() {
    final GameState? current = state;
    if (current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = players[current.currentPlayerIndex]
        .copyWith(clearStoredWeapon: true);
    state = current.copyWith(players: players);
  }

  /// Défausse la tenue en réserve.
  void discardStoredArmor() {
    final GameState? current = state;
    if (current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(clearStoredArmor: true);
    state = current.copyWith(players: players);
  }

  /// Défausse l'arme équipée (le joueur repart sans arme).
  void discardEquippedWeapon() {
    final GameState? current = state;
    if (current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(clearWeapon: true);
    state = current.copyWith(players: players);
  }

  /// Défausse la tenue équipée.
  void discardEquippedArmor() {
    final GameState? current = state;
    if (current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(clearArmor: true);
    state = current.copyWith(players: players);
  }

  /// Équipe l'arme trouvée si la rareté est autorisée par le niveau.
  /// Cas « équipée + réserve occupées » (retours playtest) :
  ///  - [discardReplaced] vrai  → l'ancienne équipée est DÉFAUSSÉE et la
  ///    réserve est PRÉSERVÉE ;
  ///  - [discardReplaced] faux  → l'ancienne équipée part en réserve et
  ///    remplace l'éventuelle réserve (comportement historique).
  bool equipPendingWeapon({bool discardReplaced = false}) {
    final Weapon? found = pendingWeaponOffer;
    final GameState? current = state;
    if (found == null || current == null) return false;
    final Player active = current.activePlayer;
    if (!rarityAllowedForLevel(found.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      weapon: found,
      storedWeapon: discardReplaced
          ? active.storedWeapon
          : (active.weapon ?? active.storedWeapon),
    );
    state = current.copyWith(players: players);
    pendingWeaponOffer = null;
    return true;
  }

  /// Les PV suivent la tenue équipée (retours playtest 19/09) : équiper
  /// une armure augmente AUSSI les PV actuels du gain de maximum
  /// (200/200 + une tenue +100 → 300/300, et non 200/300). Le bonus ne
  /// descend jamais les PV (ranger/échanger vers une tenue plus faible).
  Player _withArmorHpGain(Player equipped, Armor? oldArmor) {
    final int delta =
        (equipped.armor?.hpBonus ?? 0) - (oldArmor?.hpBonus ?? 0);
    if (delta <= 0) return equipped;
    return equipped.copyWith(hp: min(equipped.hp + delta, equipped.totalMaxHp));
  }

  /// Équipe la tenue trouvée (même logique que l'arme).
  bool equipPendingArmor({bool discardReplaced = false}) {
    final Armor? found = pendingArmorOffer;
    final GameState? current = state;
    if (found == null || current == null) return false;
    final Player active = current.activePlayer;
    if (!rarityAllowedForLevel(found.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = _withArmorHpGain(
      active.copyWith(
        armor: found,
        storedArmor: discardReplaced
            ? active.storedArmor
            : (active.armor ?? active.storedArmor),
      ),
      active.armor,
    );
    state = current.copyWith(players: players);
    pendingArmorOffer = null;
    return true;
  }

  /// Met l'arme trouvée en réserve (remplace l'éventuelle réserve actuelle).
  void storePendingWeapon() {
    final Weapon? found = pendingWeaponOffer;
    final GameState? current = state;
    if (found == null || current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = players[current.currentPlayerIndex]
        .copyWith(storedWeapon: found, clearStoredWeapon: false);
    state = current.copyWith(players: players);
    pendingWeaponOffer = null;
  }

  /// Met la tenue trouvée en réserve (remplace l'éventuelle réserve actuelle).
  void storePendingArmor() {
    final Armor? found = pendingArmorOffer;
    final GameState? current = state;
    if (found == null || current == null) return;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = players[current.currentPlayerIndex]
        .copyWith(storedArmor: found);
    state = current.copyWith(players: players);
    pendingArmorOffer = null;
  }

  /// Échange l'arme en réserve avec l'arme équipée (restrictions de niveau
  /// vérifiées ; no-op sinon). Fix doublon playtest : si aucune arme n'est
  /// équipée, la réserve est VIDÉE (le piège `copyWith(null ?? ancien)`
  /// laissait l'arme à la fois équipée ET en réserve).
  bool equipStoredWeapon() {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    final Weapon? stored = active.storedWeapon;
    if (stored == null) return false;
    if (!rarityAllowedForLevel(stored.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      weapon: stored,
      storedWeapon: active.weapon,
      clearStoredWeapon: active.weapon == null,
    );
    state = current.copyWith(players: players);
    return true;
  }

  /// Échange la tenue en réserve avec la tenue équipée (même fix doublon).
  /// Les PV actuels suivent le gain de maximum (retours playtest 19/09).
  bool equipStoredArmor() {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    final Armor? stored = active.storedArmor;
    if (stored == null) return false;
    if (!rarityAllowedForLevel(stored.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = _withArmorHpGain(
      active.copyWith(
        armor: stored,
        storedArmor: active.armor,
        clearStoredArmor: active.armor == null,
      ),
      active.armor,
    );
    state = current.copyWith(players: players);
    return true;
  }

  /// Range l'arme équipée en réserve (retours playtest : réserve vide requis).
  bool storeEquippedWeapon() {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    if (active.weapon == null || active.storedWeapon != null) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      storedWeapon: active.weapon,
      clearWeapon: true,
    );
    state = current.copyWith(players: players);
    return true;
  }

  /// Range la tenue équipée en réserve.
  bool storeEquippedArmor() {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    if (active.armor == null || active.storedArmor != null) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      storedArmor: active.armor,
      clearArmor: true,
    );
    state = current.copyWith(players: players);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Fin de tour (CDC §2 : Fin du tour → Joueur suivant)
  // ---------------------------------------------------------------------------

  /// Termine le tour du joueur actif : sauvegarde automatique (GDD §15 —
  /// « sauvegardée automatiquement à chaque tour »), passage au joueur
  /// suivant, réinitialisation du dé, incrémentation du numéro de tour quand
  /// la main revient au premier joueur, révélation du rayon du nouveau
  /// joueur actif, puis déclenchement des événements de fin de tour.
  Future<void> endTurn() async {
    final GameState? current = state;
    if (current == null || current.status != GameStatus.inProgress) return;

    int nextIndex = current.currentPlayerIndex + 1;
    int turn = current.turn;
    if (nextIndex >= current.players.length) {
      nextIndex = 0;
      turn++;
    }
    // Les joueurs éliminés (Sprint 3) sont sautés dans la rotation.
    while (current.players[nextIndex].eliminated &&
        nextIndex != current.currentPlayerIndex) {
      nextIndex++;
      if (nextIndex >= current.players.length) {
        nextIndex = 0;
        turn++;
      }
    }

    GameState next = current.copyWith(
      currentPlayerIndex: nextIndex,
      turn: turn,
      movementPointsRemaining: 0,
      clearLastDiceRoll: true,
      currentPlanet: _mapService.revealFogAround(
          current.currentPlanet, current.players[nextIndex].position),
    );

    // Événements de fin de tour (Sprint 5) : révélation autour du nouveau
    // joueur actif sur SA planète, déplacement/réapparition des boss.
    final Player nextPlayer = next.players[nextIndex];
    final Planet nextPlanet =
        next.planets[nextPlayer.planet] ?? next.currentPlanet;
    final populate = _mapService.populateNewlyDiscoveredTiles(
      before: nextPlanet,
      after: _mapService.revealFogAround(
          nextPlanet, nextPlayer.position),
      phase: phaseOf(next),
      rng: _diceRandom,
      occupied: next.players
          .where((Player p) => p.planet == nextPlanet.type)
          .map((Player p) => p.position)
          .toSet(),
      existingPortals: next.portals,
      avoidPositions: <Position>{
        ..._bossPositions(next, nextPlanet.type),
        if (next.cantina?.planet == nextPlanet.type) next.cantina!.anchor,
        if (next.teleport?.planet == nextPlanet.type) ...<Position>[
          next.teleport!.position,
          if (next.teleport!.position2 != null)
            next.teleport!.position2!,
        ],
        if (next.patapuche?.planet == nextPlanet.type)
          next.patapuche!.position,
      },
      bossUnlocked: next.players
          .any((Player p) => !p.eliminated && p.level >= 5),
      doubleMonstersUnlocked: next.players
          .any((Player p) => !p.eliminated && p.level >= 4),
      allyBiasPlayer: nextPlayer,
    );
    final Map<PlanetType, Planet> planetsNext =
        <PlanetType, Planet>{...next.planets, nextPlanet.type: populate.planet};
    final movement = _mapService.moveBossesAtTurnEnd(
      bosses: next.bosses,
      planets: planetsNext,
      players: next.players,
      rng: _diceRandom,
    );
    next = next.copyWith(
      // La planète PEUPLÉE (populate.planet), pas l'objet nextPlanet capturé
      // avant le populate — sinon la révélation du nouveau joueur est perdue.
      currentPlanet: populate.planet,
      planetType: nextPlayer.planet,
      planets: movement.planets,
      portals: next.portals,
      bosses: movement.bosses,
    );

    // Garantie de découverte (retours playtest : les bords du plateau
    // pouvaient être déjà explorés avant le niveau 3 — plus AUCUN portail
    // ne pouvait apparaître). Dès la phase milieu (premier joueur N3), les
    // 4 portails sont posés EN UNE FOIS, où que ce soit sur la planète
    // principale (retours playtest : pas seulement les bords). Fix du
    // 19/09 : posés SANS révéler la case — invisibles sous le brouillard,
    // ils ne s'affichent qu'à l'approche d'un joueur.
    if (phaseOf(next) != GamePhase.debut) {
      next = _spawnGuaranteedPortals(next);
    }

    // L'état courant (rotation + populate de CE endTurn) devient la base
    // des spawns internes (boss, doubles monstres, Patapuche) — sinon
    // leurs propres affectations d'état seraient écrasées par la copie
    // obsolète `next` (fix 21/09 : les doubles/Patapuche n'apparaissaient
    // jamais via endTurn).
    state = next;
    _maybeSpawnBosses();
    _maybeSpawnDoubleMonsters();
    _maybeSpawnPatapuche();
    _movePatapuche();
    // Les spawns internes ont pu modifier l'état : on repart de l'état à
    // jour pour les conditions de victoire et la sauvegarde.
    next = state ?? next;
    next = _checkVictoryConditions(next);
    next = next.copyWith(savedAt: DateTime.now());
    state = next;
    await _saveService.save(next);
  }

  // ---------------------------------------------------------------------------
  // XP, montée de niveau et résolution des combats (GDD §7, §11, §13)
  // ---------------------------------------------------------------------------

  /// Applique un gain d'XP à [player] : paliers du GDD §7
  /// (200/400/700/1000/3000), cap niveau 6. À chaque niveau gagné :
  /// ATK = table et PV actuels remis au nouveau maximum (décision du
  /// 07/09/2026).
  Player applyXpGain(Player player, int xpGain) {
    final int total = player.xp + xpGain;
    int newLevel = player.level;
    while (newLevel < GameConstants.maxPlayerLevel &&
        total >= GameConstants.xpRequiredPerLevel[newLevel]) {
      newLevel++;
    }
    if (newLevel == player.level) {
      return player.copyWith(xp: total);
    }
    log('⬆ ${player.name} atteint le niveau $newLevel !');
    return player.copyWith(
      xp: total,
      level: newLevel,
      attack: GameConstants.attackForLevel(newLevel),
      hp: GameConstants.hpForLevel(newLevel),
      maxHp: GameConstants.hpForLevel(newLevel),
    );
  }

  /// Résout la victoire sur un monstre (GDD §11) : +XP au joueur actif
  /// (montée de niveau éventuelle), puis dégâts subis
  /// (= ATK du monstre × attaques, calculés par le CombatController).
  /// Renvoie les PV restants et l'éventuelle élimination du joueur.
  MonsterVictoryOutcome applyMonsterVictory({
    required Position tile,
    required int xp,
    required int playerHp,
  }) {
    final GameState current = state!;
    Player updated = current.activePlayer.copyWith(hp: playerHp);

    // 1) XP / montée de niveau (le soin au nouveau max peut compenser).
    //    Soutien « bonusXp20 » : +20 XP après chaque combat (playtest).
    final int monsterBonusXp =
        updated.hasXpBonusSupport ? GameConstants.supportBonusXp : 0;
    updated = applyXpGain(updated, xp + monsterBonusXp);

    // 2) Les healers de l'équipe soignent après le combat (cumulables,
    //    plafonnés au max PV — tanks inclus).
    if (!updated.eliminated) {
      final int heal = updated.healerAfterCombatHeal;
      if (heal > 0) {
        updated =
            updated.copyWith(hp: min(updated.hp + heal, updated.totalMaxHp));
      }
    }

    // 4) La (les) carte(s) du monstre sont retirées de la case (GDD §11) —
    // un double monstre vaincu retire ses DEUX cartes (retours playtest
    // 20/09).
    final Tile tileUpdated = current.currentPlanet
        .tileAt(tile.x, tile.y)
        .copyWith(clearMonster: true, clearMonster2: true);
    final List<Tile> tiles = List<Tile>.of(current.currentPlanet.tiles);
    tiles[tile.y * current.currentPlanet.width + tile.x] = tileUpdated;

    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = updated;

    final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
      ...current.planets,
      current.planetType: current.currentPlanet.withTiles(tiles),
    };
    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: planets,
      currentPlanet: planets[current.planetType],
    ));
    // Après l'affectation : le spawn repart du nouvel état (une victoire
    // peut faire passer le joueur N5) et n'est pas écrasé.
    _maybeSpawnBosses();
    _maybeSpawnDoubleMonsters();
    _maybeSpawnPatapuche();
    return MonsterVictoryOutcome(
        playerHp: updated.hp,
        playerEliminated: updated.eliminated,
        xpGained: xp + monsterBonusXp);
  }

  /// Défaite contre un monstre : le joueur actif est éliminé (0 PV) et le
  /// monstre reste sur sa case. La partie se termine si nécessaire.
  void applyPlayerDefeat() {
    final GameState current = state!;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(hp: 0, eliminated: true);
    log('💀 ${players[current.currentPlayerIndex].name} a été éliminé…');
    state = _applySurvivorCheck(current.copyWith(players: players));
  }

  /// Applique les PV restants du joueur après une fuite en plein combat.
  void applyPlayerCombatHp(int hp) {
    final GameState current = state!;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] =
        players[current.currentPlayerIndex].copyWith(hp: hp);
    state = _applySurvivorCheck(current.copyWith(players: players));
  }

  /// Fin de partie provisoire (écran complet au Sprint 5) : dernier
  /// survivant (chacun pour soi) ou équipe adverse entièrement éliminée.
  GameState _applySurvivorCheck(GameState s) {
    if (s.status != GameStatus.inProgress) return s;
    if (s.mode == GameMode.chacunPourSoi) {
      final int alive = s.players.where((Player p) => !p.eliminated).length;
      if (alive <= 1 && s.players.length > 1) {
        return s.copyWith(status: GameStatus.finished);
      }
      return s;
    }
    // Big Four : victoire d'équipe par objectifs — union des boss de
    // l'équipe, HORS boss des factions des membres (chaque équipe
    // représente une faction : son boss ne compte pas).
    if (s.mode == GameMode.bigFour) {
      for (final TeamSide side in TeamSide.values) {
        final List<Player> members = s.players
            .where((Player p) => p.team == side && !p.eliminated)
            .toList();
        if (members.isEmpty) continue;
        final Set<Faction> teamFactions = <Faction>{
          for (final Player p in members) p.faction,
        };
        final Set<BossType> adverseBosses = <BossType>{
          for (final Player p in members)
            for (final BossType boss in p.defeatedBosses)
              if (!teamFactions
                  .contains(PlanetConstants.bossFactionByType[boss]))
                boss,
        };
        if (adverseBosses.length >= GameConstants.bossesToWin) {
          return s.copyWith(status: GameStatus.finished);
        }
      }
    }

    // Modes à équipes (Équipes, Big Four) : la partie se termine quand une
    // SEULE équipe a encore des joueurs vivants (générique à N équipes).
    final Set<TeamSide> allTeams = <TeamSide>{
      for (final Player p in s.players)
        if (p.team != null) p.team!,
    };
    final Set<TeamSide> aliveTeams = <TeamSide>{
      for (final Player p in s.players)
        if (!p.eliminated && p.team != null) p.team!,
    };
    if (allTeams.isNotEmpty && aliveTeams.length <= 1) {
      return s.copyWith(status: GameStatus.finished);
    }
    return s;
  }

  /// Résout un échange entre joueurs (GDD §13) : PV restants du défenseur,
  /// élimination éventuelle, XP de chasseur (+500) pour l'attaquant.
  /// Retours playtest : l'attaquant peut perdre des PV et être éliminé par
  /// la RIPOSTE du défenseur (sans critique), auquel cas le défenseur
  /// touche les +500 XP.
  void applyPlayerCombatResult({
    required int defenderIndex,
    required int defenderHp,
    required bool defenderEliminated,
    required int attackerXp,
    int attackerHp = -1,
    bool attackerEliminated = false,
    int defenderXp = 0,
  }) {
    final GameState current = state!;
    final List<Player> players = List<Player>.of(current.players);
    players[defenderIndex] = players[defenderIndex].copyWith(
      hp: defenderHp,
      eliminated: defenderEliminated,
    );
    if (defenderEliminated) {
      log('💀 ${players[defenderIndex].name} a été éliminé en duel par '
          '${players[current.currentPlayerIndex].name} !');
    }
    if (attackerEliminated) {
      log('💀 ${players[current.currentPlayerIndex].name} a été éliminé par '
          'la riposte de ${players[defenderIndex].name} !');
    }
    if (defenderXp > 0) {
      players[defenderIndex] =
          applyXpGain(players[defenderIndex], defenderXp);
    }
    if (attackerHp >= 0) {
      players[current.currentPlayerIndex] =
          players[current.currentPlayerIndex].copyWith(
        hp: attackerHp,
        eliminated: attackerEliminated,
      );
    }
    if (attackerXp > 0) {
      players[current.currentPlayerIndex] =
          applyXpGain(players[current.currentPlayerIndex], attackerXp);
    }
    state = _applySurvivorCheck(current.copyWith(players: players));
    // Après l'affectation : le spawn repart du nouvel état (un joueur peut
    // passer N5 grâce à l'XP de chasseur) et n'est pas écrasé.
    _maybeSpawnBosses();
    _maybeSpawnDoubleMonsters();
    _maybeSpawnPatapuche();
  }

  // ---------------------------------------------------------------------------
  // Soutiens à usage unique (retours playtest 10/09/2026)
  // ---------------------------------------------------------------------------

  /// Consomme la carte soutien « empêche la mort » de l'équipe du joueur
  /// [playerIndex] (survit à 1 PV — l'appelant applique les PV). Renvoie
  /// false si le joueur n'en possède pas.
  bool consumePreventDeath(int playerIndex) {
    final GameState? current = state;
    if (current == null) return false;
    final Player p = current.players[playerIndex];
    final int index = p.allies.indexWhere((Ally ally) =>
        ally.type == AllyType.soutien && ally.ability == 'preventDeath');
    if (index < 0) return false;
    final List<Ally> allies = List<Ally>.of(p.allies)..removeAt(index);
    final List<Player> players = List<Player>.of(current.players);
    players[playerIndex] = p.copyWith(allies: allies);
    state = current.copyWith(players: players);
    return true;
  }

  /// Active la charge de soin immédiat d'un healer de l'équipe
  /// (retours playtest : le joueur soigne QUAND IL VEUT depuis l'écran
  /// Équipe). La charge est consommée après usage. Renvoie false si
  /// l'allié n'a pas de charge, si le joueur est full PV ou si l'index
  /// est invalide.
  bool useHealerHeal(int allyIndex) {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    if (allyIndex < 0 || allyIndex >= active.allies.length) return false;
    final Ally healer = active.allies[allyIndex];
    final int? amount = healer.healInstant;
    if (amount == null || amount <= 0) return false;
    if (active.hp >= active.totalMaxHp) return false;

    final int healed = min(amount, active.totalMaxHp - active.hp);
    final List<Ally> allies = List<Ally>.of(active.allies);
    allies[allyIndex] = healer.copyWith(clearHealInstant: true);
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      hp: active.hp + healed,
      allies: allies,
    );
    state = current.copyWith(players: players);
    log('💚 ${active.name} est soigné de $healed PV par ${healer.name}.');
    return true;
  }

  /// Consomme la carte soutien « attaque ×dé » du joueur actif (usage
  /// unique).
  void consumeAttackTimesDice() {
    final GameState? current = state;
    if (current == null) return;
    final Player active = current.activePlayer;
    final int index = active.allies.indexWhere((Ally ally) =>
        ally.type == AllyType.soutien && ally.ability == 'attackTimesDice');
    if (index < 0) return;
    final List<Ally> allies = List<Ally>.of(active.allies)..removeAt(index);
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(allies: allies);
    state = current.copyWith(players: players);
  }

  // ---------------------------------------------------------------------------
  // Boss — apparition au niveau 5 (Sprint 5)
  // ---------------------------------------------------------------------------

  /// Pose TOUS les portails manquants sur la planète PRINCIPALE (retours
  /// playtest : dès qu'un joueur atteint le N3, les 4 existent — plus aucun
  /// risque de partie sans voyages possibles). Chacun vers une planète
  /// secondaire encore libre, au hasard, n'importe où sur des cases libres
  /// (pas seulement les bords), espacés d'au moins 4.
  ///
  /// Fix playtest 19/09 : la pose ne révèle PLUS la case — le portail reste
  /// sous le brouillard de guerre et ne s'affiche sur le plateau que
  /// lorsqu'un joueur s'en approche (case dans la zone visible), comme
  /// n'importe quel autre élément.
  GameState _spawnGuaranteedPortals(GameState next) {
    // La planète principale = l'unique planète de départ dans la map.
    PlanetType? mainType;
    for (final PlanetType type in next.planets.keys) {
      if (PlanetConstants.startPlanets.contains(type)) {
        mainType = type;
        break;
      }
    }
    if (mainType == null) return next;
    final Planet mainPlanet = next.planets[mainType]!;
    // Cases occupées SUR CETTE PLANÈTE (comparaison planète + position —
    // un pion sur une autre planète ne bloque pas une case de même
    // coordonnées, fix 19/09).
    final Set<Position> occupied = next.players
        .where((Player p) => p.planet == mainType && !p.eliminated)
        .map((Player p) => p.position)
        .toSet();

    while (next.portals.length < PlanetConstants.secondaryPlanets.length) {
      final Position? spot = _mapService.findGuaranteedPortalSpot(
        planet: mainPlanet,
        portals: next.portals,
        occupied: occupied,
        rng: _diceRandom,
        // Jamais de portail SUR la porte de la cantina ou de téléport.
        cantinaDoor:
            next.cantina?.planet == mainType ? next.cantina!.anchor : null,
        teleportDoor: next.teleport?.planet == mainType
            ? next.teleport!.position
            : null,
        patapuchePosition: next.patapuche?.planet == mainType
            ? next.patapuche!.position
            : null,
      );
      if (spot == null) break;

      final List<PlanetType> free = PlanetConstants.secondaryPlanets
          .where((PlanetType type) =>
              !next.portals.any((Portal p) => p.destination == type))
          .toList();
      if (free.isEmpty) break;
      final PlanetType destination = free[_diceRandom.nextInt(free.length)];

      // discovered = vrai : le portail existe et est fonctionnel (le voyage
      // se déclenche dès qu'on marche dessus), mais la case reste masquée —
      // l'affichage suit la case (filtre tile.visible du plateau).
      next = next.copyWith(portals: <Portal>[
        ...next.portals,
        Portal(destination: destination, position: spot, discovered: true),
      ]);
      if (!next.planets.containsKey(destination)) {
        next = next.copyWith(planets: <PlanetType, Planet>{
          ...next.planets,
          destination: _mapService.generateSecondaryPlanet(destination,
              seed: next.seed + destination.index * 977),
        });
      }
      log('🌌 Un portail vers '
          '${PlanetConstants.displayNames[destination] ?? destination.name} '
          'est apparu quelque part sur la planète…');
    }
    return next;
  }

  /// Fait apparaître le boss de chaque planète secondaire générée dès qu'un
  /// joueur actif atteint le niveau 5 (une seule fois par planète). Position
  /// : la case jouable la plus éloignée du portail central, de préférence non
  /// découverte.
  /// PREMIER joueur niveau 4 (retours playtest 20/09) : annonce et ajout
  /// de ~20 % de cases « doubles monstres » EN PLUS sur chaque planète
  /// générée (le plateau était déjà exploré en grande partie au N4 — les
  /// nouvelles découvertes seules n'auraient presque jamais montré de
  /// doubles). Une seule fois par partie.
  void _maybeSpawnDoubleMonsters() {
    final GameState? s = state;
    if (s == null || s.status != GameStatus.inProgress) return;
    if (!s.players.any((Player p) => !p.eliminated && p.level >= 4)) return;
    // Déclencheur PERSISTANT (dans la sauvegarde) : un rechargement de
    // page ne perd plus l'effet (fix 21/09 — « toujours pas de doubles »).
    if (s.doubleMonstersUnlocked) return;
    doubleMonstersPending = true;
    log('👥 Des doubles monstres apparaissent !');

    final Map<PlanetType, Planet> planets = Map<PlanetType, Planet>.of(s.planets);
    for (final PlanetType type in planets.keys.toList()) {
      final Planet planet = planets[type]!;
      final Set<Position> occupied = <Position>{
        for (final Player p in s.players)
          if (p.planet == type && !p.eliminated) p.position,
      };
      final int existing =
          planet.tiles.where((Tile t) => t.monster != null).length;
      final int target = (existing * 0.2).round();
      if (target <= 0) continue;

      // Cases candidates : jouables, sans contenu, hors départs, hors
      // joueurs, hors portails, hors porte/cantine.
      final List<Position> discovered = <Position>[];
      final List<Position> hidden = <Position>[];
      for (final Tile t in planet.tiles) {
        final Position p = Position(t.x, t.y);
        if (t.walkable &&
            t.monster == null &&
            t.monster2 == null &&
            t.ally == null &&
            t.weapon == null &&
            t.armor == null &&
            !t.healSite &&
            !t.cantina &&
            !BoardConstants.startPositions.contains(p) &&
            !occupied.contains(p) &&
            !s.portals.any((Portal portal) => portal.position == p) &&
            !(s.cantina?.planet == type && s.cantina!.anchor == p) &&
            !(s.teleport != null &&
                s.teleport!.planet == type &&
                (s.teleport!.position == p ||
                    s.teleport!.position2 == p))) {
          // Cases DÉCOUVERTES d'abord : les doubles apparaissent sous les
          // yeux du joueur (sinon invisibles dans la zone inexplorée).
          (t.discovered ? discovered : hidden).add(p);
        }
      }
      discovered.shuffle(_diceRandom);
      hidden.shuffle(_diceRandom);
      final List<Position> candidates = <Position>[...discovered, ...hidden];

      final List<Tile> tiles = List<Tile>.of(planet.tiles);
      int placed = 0;
      for (final Position position in candidates) {
        if (placed >= target) break;
        final int index = position.y * planet.width + position.x;
        tiles[index] = tiles[index].copyWith(
          monster: MonsterConstants.randomLowMonster(_diceRandom),
          monster2: MonsterConstants.randomLowMonster(_diceRandom),
        );
        placed++;
      }
      if (placed > 0) {
        planets[type] = planet.withTiles(tiles);
        log('👥 $placed doubles monstres surgissent sur '
            '${PlanetConstants.displayNames[type] ?? type.name} !');
      }
    }
    // FIX : synchroniser currentPlanet avec la planète modifiée (même
    // mécanique que le fix « toujours la même carte » du 19/09).
    state = s.copyWith(
      planets: planets,
      currentPlanet: planets[s.planetType] ?? s.currentPlanet,
      doubleMonstersUnlocked: true,
    );
  }

  /// PREMIER joueur niveau 2 (retours playtest 20/09) : PATAPUCHE
  /// apparaît sur la planète principale (case libre au hasard, hors
  /// départs/contenus/portes) + annonce au plateau.
  void _maybeSpawnPatapuche() {
    final GameState? s = state;
    if (s == null || s.status != GameStatus.inProgress) return;
    if (s.patapuche != null) return;
    if (!s.players.any((Player p) => !p.eliminated && p.level >= 2)) return;
    final PlanetType mainType = s.planets.keys
        .firstWhere((PlanetType t) => PlanetConstants.startPlanets.contains(t),
            orElse: () => s.planetType);
    final Position? anchor = _mapService.patapucheAnchorFor(s.seed);
    if (anchor == null) return;
    state = s.copyWith(
      patapuche: Patapuche(planet: mainType, position: anchor),
    );
    patapuchePending = true;
    log('🐾 Patapuche apparaît sur la planète !');
  }

  /// Déplacement de Patapuche à CHAQUE fin de tour : une case au hasard
  /// (jouable, sans joueur/monstre/contenu). Bloqué par des monstres ou
  /// du contenu ? Il SAUTE par-dessus : la case valide libre la plus
  /// proche (anneaux 2, 3, 4…). Ne se déplace que sur la planète
  /// principale.
  void _movePatapuche() {
    final GameState? s = state;
    final Patapuche? patapuche = s?.patapuche;
    if (s == null ||
        patapuche == null ||
        s.status != GameStatus.inProgress ||
        s.planets[patapuche.planet] == null) {
      return;
    }
    final Planet? mainPlanetOrNull = s.planets[patapuche.planet];
    if (mainPlanetOrNull == null) return;
    final Planet planet = mainPlanetOrNull;
    final Set<Position> occupied = <Position>{
      for (final Player p in s.players)
        if (!p.eliminated && p.planet == patapuche.planet) p.position,
    };

    bool tileValide(Position p) {
      if (!planet.isWalkableAt(p.x, p.y)) return false;
      if (occupied.contains(p)) return false;
      final Tile tile = planet.tileAt(p.x, p.y);
      // Aucun monstre, aucun contenu (allié/objet/soin), hors cantina.
      if (tile.monster != null ||
          tile.ally != null ||
          tile.weapon != null ||
          tile.armor != null ||
          tile.healSite ||
          tile.cantina) {
        return false;
      }
      return true;
    }

    // Anneaux de Chebyshev 1, 2, 3, 4 : la case valide LA PLUS PROCHE
    // (saut par-dessus les monstres/contenus si bloqué — jamais coincé).
    for (int ring = 1; ring <= 4; ring++) {
      final List<Position> valides = <Position>[];
      for (int dy = -ring; dy <= ring; dy++) {
        for (int dx = -ring; dx <= ring; dx++) {
          if (dx.abs() != ring && dy.abs() != ring) continue;
          final int nx = patapuche.position.x + dx;
          final int ny = patapuche.position.y + dy;
          final Tile? tile = planet.tileAtOrNull(nx, ny);
          if (tile == null || !tile.walkable) continue;
          final Position p = Position(nx, ny);
          if (tileValide(p)) valides.add(p);
        }
      }
      if (valides.isNotEmpty) {
        final Position destination =
            valides[_diceRandom.nextInt(valides.length)];
        state = s.copyWith(patapuche: patapuche.copyWith(position: destination));
        return;
      }
    }
    // Aucune case valide dans les 4 anneaux : Patapuche reste sur place
    // (cas extrême — planète saturée de monstres).
  }

  void _maybeSpawnBosses() {
    final GameState? s = state;
    if (s == null || s.status != GameStatus.inProgress) return;
    if (!s.players.any((Player p) => !p.eliminated && p.level >= 5)) return;
    if (s.bosses.length >= PlanetConstants.secondaryPlanets.length) return;

    final List<Boss> result = List<Boss>.of(s.bosses);
    for (final PlanetType type in PlanetConstants.secondaryPlanets) {
      if (result.any((Boss b) => b.planet == type)) continue;
      final Planet? planet = s.planets[type];
      if (planet == null) continue;
      result.add(_createBossFor(planet, type));
      bossAwakeningPlanets.add(type);
    }
    if (result.length != s.bosses.length) {
      state = s.copyWith(bosses: result);
    }
  }

  /// Positions des boss ACTIFS (non fugqués, non morts) sur une planète :
  /// aucune case de contenu ne doit être posée dessus (retours playtest
  /// 19/09 — un boss partageait sa case avec un monstre).
  Set<Position> _bossPositions(GameState state, PlanetType planet) {
    final int aliveCount =
        state.players.where((Player p) => !p.eliminated).length;
    return <Position>{
      for (final Boss boss in state.bosses)
        if (boss.planet == planet &&
            !boss.isGone &&
            !boss.isDefinitivelyDead(aliveCount))
          boss.position,
    };
  }

  Boss _createBossFor(Planet planet, PlanetType type) {
    const Position center = PlanetConstants.secondaryPortalPosition;
    final Set<Position> occupied = <Position>{
      for (final Player p in state!.players)
        if (p.planet == type && !p.eliminated) p.position,
      center,
    };

    // Zones libres, de préférence non découvertes, les plus éloignées du
    // portail central.
    Position? bestHidden;
    int bestHiddenDist = -1;
    Position? bestAny;
    int bestAnyDist = -1;
    for (final Tile tile in planet.tiles) {
      if (!tile.walkable) continue;
      final Position position = Position(tile.x, tile.y);
      if (occupied.contains(position)) continue;
      // Jamais sur une case à contenu (retours playtest 19/09 : un boss
      // est apparu sur la même case qu'un monstre).
      if (MapService.tileHasEvent(planet, position)) continue;
      final int distance = position.chebyshevDistanceTo(center);
      if (!tile.discovered && distance > bestHiddenDist) {
        bestHiddenDist = distance;
        bestHidden = position;
      }
      if (distance > bestAnyDist) {
        bestAnyDist = distance;
        bestAny = position;
      }
    }
    final BossType bossType = PlanetConstants.bossBySecondaryPlanet[type]!;
    return Boss(
      name: bossType.displayName,
      type: bossType,
      planet: type,
      hp: GameConstants.bossHp,
      attackMin: GameConstants.bossAttackMin,
      attackMax: GameConstants.bossAttackMax,
      position: bestHidden ?? bestAny ?? center,
    );
  }

  /// Résout la victoire sur un boss (GDD §12) : XP selon le rang du
  /// vainqueur (400/300/200/100), la carte est marquée vaincue ; si tous
  /// les joueurs actifs l'ont vaincue → mort définitive, sinon le boss
  /// fuit (il réapparaîtra en zone non visible — Sprint 5).
  MonsterVictoryOutcome applyBossVictory({
    required BossType type,
    required int playerHp,
  }) {
    final GameState current = state!;
    Player updated = current.activePlayer.copyWith(hp: playerHp);

    final Boss target =
        current.bosses.firstWhere((Boss b) => b.type == type);
    final int rank = target.defeatedByPlayerIds.length;
    final int xp = rank < GameConstants.bossXpRewards.length
        ? GameConstants.bossXpRewards[rank]
        : GameConstants.bossXpRewardSubsequent;
    final int bossBonusXp =
        updated.hasXpBonusSupport ? GameConstants.supportBonusXp : 0;
    updated = applyXpGain(updated, xp + bossBonusXp);
    updated = updated.copyWith(
        defeatedBosses: <BossType>[...updated.defeatedBosses, type]);
    // Retours playtest : chaque boss vaincu soigne +500 PV et augmente la
    // capacité d'équipe de +2 places pour le vainqueur.
    final int healed = min(GameConstants.bossVictoryHeal,
        updated.totalMaxHp - updated.hp);
    if (healed > 0) {
      updated = updated.copyWith(hp: updated.hp + healed);
    }
    updated = updated.copyWith(
        teamCapacityBonusDelta: GameConstants.bossTeamCapacityBonus);
    log('🏆 ${updated.name} a vaincu ${type.displayName} '
        '(+${xp + bossBonusXp} XP'
        '${healed > 0 ? ', +$healed PV' : ''}, +2 places d’équipe) !');

    final int aliveCount =
        current.players.where((Player p) => !p.eliminated).length;
    final List<String> defeated =
        <String>[...target.defeatedByPlayerIds, updated.id];
    final bool definitivelyDead = defeated.length >= aliveCount;
    final List<Boss> bosses = current.bosses.map((Boss b) {
      if (b.type != type) return b;
      return b.copyWith(
        defeatedByPlayerIds: defeated,
        // Victoire sans mort définitive : le boss prend la fuite.
        isGone: !definitivelyDead,
        // Il réapparaîtra À PLEINE VIE (retours playtest 20/09) : les dégâts
        // ne persistent que pour les fuites en cours de combat.
        hp: GameConstants.bossHp,
      );
    }).toList();

    final List<Player> updatedPlayers = List<Player>.of(current.players);
    updatedPlayers[current.currentPlayerIndex] = updated;
    state = _checkVictoryConditions(_applySurvivorCheck(current.copyWith(
      players: updatedPlayers,
      bosses: bosses,
    )));
    return MonsterVictoryOutcome(
      playerHp: updated.hp,
      playerEliminated: updated.eliminated,
      xpGained: xp + bossBonusXp,
    );
  }

  /// Persiste les PV restants d'un boss après la FUITE du joueur (retours
  /// playtest 20/09 : un boss blessé garde ses dégâts — le prochain
  /// combat contre LUI repart de ces PV ; il ne récupère ses 10000 PV
  /// qu'une fois vaincu, à sa réapparition — voir applyBossVictory).
  void applyBossDamage({required BossType type, required int remainingHp}) {
    final GameState? current = state;
    if (current == null || remainingHp <= 0) return;
    final List<Boss> bosses = List<Boss>.of(current.bosses);
    final int index =
        bosses.indexWhere((Boss b) => b.type == type && !b.isGone);
    if (index < 0) return;
    bosses[index] = bosses[index].copyWith(hp: remainingHp);
    state = current.copyWith(bosses: bosses);
  }

  // ---------------------------------------------------------------------------
  // Chrono (CDC §10 : Temps de jeu mm:ss)
  // ---------------------------------------------------------------------------

  /// Tick d'une seconde appelé par le chronomètre de l'écran plateau.
  /// (Le temps de jeu est persisté à chaque sauvegarde de fin de tour.)
  void tickGameTime() {
    final GameState? current = state;
    if (current == null || current.status != GameStatus.inProgress) return;
    state = current.copyWith(gameTimeSeconds: current.gameTimeSeconds + 1);
  }

  // ---------------------------------------------------------------------------
  // Conditions de victoire (GDD §16, CDC §17) — Sprint 5
  // ---------------------------------------------------------------------------

  /// Vérifie les conditions de victoire :
  ///  - chacun pour soi : dernier survivant, ou 3 boss différents vaincus ;
  ///  - équipes : équipe adverse éliminée, ou 3 boss différents vaincus par
  ///    l'équipe.
  /// Conditions de victoire (GDD §16, CDC §17, décision du 08/09/2026) :
  ///  - chacun pour soi : dernier survivant, ou les 3 boss des factions
  ///    ADVERSES à sa faction vaincus (son propre boss ne compte pas) ;
  ///  - équipes : équipe adverse éliminée, ou l'union des boss vaincus par
  ///    l'équipe couvre 3 boss différents.
  GameState _checkVictoryConditions(GameState state) {
    if (state.status != GameStatus.inProgress) return state;

    // Chacun pour soi : 3 boss de factions adverses vaincus.
    for (final Player player
        in state.players.where((Player p) => !p.eliminated)) {
      final int adverseCount = player.defeatedBosses
          .where((BossType boss) =>
              PlanetConstants.bossFactionByType[boss] != player.faction)
          .toSet()
          .length;
      if (adverseCount >= GameConstants.bossesToWin) {
        return state.copyWith(status: GameStatus.finished);
      }
    }

    // Équipes : l'union des boss vaincus par les membres couvre 3 boss
    // différents.
    if (state.mode == GameMode.equipes) {
      for (final TeamSide side in TeamSide.values) {
        final Set<BossType> defeated = <BossType>{};
        for (final Player player
            in state.players.where((Player p) => p.team == side)) {
          defeated.addAll(player.defeatedBosses);
        }
        if (defeated.length >= GameConstants.bossesToWin) {
          return state.copyWith(status: GameStatus.finished);
        }
      }
    }
    return state;
  }
}
