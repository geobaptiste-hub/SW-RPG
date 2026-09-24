import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/core/constants/game_constants.dart';
import 'package:star_wars_rpg/core/constants/monster_constants.dart';
import 'package:star_wars_rpg/core/constants/planet_constants.dart';
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/boss.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/portal.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/services/combat_service.dart';
import 'package:star_wars_rpg/services/game_service.dart';
import 'package:star_wars_rpg/services/map_service.dart';
import 'package:star_wars_rpg/services/save_service.dart';

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

Planet _mainPlanet() =>
    mapService.generateStartPlanet(PlanetType.coruscant, seed: 42);

Planet _secondary(PlanetType type) =>
    mapService.generateSecondaryPlanet(type, seed: 7);

Player _player({
  Position position = const Position(0, 0),
  PlanetType planet = PlanetType.coruscant,
  int level = 1,
  int? hp,
  int? attack,
  List<Ally> allies = const [],
  Faction faction = Faction.jedi,
  int index = 0,
}) {
  final int lvl = level.clamp(1, 6);
  return Player(
    id: 'p${index + 1}',
    name: 'Joueur ${index + 1}',
    faction: faction,
    position: position,
    planet: planet,
    level: lvl,
    xp: 0,
    attack: attack ?? GameConstants.attackForLevel(lvl),
    hp: hp ?? GameConstants.hpForLevel(lvl),
    maxHp: GameConstants.hpForLevel(lvl),
    allies: allies,
  );
}

Boss _boss(
  BossType type,
  PlanetType planet,
  Position position, {
  bool isGone = false,
}) =>
    Boss(
      name: type.displayName,
      type: type,
      planet: planet,
      hp: GameConstants.bossHp,
      attackMin: GameConstants.bossAttackMin,
      attackMax: GameConstants.bossAttackMax,
      position: position,
      isGone: isGone,
    );

GameState _state({
  required Planet planet,
  required PlanetType planetType,
  required List<Player> players,
  List<Boss> bosses = const [],
  List<Portal> portals = const [],
  Map<PlanetType, Planet> planets = const {},
  int movement = 3,
}) {
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'sprint5_test',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: planetType,
    currentPlanet: planet,
    planets: planets,
    players: players,
    turn: 1,
    currentPlayerIndex: 0,
    gameTimeSeconds: 0,
    movementPointsRemaining: movement,
    lastDiceRoll: movement,
    bosses: bosses,
    portals: portals,
    status: GameStatus.inProgress,
  );
}

void main() {
  group('Attaque de boss (CDC §16)', () {
    test('rollBossAttack : 250 à 500, par pas de 10', () {
      final CombatService combat = CombatService(random: Random(7));
      for (int i = 0; i < 200; i++) {
        final int roll = combat.rollBossAttack();
        expect(roll, inInclusiveRange(250, 500));
        expect((roll - 250) % 10, 0, reason: 'pas de 10 requis');
      }
    });

    test('FIX 20/09 : riposte de monstre aléatoire ±10 % (10 → 9, 10 ou 11)',
        () {
      final CombatService combat = CombatService(random: Random(7));
      final Set<int> seen = <int>{};
      for (int i = 0; i < 300; i++) {
        final int roll = combat.rollMonsterAttack(10);
        expect(roll, inInclusiveRange(9, 11),
            reason: 'attaque 10 ±10 % → 9 à 11 (plus de montant fixe)');
        seen.add(roll);
      }
      expect(seen.length, 3, reason: 'les trois valeurs sortent (9, 10, 11)');
      // Autre palier : 50 ATK → 45 à 55.
      for (int i = 0; i < 200; i++) {
        expect(combat.rollMonsterAttack(50), inInclusiveRange(45, 55));
      }
    });
  });

  group('Combat de boss (GDD §12)', () {
    test('startBossCombat : session initialisée sur le boss ciblé', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameState state = _state(
        planet: _secondary(PlanetType.mustafar),
        planetType: PlanetType.mustafar,
        players: <Player>[_player(planet: PlanetType.mustafar)],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
        ],
      );
      container.read(gameControllerProvider.notifier).state = state;

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startBossCombat(state.bosses.first);

      final CombatSession? session = container.read(combatControllerProvider);
      expect(session, isNotNull);
      expect(session!.kind, CombatKind.boss);
      expect(session.bossType, BossType.exogorth);
      expect(session.monsterHpRemaining, GameConstants.bossHp);
    });

    test('le boss riposte après chaque attaque, victoire = XP de rang '
        '400 + fuite', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Player player = _player(
        planet: PlanetType.mustafar,
        level: 6,
        index: 0,
      );
      final Player other = _player(
        planet: PlanetType.coruscant,
        index: 1,
      );
      final GameState state = _state(
        planet: _secondary(PlanetType.mustafar),
        planetType: PlanetType.mustafar,
        players: <Player>[player, other],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
        ],
      );
      container.read(gameControllerProvider.notifier).state = state;

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startBossCombat(state.bosses.first);

      int guard = 0;
      while (!(container.read(combatControllerProvider)?.finished ?? false)) {
        combat.attack();
        guard++;
        expect(guard, lessThan(30), reason: 'le combat doit se terminer');
      }

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.victory, isTrue);
      expect(session.playerEliminated, isFalse);
      expect(session.xpGained, GameConstants.bossXpRewards[0]);
      expect(session.attacksUsed, guard);
      expect(session.damageTaken, greaterThan(0));

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.players[0].defeatedBosses, contains(BossType.exogorth));
      expect(after.status, GameStatus.inProgress);
      final Boss boss = after.bosses.single;
      expect(boss.defeatedByPlayerIds, contains('p1'));
      // Deux joueurs actifs : une seule victoire → le boss prend la fuite.
      expect(boss.isGone, isTrue);
      expect(boss.isDefinitivelyDead(2), isFalse);
    });

    test('un joueur de bas niveau finit éliminé par les ripostes du boss '
        '(mais survit au premier coup — plafond playtest)', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameState state = _state(
        planet: _secondary(PlanetType.mustafar),
        planetType: PlanetType.mustafar,
        players: <Player>[_player(planet: PlanetType.mustafar)],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
        ],
      );
      container.read(gameControllerProvider.notifier).state = state;

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startBossCombat(state.bosses.first);

      // Niveau 1 : riposte 250-500 → x 0,5 puis plafond 60 % des PV max
      // (120 PV par coup) : le premier coup ne tue plus, le boss finit par
      // l'emporter (10 000 PV inatteignables).
      combat.attack();
      expect(container.read(combatControllerProvider)!.playerEliminated,
          isFalse, reason: 'plafond 60 % PV max : survie au premier coup');

      int guard = 0;
      while (!(container.read(combatControllerProvider)?.finished ?? false)) {
        combat.attack();
        guard++;
        expect(guard, lessThan(15), reason: 'le combat doit se terminer');
      }

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.finished, isTrue);
      expect(session.victory, isFalse);
      expect(session.playerEliminated, isTrue);
      expect(container.read(gameControllerProvider)!.activePlayer.eliminated,
          isTrue);
    });

    test('la fuite est autorisée en combat de boss (GDD §10)', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameState state = _state(
        planet: _secondary(PlanetType.mustafar),
        planetType: PlanetType.mustafar,
        players: <Player>[
          _player(planet: PlanetType.mustafar, level: 6),
        ],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
        ],
      );
      container.read(gameControllerProvider.notifier).state = state;

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startBossCombat(state.bosses.first);
      final int hpBefore =
          container.read(gameControllerProvider)!.activePlayer.hp;
      combat.flee();

      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.finished, isTrue);
      expect(session.fled, isTrue);
      expect(session.victory, isFalse);
      expect(session.xpGained, 0);
      expect(container.read(gameControllerProvider)!.activePlayer.hp,
          hpBefore, reason: 'fuir conserve les PV');
    });

    test('FIX 20/09 : un boss blessé GARDE ses PV après la fuite du joueur',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameState state = _state(
        planet: _secondary(PlanetType.mustafar),
        planetType: PlanetType.mustafar,
        players: <Player>[
          _player(planet: PlanetType.mustafar, level: 6),
        ],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
        ],
      );
      container.read(gameControllerProvider.notifier).state = state;

      final CombatController combat =
          container.read(combatControllerProvider.notifier);
      combat.startBossCombat(state.bosses.first);
      // Un seul coup au niveau 6 : bien en dessous des 10000 PV du boss.
      combat.attack();
      final CombatSession session = container.read(combatControllerProvider)!;
      expect(session.finished, isFalse,
          reason: 'le boss survit au premier coup (ATK N6 < 10000)');
      expect(session.monsterHpRemaining, lessThan(GameConstants.bossHp),
          reason: 'le coup a blessé le boss');
      combat.flee();

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.bosses.single.hp, session.monsterHpRemaining,
          reason: 'le boss garde les dégâts infligés : il ne se remet pas '
              'à 10000 PV');

      // Le prochain combat contre LUI repart des PV restants.
      container
          .read(combatControllerProvider.notifier)
          .startBossCombat(after.bosses.single);
      expect(container.read(combatControllerProvider)!.monsterHpRemaining,
          session.monsterHpRemaining,
          reason: 'le joueur suivant affronte le boss blessé');
    });

    test('FIX 20/09 : le boss vaincu réapparaît à pleine vie (10000 PV)',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      // Boss déjà blessé lors d\'un combat précédent (fuite d\'un joueur).
      final Boss damaged = _boss(
              BossType.exogorth, PlanetType.mustafar, const Position(3, 4))
          .copyWith(hp: 5600);
      final Player player = _player(
        planet: PlanetType.mustafar,
        level: 6,
      );
      final Player other = _player(
        planet: PlanetType.coruscant,
        index: 1,
      );
      container.read(gameControllerProvider.notifier).state = _state(
        planet: _secondary(PlanetType.mustafar),
        planetType: PlanetType.mustafar,
        players: <Player>[player, other],
        bosses: <Boss>[damaged],
      );

      container
          .read(gameControllerProvider.notifier)
          .applyBossVictory(type: BossType.exogorth, playerHp: player.hp);

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.bosses.single.hp, GameConstants.bossHp,
          reason: 'une fois vaincu, le boss réapparaît à 10000 PV');
      expect(after.bosses.single.isGone, isTrue,
          reason: 'deux joueurs actifs : il reprend la fuite');
    });

    test('un tank « dégâts divisés » réduit la riposte du boss de moitié',
        () {
      // Même graine de combat : la seule différence est la présence du tank,
      // donc les dégâts subis doivent être strictement inférieurs.
      int run({required bool withTank}) {
        final ProviderContainer container = _container(11);
        addTearDown(container.dispose);
        final Player player = _player(
          planet: PlanetType.mustafar,
          level: 6,
          allies: withTank
              ? <Ally>[
                  Ally.tank(
                    name: 'Chewbacca',
                    faction: Faction.rebel,
                    rarity: Rarity.rare,
                    cost: 1,
                    dividesDamage: true,
                  ),
                ]
              : const <Ally>[],
        );
        container.read(gameControllerProvider.notifier).state = _state(
          planet: _secondary(PlanetType.mustafar),
          planetType: PlanetType.mustafar,
          players: <Player>[player],
          bosses: <Boss>[
            _boss(
                BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
          ],
        );
        final CombatController combat =
            container.read(combatControllerProvider.notifier);
        combat.startBossCombat(
            container.read(gameControllerProvider)!.bosses.first);
        // Deux attaques : le boss est encore loin d'être vaincu (10 000 PV).
        combat.attack();
        combat.attack();
        return container.read(combatControllerProvider)!.damageTaken;
      }

      final int withoutTank = run(withTank: false);
      final int withTank = run(withTank: true);
      expect(withoutTank, greaterThan(0));
      expect(withTank, lessThan(withoutTank),
          reason: 'la riposte du boss est divisée par 2 (arrondi supérieur)');
    });
  });

  group('Rencontres boss sur le plateau (Sprint 5)', () {
    test('boss verrouillé avant le N5 : entrée refusée, 1 point perdu',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet mustafar = _secondary(PlanetType.mustafar);
      const Position base = PlanetConstants.secondaryPortalPosition;
      final Position neighbor = mapService
          .neighborPositions(base, mustafar)
          .firstWhere((Position p) => mustafar.isWalkableAt(p.x, p.y));
      final Player player = _player(
        position: base,
        planet: PlanetType.mustafar,
        level: 1,
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: mustafar,
        planetType: PlanetType.mustafar,
        players: <Player>[player],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, neighbor),
        ],
        movement: 3,
      );

      final MoveResult result = controller.moveActivePlayerTo(
          neighbor.x, neighbor.y);

      expect(result, MoveResult.bossBlocked);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.position, base,
          reason: 'l’entrée dans la case du boss est refusée');
      expect(after.movementPointsRemaining, 2,
          reason: 'le point de déplacement est perdu');
    });

    test('boss déverrouillé (un joueur N5) : combat de boss', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet mustafar = _secondary(PlanetType.mustafar);
      const Position base = PlanetConstants.secondaryPortalPosition;
      final Position neighbor = mapService
          .neighborPositions(base, mustafar)
          .firstWhere((Position p) => mustafar.isWalkableAt(p.x, p.y));
      final Player player = _player(
        position: base,
        planet: PlanetType.mustafar,
        level: 5,
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: mustafar,
        planetType: PlanetType.mustafar,
        players: <Player>[player],
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, neighbor),
        ],
        movement: 3,
      );

      final MoveResult result = controller.moveActivePlayerTo(
          neighbor.x, neighbor.y);

      expect(result, MoveResult.bossEncounter);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.position, neighbor,
          reason: 'le pion entre dans la case du boss');
      expect(after.movementPointsRemaining, 2);
    });
  });

  group('Voyage par portail (GDD §5)', () {
    test('ALLER : la planète courante devient la planète liée au portail',
        () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet main = _mainPlanet();
      final Player player = _player();
      final Position portalPos = mapService
          .validMoveTargets(
              planet: main, players: <Player>[player], activePlayerIndex: 0)
          .first;
      // Case du portail déjà découverte et vide : le populate ne doit pas
      // y poser de contenu (la rencontre passerait avant le voyage).
      final List<Tile> tiles = List<Tile>.of(main.tiles);
      final int index = portalPos.y * main.width + portalPos.x;
      tiles[index] = tiles[index].copyWith(discovered: true);

      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: main.withTiles(tiles),
        planetType: PlanetType.coruscant,
        players: <Player>[player],
        portals: <Portal>[
          Portal(
              destination: PlanetType.dagobah,
              position: portalPos,
              discovered: true),
        ],
        movement: 3,
      );

      final MoveResult result =
          controller.moveActivePlayerTo(portalPos.x, portalPos.y);

      expect(result, MoveResult.portalTravel);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.planetType, PlanetType.dagobah);
      expect(after.currentPlanet.type, PlanetType.dagobah);
      expect(after.currentPlanet.width, PlanetConstants.secondaryGridWidth);
      expect(after.activePlayer.position,
          PlanetConstants.secondaryPortalPosition);
      expect(after.activePlayer.planet, PlanetType.dagobah);
      expect(after.activePlayer.returnPlanet, PlanetType.coruscant);
      expect(after.activePlayer.returnPosition, portalPos);
      expect(after.movementPointsRemaining, 2,
          reason: 'le pas sur le portail coûte exactement 1 point '
              '(pas de double décrément)');
    });

    test('RETOUR : le portail central ramène au point d’origine', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet main = _mainPlanet();
      final Planet dagobah = _secondary(PlanetType.dagobah);
      final Position side = mapService
          .neighborPositions(PlanetConstants.secondaryPortalPosition, dagobah)
          .firstWhere((Position p) => dagobah.isWalkableAt(p.x, p.y));
      // Portail central pré-découvert : le populate ne doit pas y poser de
      // contenu (la rencontre passerait avant le voyage).
      final List<Tile> tiles = List<Tile>.of(dagobah.tiles);
      const Position portal = PlanetConstants.secondaryPortalPosition;
      final int index = portal.y * dagobah.width + portal.x;
      tiles[index] = tiles[index].copyWith(discovered: true);
      final Planet crafted = dagobah.withTiles(tiles);
      final Player traveler = _player(
        position: side,
        planet: PlanetType.dagobah,
      ).copyWith(
        returnPlanet: PlanetType.coruscant,
        returnPosition: const Position(0, 0),
      );
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: crafted,
        planetType: PlanetType.dagobah,
        players: <Player>[traveler],
        planets: <PlanetType, Planet>{
          PlanetType.coruscant: main,
          PlanetType.dagobah: crafted,
        },
        movement: 3,
      );

      final MoveResult result = controller.moveActivePlayerTo(
          PlanetConstants.secondaryPortalPosition.x,
          PlanetConstants.secondaryPortalPosition.y);

      expect(result, MoveResult.portalTravel);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.planetType, PlanetType.coruscant);
      expect(after.activePlayer.planet, PlanetType.coruscant);
      expect(after.activePlayer.position, const Position(0, 0));
      expect(after.activePlayer.returnPlanet, isNull);
      expect(after.activePlayer.returnPosition, isNull);
      expect(after.movementPointsRemaining, 2);
    });

    test('FIX 19/09 : pas de voyage fantôme sur une planète secondaire — '
        'une case qui coïncide avec un portail principal reste une case '
        'ordinaire', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet dagobah = _secondary(PlanetType.dagobah);
      final Planet main = _mainPlanet();
      // Un joueur SANS retour prévu (returnPlanet null) sur Dagobah, à côté
      // de la case (2,3) — position qui coïncide avec un portail de la
      // planète principale : avant le fix, marcher dessus « voyageait ».
      const Position phantom = Position(2, 3);
      final Player traveler =
          _player(position: const Position(2, 2), planet: PlanetType.dagobah);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: dagobah,
        planetType: PlanetType.dagobah,
        players: <Player>[traveler],
        portals: <Portal>[
          Portal(
              destination: PlanetType.mustafar,
              position: phantom,
              discovered: true),
        ],
        planets: <PlanetType, Planet>{
          PlanetType.coruscant: main,
          PlanetType.dagobah: dagobah,
        },
        movement: 3,
      );

      final MoveResult result =
          controller.moveActivePlayerTo(phantom.x, phantom.y);

      expect(result, MoveResult.moved,
          reason: 'une case ordinaire d\'une planète secondaire ne doit pas '
              'déclencher un portail de la planète principale');
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.planet, PlanetType.dagobah,
          reason: 'le joueur reste sur sa planète secondaire');
      expect(after.activePlayer.position, phantom);
      expect(after.activePlayer.returnPlanet, isNull,
          reason: 'returnPlanet ne doit pas être corrompu par un voyage '
              'fantôme (c\'est ce qui coincait le joueur sur la planète)');
      expect(after.activePlayer.returnPosition, isNull);
    });

    test('FIX 19/09 : le portail central sans origine connue ne téléporte '
        'plus en (0,0) — il ne fait rien et ne consomme pas le pas', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Planet dagobah = _secondary(PlanetType.dagobah);
      // Joueur à côté du portail central, SANS returnPlanet/returnPosition
      // (état corrompu / ancien voyage fantôme) : avant le fix, le portail
      // l'envoyait en (0,0) SUR LA MÊME planète — coincé pour de bon.
      final Player stuck =
          _player(position: const Position(4, 3), planet: PlanetType.dagobah);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: dagobah,
        planetType: PlanetType.dagobah,
        players: <Player>[stuck],
        movement: 3,
      );

      final MoveResult result = controller.moveActivePlayerTo(4, 4);

      expect(result, MoveResult.moved,
          reason: 'sans origine connue, le retour ne doit pas se déclencher');
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.activePlayer.position, const Position(4, 4),
          reason: 'le pion se contente d\'entrer dans la case du portail — '
              'PAS de téléportation par défaut en (0,0)');
      expect(after.activePlayer.planet, PlanetType.dagobah,
          reason: 'le joueur n\'est pas renvoyé sur une planète au hasard');
      expect(after.activePlayer.returnPlanet, isNull);
      expect(after.activePlayer.returnPosition, isNull);
      expect(after.movementPointsRemaining, 2,
          reason: 'un seul pas consommé (le déplacement ordinaire), comme '
              'tout pas sur une case');
    });
  });

  group('FIX 19/09 : un boss ne partage JAMAIS sa case avec un contenu', () {
    test('la réapparition d\'un boss fugué évite contenus et portail central',
        () {
      final Planet dagobah = _secondary(PlanetType.dagobah);
      // Planète entièrement découverte ; un monstre sur (0,0), une case de
      // soin sur (8,8) : le boss fugué doit réapparaître ailleurs.
      final List<Tile> tiles = <Tile>[
        for (final Tile t in dagobah.tiles)
          t.copyWith(discovered: true, visible: false),
      ];
      tiles[0] = tiles[0]
          .copyWith(monster: MonsterConstants.randomMonster(Random(1)));
      tiles[80] = tiles[80].copyWith(healSite: true);
      final Planet crafted = dagobah.withTiles(tiles);
      final Player watcher =
          _player(position: const Position(0, 1), planet: PlanetType.dagobah);
      final Boss fugue = _boss(
          BossType.rancor, PlanetType.dagobah, const Position(4, 4),
          isGone: true);

      final movement = mapService.moveBossesAtTurnEnd(
        bosses: <Boss>[fugue],
        planets: <PlanetType, Planet>{PlanetType.dagobah: crafted},
        players: <Player>[watcher],
        rng: Random(3),
      );

      final Boss reappeared = movement.bosses.first;
      expect(reappeared.isGone, isFalse);
      expect(reappeared.position, isNot(const Position(4, 4)),
          reason: 'le boss ne bloque pas le portail central du retour');
      expect(reappeared.position, isNot(const Position(0, 0)),
          reason: 'pas de boss sur la case du monstre');
      expect(reappeared.position, isNot(const Position(8, 8)),
          reason: 'pas de boss sur la case de soin');
      final Tile tile =
          crafted.tileAt(reappeared.position.x, reappeared.position.y);
      expect(tile.monster, isNull);
      expect(tile.ally, isNull);
      expect(tile.weapon, isNull);
      expect(tile.armor, isNull);
      expect(tile.healSite, isFalse);
    });

    test('le peuplement ne pose aucun contenu sur les cases de boss', () {
      final Planet planet =
          mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
      final Set<Position> bossPositions = <Position>{
        const Position(5, 5),
        const Position(10, 10),
      };
      final Planet revealed = mapService.revealFogAround(
        planet,
        const Position(10, 10),
        radius: 30,
      );
      final populate = mapService.populateNewlyDiscoveredTiles(
        before: planet,
        after: revealed,
        phase: GamePhase.fin,
        rng: Random(11),
        occupied: const <Position>{},
        existingPortals: const [],
        bossUnlocked: false,
        avoidPositions: bossPositions,
      );
      for (final Position position in bossPositions) {
        final Tile tile = populate.planet.tileAt(position.x, position.y);
        expect(tile.monster, isNull, reason: 'case $position : boss présent');
        expect(tile.ally, isNull);
        expect(tile.weapon, isNull);
        expect(tile.armor, isNull);
        expect(tile.healSite, isFalse);
      }
    });
  });

  group('Conditions de victoire par boss (GDD §16)', () {
    test('chacun pour soi : 3 boss de factions adverses → victoire', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: _mainPlanet(),
        planetType: PlanetType.coruscant,
        players: <Player>[_player(level: 6)], // Jedi
        bosses: <Boss>[
          _boss(BossType.exogorth, PlanetType.mustafar, const Position(3, 4)),
          _boss(BossType.kraytDragon, PlanetType.yavin4, const Position(3, 4)),
          _boss(BossType.atAt, PlanetType.etoileNoire, const Position(3, 4)),
        ],
      );

      controller.applyBossVictory(type: BossType.exogorth, playerHp: 100);
      expect(container.read(gameControllerProvider)!.status,
          GameStatus.inProgress);
      controller.applyBossVictory(type: BossType.kraytDragon, playerHp: 100);
      expect(container.read(gameControllerProvider)!.status,
          GameStatus.inProgress);
      controller.applyBossVictory(type: BossType.atAt, playerHp: 100);
      expect(container.read(gameControllerProvider)!.status,
          GameStatus.finished);
    });

    test('le boss de sa propre faction ne compte pas', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: _mainPlanet(),
        planetType: PlanetType.coruscant,
        players: <Player>[_player(level: 6)], // Jedi
        bosses: <Boss>[
          _boss(BossType.rancor, PlanetType.dagobah, const Position(3, 4)),
        ],
      );

      controller.applyBossVictory(type: BossType.rancor, playerHp: 100);
      final GameState after = container.read(gameControllerProvider)!;
      expect(after.status, GameStatus.inProgress,
          reason: 'le Rancor est Jedi : il ne compte pas pour un joueur Jedi');
      expect(after.players[0].defeatedBosses, contains(BossType.rancor));
    });
  });

  group('Apparition des boss au N5 (Sprint 5)', () {
    test('un joueur N5 fait apparaître un boss par planète secondaire '
        'générée', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
        for (final PlanetType type in PlanetConstants.secondaryPlanets)
          type: _secondary(type),
      };
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: _mainPlanet(),
        planetType: PlanetType.coruscant,
        players: <Player>[_player(level: 5)],
        planets: planets,
      );

      // Déclencheur quelconque appelant _maybeSpawnBosses.
      controller.applyPlayerCombatResult(
        defenderIndex: 0,
        defenderHp: 100,
        defenderEliminated: false,
        attackerXp: 0,
      );

      final GameState after = container.read(gameControllerProvider)!;
      expect(after.bosses.length, PlanetConstants.secondaryPlanets.length);
      for (final PlanetType type in PlanetConstants.secondaryPlanets) {
        final Boss boss =
            after.bosses.firstWhere((Boss b) => b.planet == type);
        expect(boss.hp, GameConstants.bossHp);
        expect(
          planets[type]!.tileAt(boss.position.x, boss.position.y).walkable,
          isTrue,
        );
        expect(boss.position, isNot(PlanetConstants.secondaryPortalPosition));
      }
      expect(container.read(gameControllerProvider.notifier).bossAwakeningPlanets,
          PlanetConstants.secondaryPlanets);
    });

    test('aucun boss tant que personne n’est N5', () {
      final ProviderContainer container = _container(5);
      addTearDown(container.dispose);
      final Map<PlanetType, Planet> planets = <PlanetType, Planet>{
        for (final PlanetType type in PlanetConstants.secondaryPlanets)
          type: _secondary(type),
      };
      final GameController controller =
          container.read(gameControllerProvider.notifier);
      controller.state = _state(
        planet: _mainPlanet(),
        planetType: PlanetType.coruscant,
        players: <Player>[_player(level: 4)],
        planets: planets,
      );

      controller.applyPlayerCombatResult(
        defenderIndex: 0,
        defenderHp: 100,
        defenderEliminated: false,
        attackerXp: 0,
      );

      expect(container.read(gameControllerProvider)!.bosses, isEmpty);
    });
  });
}
