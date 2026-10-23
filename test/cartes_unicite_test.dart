import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/character_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/ally.dart';
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
/// finale (Hothe) pour scan.
Future<Planet> _walkAndScan({
  required List<Player> players,
  int steps = 14,
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
  final Planet cleaned = created.currentPlanet.withTiles(<Tile>[
    for (final Tile t in created.currentPlanet.tiles)
      t.copyWith(
        clearAlly: true,
        clearWeapon: true,
        clearArmor: true,
        healSite: false,
      ),
  ]);
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

    test('les cartes d\'un joueur ÉLIMINÉ sont remises en jeu', () async {
      final Ally r2d2 = CardConstants.recruitDeck
          .firstWhere((Ally a) => a.name == 'R2-D2');
      bool appeared = false;
      for (int run = 0; run < 12; run++) {
        // Trois joueurs : le survivant-check (chacun pour soi) ne clôt
        // pas la partie, et l'éliminé libère R2-D2.
        final Planet planet = await _walkAndScan(players: <Player>[
          _player(index: 0),
          _player(index: 1, allies: <Ally>[r2d2], eliminated: true),
          _player(faction: Faction.sith, index: 2),
        ]);
        for (final Tile t in planet.tiles) {
          if (t.ally?.name == 'R2-D2') appeared = true;
        }
      }
      expect(appeared, isTrue,
          reason: 'le joueur éliminé libère ses cartes : R2-D2 peut '
              'ressortir pour les survivants');
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
}
