import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/board_constants.dart';
import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/armor.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/portal.dart' show Portal;
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/models/weapon.dart';
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';

/// UNICITÉ DES CARTES (retours playtest 11/10) : une carte possédée par
/// un joueur (allié, arme, tenue) ne sort plus sur le plateau ; les
/// escouades restent tirables jusqu'à 10 exemplaires au total ; les
/// cartes d'un joueur éliminé sont remises en jeu.

class _FakeSaveService extends SaveService {
  @override
  Future<bool> hasSave() async => false;

  @override
  Future<void> save(GameState state) async {}

  @override
  Future<GameState?> load() async => null;

  @override
  Future<void> deleteSave() async {}
}

ProviderContainer _container(int combatSeed) => ProviderContainer(
      overrides: <Override>[
        saveServiceProvider.overrideWithValue(_FakeSaveService()),
        combatServiceProvider
            .overrideWithValue(CombatService(random: Random(combatSeed))),
      ],
    );

final MapService mapService = MapService();

/// Peuple un plateau ENTIÈREMENT révélé (populate direct, graines
/// différentes) et renvoie les noms tirés.
Set<String> _drawnNames({
  required Set<String> taken,
  required String? Function(Tile) pick,
  Faction playerFaction = Faction.rebel,
  int playerLevel = 6,
  int seeds = 20,
}) {
  final Set<String> drawn = <String>{};
  for (int seed = 1; seed <= seeds; seed++) {
    final Planet planet =
        mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final Player player = Player(
      id: 'p1',
      name: 'Testeur',
      faction: playerFaction,
      position: const Position(0, 0),
      planet: PlanetType.hoth,
      level: playerLevel,
      xp: 0,
      attack: 125,
      hp: 2000,
      maxHp: 2000,
    );
    final Planet revealed = mapService.revealFogAround(
      planet,
      const Position(10, 10),
      radius: 30,
    );
    final populate = mapService.populateNewlyDiscoveredTiles(
      before: planet,
      after: revealed,
      phase: GamePhase.fin,
      rng: Random(seed),
      occupied: const <Position>{},
      existingPortals: const [],
      bossUnlocked: false,
      allyBiasPlayer: player,
      takenCardNames: taken,
    );
    for (final Tile t in populate.planet.tiles) {
      final String? name = pick(t);
      if (name != null) drawn.add(name);
    }
  }
  return drawn;
}

/// Vraie partie + marche aléatoire (sans combat ni voyage) de [steps]
/// déplacements, en refusant les cartes rencontrées. Renvoie la planète
/// finale (Hothe) pour scan. [seedWeapons] : armes posées d'office sur
/// des cases libres au départ (pour compter les exemplaires en existence).
Future<Planet> _walkAndScan({
  required List<Player> players,
  int steps = 14,
  List<Weapon> seedWeapons = const <Weapon>[],
}) async {
  final ProviderContainer container = _container(7);
  addTearDown(container.dispose);
  final GameController controller =
      container.read(gameControllerProvider.notifier);
  GameState created = await controller.createNewGame(NewGameConfig(
    mode: GameMode.chacunPourSoi,
    playerCount: players.length,
    teamSize: 0,
    planetType: PlanetType.hoth,
    characters: <CharacterDefinition>[
      for (int i = 0; i < players.length; i++)
        CharacterConstants.characters[i],
    ],
  ));
  // Remplace les joueurs par la configuration du test (mêmes positions)
  // et vide le plateau du populate initial (lui-même effectué SANS les
  // possessions injectées — sinon des cartes tirées avant l'injection
  // pollueraient le scan).
  final List<Player> placed = <Player>[
    for (int i = 0; i < created.players.length; i++)
      players[i].copyWith(position: created.players[i].position),
  ];
  Planet cleaned = created.currentPlanet.withTiles(<Tile>[
    for (final Tile t in created.currentPlanet.tiles)
      t.copyWith(
        clearAlly: true,
        clearWeapon: true,
        clearArmor: true,
        healSite: false,
      ),
  ]);
  // Armes à SEMER : posées sur les premières cases libres hors départs.
  if (seedWeapons.isNotEmpty) {
    final List<Tile> seeded = List<Tile>.of(cleaned.tiles);
    int placed = 0;
    for (int i = 0;
        i < seeded.length && placed < seedWeapons.length;
        i++) {
      final Tile t = seeded[i];
      if (!t.walkable ||
          BoardConstants.startPositions.contains(Position(t.x, t.y)) ||
          t.monster != null ||
          t.ally != null ||
          t.weapon != null ||
          t.armor != null ||
          t.healSite ||
          t.cantina) {
        continue;
      }
      seeded[i] = t.copyWith(weapon: seedWeapons[placed]);
      placed++;
    }
    cleaned = cleaned.withTiles(seeded);
  }
  created = created.copyWith(
    players: placed,
    currentPlanet: cleaned,
    planets: <PlanetType, Planet>{
      ...created.planets,
      PlanetType.hoth: cleaned,
    },
  );
  controller.state = created;

  controller.rollDice();
  final Random rng = Random(99);
  for (int step = 0; step < steps; step++) {
    final GameState s = container.read(gameControllerProvider)!;
    if (s.movementPointsRemaining <= 0) {
      await controller.endTurn();
      if (container.read(gameControllerProvider)!.status !=
          GameStatus.inProgress) {
        break;
      }
      controller.rollDice();
      continue;
    }
    // Cible sans monstre, ni case-portail (rester sur la planète).
    final List<Position> targets = controller
        .validMoveTargets()
        .where((Position t) {
          final Tile tile = s.currentPlanet.tileAt(t.x, t.y);
          if (tile.monster != null) return false;
          if (s.portals.any((Portal p) => p.position == t)) return false;
          if (s.teleport?.position == t) return false;
          if (s.cantina?.anchor == t) return false;
          if (s.falcon?.anchor == t) return false;
          return true;
        }).toList();
    if (targets.isEmpty) {
      await controller.endTurn();
      controller.rollDice();
      continue;
    }
    final Position t = targets[rng.nextInt(targets.length)];
    final MoveResult result =
        controller.moveActivePlayerTo(t.x, t.y);
    if (result == MoveResult.itemEncounter) {
      if (container
              .read(gameControllerProvider.notifier).pendingWeaponOffer !=
          null) {
        controller.declinePendingWeapon();
      } else {
        controller.declinePendingArmor();
      }
    } else if (result == MoveResult.allyEncounter) {
      controller.declinePendingAlly();
    }
  }
  return container.read(gameControllerProvider)!.planets[PlanetType.hoth]!;
}

Player _player({
  Faction faction = Faction.rebel,
  List<Ally> allies = const [],
  bool eliminated = false,
  int index = 0,
}) =>
    Player(
      id: 'p${index + 1}',
      name: 'Joueur ${index + 1}',
      faction: faction,
      position: const Position(0, 0),
      planet: PlanetType.hoth,
      level: 3,
      xp: 500,
      attack: 125,
      hp: 1000,
      maxHp: 1000,
      allies: allies,
      eliminated: eliminated,
    );

void main() {
  group('Filtre de tirage (populate direct)', () {
    test('une arme possédée n\'est JAMAIS tirée (20 graines)', () {
      final Weapon allowed = CardConstants.weapons.first;
      final Set<String> taken = <String>{
        for (final Weapon w in CardConstants.weapons) w.name,
      }..remove(allowed.name);

      final Set<String> drawn =
          _drawnNames(taken: taken, pick: (Tile t) => t.weapon?.name);
      expect(drawn, isNotEmpty,
          reason: 'la seule arme autorisée continue de sortir');
      expect(drawn, <String>{allowed.name},
          reason: 'toutes les armes possédées sont exclues du tirage');
    });

    test('un allié possédé n\'est JAMAIS tiré ; sans filtre il sort',
        () {
      const String owned = 'R2-D2';
      // Sanity : sans exclusion, R2-D2 est bien tirable.
      final Set<String> unfiltered =
          _drawnNames(taken: const <String>{},
              pick: (Tile t) => t.ally?.name, seeds: 30);
      expect(unfiltered, contains(owned),
          reason: 'R2-D2 existe dans le deck (test non vacue)');

      final Set<String> drawn = _drawnNames(
          taken: <String>{owned}, pick: (Tile t) => t.ally?.name);
      expect(drawn, isNot(contains(owned)),
          reason: 'R2-D2 possédé : plus jamais tiré');
      expect(drawn, isNotEmpty,
          reason: 'les autres alliés continuent de sortir');
    });

    test('escouade : exclue du tirage dès qu\'elle est marquée prise '
        '(10 exemplaires au total), tirable sinon', () {
      final Ally ewok =
          CardConstants.squads.firstWhere((Ally s) => s.name == 'Ewok');
      // Sanity : sans exclusion, l'escouade sort.
      final Set<String> unfiltered =
          _drawnNames(taken: const <String>{},
              pick: (Tile t) => t.ally?.name, seeds: 20);
      expect(unfiltered, contains(ewok.name),
          reason: 'l\'escouade est tirable quand personne ne la détient');

      final Set<String> drawn = _drawnNames(
          taken: <String>{ewok.name}, pick: (Tile t) => t.ally?.name);
      expect(drawn, isNot(contains(ewok.name)),
          reason: '10 exemplaires au total détenus : plus aucun tirage');
    });
  });

  group('Unicité par le vrai flux de jeu', () {
    test('les cartes de l\'équipe du joueur actif ne sortent plus',
        () async {
      final Weapon bowcaster = CardConstants.weapons
          .firstWhere((Weapon w) => w.name == 'Bowcaster');
      final Ally r2d2 = CardConstants.recruitDeck
          .firstWhere((Ally a) => a.name == 'R2-D2');
      bool leaked = false;
      for (int run = 0; run < 8; run++) {
        final Planet planet = await _walkAndScan(players: <Player>[
          _player(allies: <Ally>[r2d2])
              .copyWith(weapon: bowcaster),
          _player(index: 1),
        ]);
        for (final Tile t in planet.tiles) {
          if (t.ally?.name == 'R2-D2' || t.weapon?.name == 'Bowcaster') {
            leaked = true;
          }
        }
      }
      expect(leaked, isFalse,
          reason: 'R2-D2 et Bowcaster possédés : jamais sur le plateau');
    });

    test('les escouades d\'un joueur (10 exemplaires) ne sortent plus',
        () async {
      final Ally ewok =
          CardConstants.squads.firstWhere((Ally s) => s.name == 'Ewok');
      bool leaked = false;
      for (int run = 0; run < 8; run++) {
        final Planet planet = await _walkAndScan(players: <Player>[
          _player(allies: <Ally>[for (int i = 0; i < 10; i++) ewok]),
          _player(index: 1),
        ]);
        for (final Tile t in planet.tiles) {
          if (t.ally?.name == 'Ewok') leaked = true;
        }
      }
      expect(leaked, isFalse,
          reason: '10 Ewoks détenus (le plafond total) : plus de tirage');
    });

    test('les cartes d\'un joueur ÉLIMINÉ sont remises en jeu '
        '(déterministe)', () async {
      final Ally r2d2 = CardConstants.recruitDeck
          .firstWhere((Ally a) => a.name == 'R2-D2');
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      final GameState created = await controller.createNewGame(NewGameConfig(
        mode: GameMode.chacunPourSoi,
        // TROIS joueurs : avec 2, l'élimination du 2e clôt la partie
        // (survivant unique) et tout déplacement est ignoré.
        playerCount: 3,
        teamSize: 0,
        planetType: PlanetType.hoth,
        characters: <CharacterDefinition>[
          CharacterConstants.characters[0],
          CharacterConstants.characters[1],
          CharacterConstants.characters[2],
        ],
      ));
      // Le joueur 2 est ÉLIMINÉ en détenant R2-D2 : ses cartes ne comptent
      // plus comme « prises ».
      controller.state = created.copyWith(players: <Player>[
        created.players[0],
        created.players[1].copyWith(
          eliminated: true,
          allies: <Ally>[r2d2],
        ),
        created.players[2],
      ]);

      // R2-D2 posé devant le joueur actif : la rencontre doit être
      // NORMALE (offre de recrutement) — preuve que la carte n'est pas
      // considérée comme prise. Si l'éliminé bloquait encore ses cartes,
      // la case serait vidée sans effet (MoveResult.moved).
      // Choix DÉTERMINISTE de la case : n'importe quelle case libre du
      // plateau, le joueur est téléporté à côté (les voisins du départ
      // peuvent tous porter des monstres tirés au peuplement initial).
      final GameState s = container.read(gameControllerProvider)!;
      final Planet planet = s.currentPlanet;
      final Position target = planet.tiles
          .map((Tile t) => Position(t.x, t.y))
          .firstWhere((Position p) =>
              planet.isWalkableAt(p.x, p.y) &&
              planet.tileAt(p.x, p.y).monster == null &&
              planet.tileAt(p.x, p.y).ally == null &&
              planet.tileAt(p.x, p.y).weapon == null &&
              planet.tileAt(p.x, p.y).armor == null &&
              !planet.tileAt(p.x, p.y).healSite &&
              !planet.tileAt(p.x, p.y).cantina &&
              !BoardConstants.startPositions.contains(p) &&
              !s.portals.any((Portal portal) =>
                  portal.position == p && portal.discovered) &&
              s.cantina?.anchor != p &&
              s.falcon?.anchor != p &&
              s.teleport?.position != p &&
              p.chebyshevDistanceTo(s.activePlayer.position) >= 3);
      final Position from = mapService
          .neighborPositions(target, planet)
          .firstWhere((Position p) =>
              planet.isWalkableAt(p.x, p.y) &&
              planet.tileAt(p.x, p.y).monster == null);
      final Planet revealed =
          mapService.revealFogAround(planet, from);
      final List<Tile> tiles = List<Tile>.of(revealed.tiles);
      tiles[target.y * planet.width + target.x] =
          tiles[target.y * planet.width + target.x].copyWith(ally: r2d2);
      controller.state = s.copyWith(
        players: <Player>[
          s.players[0].copyWith(position: from),
          s.players[1],
          s.players[2],
        ],
        // Le premier joueur est tiré AU HASARD à la création : on force
        // l'index 0, celui qui est placé sur `from`.
        currentPlayerIndex: 0,
        currentPlanet: revealed.withTiles(tiles),
        planets: <PlanetType, Planet>{
          ...s.planets,
          PlanetType.hoth: revealed.withTiles(tiles),
        },
        movementPointsRemaining: 2,
      );

      final MoveResult result =
          controller.moveActivePlayerTo(target.x, target.y);
      expect(result, MoveResult.allyEncounter,
          reason: 'la carte d\'un joueur ÉLIMINÉ reste trouvable et '
              'proposable');
      expect(container
              .read(gameControllerProvider.notifier).pendingAllyOffer,
          isNotNull);
    });

    test('une carte ENNEMIE pour l\'actif mais possédée par un autre '
        'joueur ne sort pas (pas d\'attaque possible)', () async {
      // Carte de faction SITH : ennemie pour le joueur actif REBEL, mais
      // amie (recrutable) pour le joueur 2 SITH qui la détient.
      final Ally sithCard = CardConstants.recruitDeck.firstWhere(
          (Ally a) =>
              a.type != AllyType.escouade &&
              a.faction == Faction.sith);
      bool leaked = false;
      for (int run = 0; run < 8; run++) {
        final Planet planet = await _walkAndScan(players: <Player>[
          _player(faction: Faction.rebel, index: 0),
          _player(faction: Faction.sith, index: 1,
              allies: <Ally>[sithCard]),
        ]);
        for (final Tile t in planet.tiles) {
          if (t.ally?.name == sithCard.name) leaked = true;
        }
      }
      expect(leaked, isFalse,
          reason: '${sithCard.name} est dans l\'équipe du joueur 2 : il '
              'ne peut plus attaquer le joueur 1 sur le plateau');
    });
  });

  group('Purge des exemplaires déjà posés (fix 11/10 v2 — « doublon à '
      'moitié »)', () {
    /// Plateau avec LA MÊME carte posée sur deux cases voisines du
    /// joueur (scénario du playtest : trouvée, mise en réserve, puis
    /// retrouvée 5 tours plus tard).
    (GameController, ProviderContainer, List<Position>) twoCopies({
      required Tile Function(Tile) place,
    }) {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Player player = Player(
        id: 'p1',
        name: 'Padmé',
        faction: Faction.rebel,
        position: BoardConstants.startPositions.first,
        planet: PlanetType.hoth,
        level: 4,
        xp: 950,
        attack: 125,
        hp: 1100,
        maxHp: 1300,
      );
      // Brouillard révélé autour du joueur + cases cibles DÉCOUVERTES :
      // sinon le populate du déplacement remplacerait les copies posées
      // par des tirages frais (cases non découvertes).
      final Planet revealed = mapService.revealFogAround(
          planet, player.position);
      final List<Position> targets = mapService
          .validMoveTargets(
              planet: revealed, players: <Player>[player],
              activePlayerIndex: 0)
          .where((Position p) =>
              revealed.tileAt(p.x, p.y).monster == null)
          .take(2)
          .toList();
      assert(targets.length == 2,
          'deux voisins sans monstre requis pour le test');
      final List<Tile> tiles = List<Tile>.of(revealed.tiles);
      for (final Position p in targets) {
        tiles[p.y * planet.width + p.x] = place(
            tiles[p.y * planet.width + p.x]).copyWith(
          discovered: true,
          visible: true,
        );
      }
      final ProviderContainer container = _container(5);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = GameState(
        schemaVersion: GameState.currentSchemaVersion,
        gameId: 'purge_test',
        seed: 42,
        mode: GameMode.chacunPourSoi,
        teamSize: 0,
        planetType: PlanetType.hoth,
        currentPlanet: planet.withTiles(tiles),
        planets: <PlanetType, Planet>{
          PlanetType.hoth: planet.withTiles(tiles)
        },
        players: <Player>[player],
        turn: 9,
        currentPlayerIndex: 0,
        gameTimeSeconds: 0,
        movementPointsRemaining: 2,
        lastDiceRoll: 2,
        bosses: const [],
        portals: const [],
        status: GameStatus.inProgress,
      );
      return (controller, container, targets);
    }

    test('tenue RARE mise en RÉSERVE : le second exemplaire quitte le '
        'plateau (plafond 1)', () {
      final Armor armor = CardConstants.armors
          .firstWhere((Armor a) => a.rarity == Rarity.rare);
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(armor: armor),
      );
      addTearDown(container.dispose);

      expect(controller.moveActivePlayerTo(targets[0].x, targets[0].y),
          MoveResult.itemEncounter);
      controller.storePendingArmor();

      final Planet after =
          container.read(gameControllerProvider)!.currentPlanet;
      expect(after.tiles.where((Tile t) =>
          t.armor?.name == armor.name).length, 0,
          reason: 'la tenue est en réserve : AUCUN exemplaire ne reste '
              'sur le plateau (le scénario du playtest)');
    });

    test('arme RARE ÉQUIPÉE : le second exemplaire quitte le plateau '
        '(plafond 1)', () {
      // Une arme RARE : plafond GDD 1 exemplaire → purge dès la prise.
      final Weapon weapon = CardConstants.weapons
          .firstWhere((Weapon w) => w.rarity == Rarity.rare);
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(weapon: weapon),
      );
      addTearDown(container.dispose);

      expect(controller.moveActivePlayerTo(targets[0].x, targets[0].y),
          MoveResult.itemEncounter);
      expect(controller.equipPendingWeapon(), isTrue);

      final Planet after =
          container.read(gameControllerProvider)!.currentPlanet;
      expect(after.tiles.where((Tile t) =>
          t.weapon?.name == weapon.name).length, 0);
    });

    test('arme COMMUNE équipée (1 exemplaire sur 2) : le second RESTE '
        'trouvable — raccord GDD', () {
      // Raccord GDD (Données cartes.xlsx) : les communs existent en 2
      // cartes. Équiper le premier NE purge PAS le second.
      final Weapon weapon = CardConstants.weapons
          .firstWhere((Weapon w) => w.rarity == Rarity.commun);
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(weapon: weapon),
      );
      addTearDown(container.dispose);

      expect(controller.moveActivePlayerTo(targets[0].x, targets[0].y),
          MoveResult.itemEncounter);
      expect(controller.equipPendingWeapon(), isTrue);

      final Planet after =
          container.read(gameControllerProvider)!.currentPlanet;
      expect(
        after.tileAt(targets[1].x, targets[1].y).weapon?.name,
        weapon.name,
        reason: '1 exemplaire possédé sur 2 : le second reste sur le '
            'plateau',
      );
    });

    test('allié RECRUTÉ : le second exemplaire quitte le plateau', () {
      final Ally ally = CardConstants.recruitDeck.firstWhere(
          (Ally a) =>
              a.type != AllyType.escouade && a.faction == Faction.rebel);
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(ally: ally),
      );
      addTearDown(container.dispose);

      expect(controller.moveActivePlayerTo(targets[0].x, targets[0].y),
          MoveResult.allyEncounter);
      controller.recruitPendingAlly();

      final Planet after =
          container.read(gameControllerProvider)!.currentPlanet;
      expect(after.tiles.where((Tile t) =>
          t.ally?.name == ally.name).length, 0,
          reason: 'l\'allié recruté est unique sur tout le plateau');
    });

    test('escouade SOUS le plafond : l\'autre exemplaire reste trouvable',
        () {
      final Ally ewok =
          CardConstants.squads.firstWhere((Ally s) => s.name == 'Ewok');
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(ally: ewok),
      );
      addTearDown(container.dispose);

      expect(controller.moveActivePlayerTo(targets[0].x, targets[0].y),
          MoveResult.allyEncounter);
      controller.recruitPendingAlly();

      final Planet after =
          container.read(gameControllerProvider)!.currentPlanet;
      expect(
        after.tileAt(targets[1].x, targets[1].y).ally?.name,
        'Ewok',
        reason: 'une seule escouade détenue (< 10) : le second '
            'exemplaire POSÉ reste sur le plateau (le populate peut '
            'légitimement en tirer d\'autres sur les nouvelles cases)',
      );
    });

    test('vieille sauvegarde : marcher sur une carte DÉJÀ possédée ne '
        'rouvre aucune offre, la copie disparaît', () {
      // Tenue RARE (plafond 1) : possédée → toute copie posée disparaît.
      final Armor armor = CardConstants.armors
          .firstWhere((Armor a) => a.rarity == Rarity.rare);
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(armor: armor),
      );
      addTearDown(container.dispose);
      // Le joueur possède DÉJÀ la tenue (réserve) — état d'une partie
      // créée avant le fix.
      final GameState s = container.read(gameControllerProvider)!;
      controller.state = s.copyWith(
        players: <Player>[
          s.players[0].copyWith(storedArmor: armor),
        ],
      );

      final MoveResult result =
          controller.moveActivePlayerTo(targets[0].x, targets[0].y);
      expect(result, MoveResult.moved,
          reason: 'carte déjà possédée : ni offre ni effet');
      expect(container
          .read(gameControllerProvider.notifier).pendingArmorOffer, isNull);
      expect(
        container.read(gameControllerProvider)!.currentPlanet
            .tileAt(targets[0].x, targets[0].y).armor,
        isNull,
        reason: 'la copie disparaît du plateau',
      );
      expect(container.read(gameControllerProvider)!.players[0].storedArmor,
          isNotNull,
          reason: 'la possession du joueur est intacte');
    });

    test('tenue COMMUNE possédée 2 fois (2 joueurs) : plus aucune copie '
        'sur le plateau (plafond GDD 2 atteint)', () {
      final Armor armor = CardConstants.armors
          .firstWhere((Armor a) => a.rarity == Rarity.commun);
      final (GameController controller, ProviderContainer container,
          List<Position> targets) = twoCopies(
        place: (Tile t) => t.copyWith(armor: armor),
      );
      addTearDown(container.dispose);
      // Deux joueurs NON éliminés la possèdent chacun : 2/2 → plafond.
      final GameState s = container.read(gameControllerProvider)!;
      controller.state = s.copyWith(
        players: <Player>[
          s.players[0].copyWith(storedArmor: armor),
          s.players[0].copyWith(
            id: 'p2',
            name: 'Joueur 2',
            storedArmor: armor,
          ),
        ],
      );

      final MoveResult result =
          controller.moveActivePlayerTo(targets[0].x, targets[0].y);
      expect(result, MoveResult.moved,
          reason: 'plafond 2/2 atteint : la copie posée disparaît sans '
              'effet');
      expect(
        container.read(gameControllerProvider)!.currentPlanet.tiles
            .where((Tile t) => t.armor?.name == armor.name)
            .length,
        0,
        reason: 'purge de la copie posée',
      );
    });

    test('2 exemplaires POSÉS d\'un commun, 0 possédé : le tirage n\'en '
        'produit pas de 3e', () async {
      final Weapon weapon = CardConstants.weapons
          .firstWhere((Weapon w) => w.rarity == Rarity.commun);
      bool leaked = false;
      for (int run = 0; run < 8; run++) {
        final Planet planet = await _walkAndScan(
          players: <Player>[_player(index: 0), _player(index: 1)],
          seedWeapons: <Weapon>[weapon, weapon],
        );
        final int count = planet.tiles
            .where((Tile t) => t.weapon?.name == weapon.name)
            .length;
        if (count > 2) leaked = true;
      }
      expect(leaked, isFalse,
          reason: 'les 2 cartes GDD existent déjà sur le plateau : '
              'aucun tirage supplémentaire');
    });
  });
}
