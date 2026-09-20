import 'dart:math';

import 'package:star_wars_rpg/core/constants/game_constants.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_wars_rpg/core/constants/card_constants.dart';
import 'package:star_wars_rpg/core/constants/enums.dart';
import 'package:star_wars_rpg/models/ally.dart';
import 'package:star_wars_rpg/models/armor.dart';
import 'package:star_wars_rpg/models/game_state.dart';
import 'package:star_wars_rpg/models/planet.dart';
import 'package:star_wars_rpg/models/player.dart';
import 'package:star_wars_rpg/models/tile.dart';
import 'package:star_wars_rpg/models/weapon.dart';
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

ProviderContainer _container() => ProviderContainer(overrides: <Override>[
      saveServiceProvider.overrideWithValue(_FakeSaveService()),
      combatServiceProvider.overrideWithValue(CombatService(random: Random(9))),
    ]);

GameState _stateWith(Planet planet, List<Player> players,
    {int activeIndex = 0}) {
  return GameState(
    schemaVersion: GameState.currentSchemaVersion,
    gameId: 'equip_test',
    seed: 42,
    mode: GameMode.chacunPourSoi,
    teamSize: 0,
    planetType: PlanetType.hoth,
    currentPlanet: planet,
    players: players,
    turn: 1,
    currentPlayerIndex: activeIndex,
    gameTimeSeconds: 0,
    movementPointsRemaining: 3,
    lastDiceRoll: 3,
    bosses: const [],
    portals: const [],
    status: GameStatus.inProgress,
  );
}

/// Pose un objet sur un voisin du joueur actif et renvoie sa position.
Position _neighborWith(
  Planet planet,
  List<Player> players, {
  Ally? ally,
  Weapon? weapon,
  Armor? armor,
  bool healSite = false,
}) {
  final Position target = MapService()
      .validMoveTargets(planet: planet, players: players, activePlayerIndex: 0)
      .first;
  final int index = target.y * planet.width + target.x;
  // Mutation en place : planet.tiles est une liste modifiable.
  planet.tiles[index] = planet.tiles[index].copyWith(
    ally: ally,
    weapon: weapon,
    armor: armor,
    healSite: healSite,
  );
  return target;
}

void main() {
  late ProviderContainer container;
  late MapService mapService;

  setUp(() {
    container = _container();
    mapService = MapService();
  });
  tearDown(() => container.dispose());

  test('rencontre allié : recrutement avec coût et soin instantané', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      // Rare recrutable a partir du niveau 3 (restriction playtest).
      level: 3,
      xp: 0,
      attack: 125,
      hp: 100,
      maxHp: 200,
    );
    final Ally r2d2 = CardConstants.healers
        .firstWhere((Ally a) => a.name == 'R2-D2');
    final Position target = _neighborWith(planet, <Player>[player], ally: r2d2);

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);

    final MoveResult result =
        controller.moveActivePlayerTo(target.x, target.y);
    expect(result, MoveResult.allyEncounter);
    expect(container.read(gameControllerProvider.notifier).pendingAllyOffer?.name,
        'R2-D2');

    controller.recruitPendingAlly();
    final GameState after = container.read(gameControllerProvider)!;
    expect(after.activePlayer.allies.length, 1);
    expect(after.activePlayer.allies.first.name, 'R2-D2');
    expect(after.activePlayer.hp, 100,
        reason: 'le soin instantané est une CHARGE à activer depuis '
            'l\'équipe (retours playtest) — plus d\'auto-soin');
    expect(controller.pendingAllyOffer, isNull);

    // Activation de la charge depuis l'écran Équipe.
    expect(
        container
            .read(gameControllerProvider.notifier)
            .useHealerHeal(0),
        isTrue);
    final GameState healed = container.read(gameControllerProvider)!;
    expect(healed.activePlayer.hp, 200,
        reason: '100 PV + 500 de charge de soin, plafonné à 200 max PV');
    expect(healed.activePlayer.allies.first.healInstant, isNull,
        reason: 'la charge est consommée après usage');
  });

  test('recrutement refusé si places insuffisantes', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final List<Ally> fullTeam = List<Ally>.generate(
        10, (int i) => CardConstants.squads.first); // 10 × 1 PP = équipe pleine
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
      allies: fullTeam,
    );
    final Ally tank = CardConstants.tanks.first;
    final Position target = _neighborWith(planet, <Player>[player], ally: tank);

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);
    controller.moveActivePlayerTo(target.x, target.y);

    expect(controller.canRecruitPendingAlly(), isFalse,
        reason: '10 places déjà utilisées');
    controller.recruitPendingAlly();
    expect(container.read(gameControllerProvider)!.activePlayer.allies.length,
        10, reason: 'le recrutement est refusé');
  });

  test('objet : équipement avec échange automatique vers la réserve', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final Weapon bowcaster = CardConstants.weapons
        .firstWhere((Weapon w) => w.name == 'Bowcaster');
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 4,
      xp: 700,
      attack: 450,
      hp: 1100,
      maxHp: 1100,
    );
    final Position target = _neighborWith(planet, <Player>[player], weapon: bowcaster);

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);

    final MoveResult result =
        controller.moveActivePlayerTo(target.x, target.y);
    expect(result, MoveResult.itemEncounter);
    expect(controller.pendingWeaponOffer?.name, 'Bowcaster');

    controller.equipPendingWeapon();
    final GameState after = container.read(gameControllerProvider)!;
    expect(after.activePlayer.weapon?.name, 'Bowcaster');
    expect(after.activePlayer.storedWeapon, isNull,
        reason: 'aucune arme équipée avant → réserve vide');
    expect(after.activePlayer.totalAttack, 450 + 100);
  });

  test('rareté non autorisée : équipement refusé, réserve possible', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final Weapon mythic = CardConstants.weapons
        .firstWhere((Weapon w) => w.rarity == Rarity.mythique);
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
    );
    final Position target = _neighborWith(planet, <Player>[player], weapon: mythic);

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);
    controller.moveActivePlayerTo(target.x, target.y);

    expect(controller.equipPendingWeapon(), isFalse,
        reason: 'Mythique interdite au niveau 1');
    controller.storePendingWeapon();
    final GameState after = container.read(gameControllerProvider)!;
    expect(after.activePlayer.storedWeapon?.name, mythic.name);
    expect(controller.equipStoredWeapon(), isFalse,
        reason: 'toujours interdit au niveau 1');
  });
  test('réserve : échange entre arme équipée et arme en réserve', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final Weapon bowcaster = CardConstants.weapons
        .firstWhere((Weapon w) => w.name == 'Bowcaster');
    final Weapon sabre = CardConstants.weapons
        .firstWhere((Weapon w) => w.name == 'Sabre Laser de Luke');
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 5,
      xp: 1000,
      attack: 1200,
      hp: 2000,
      maxHp: 2000,
      weapon: bowcaster,
      storedWeapon: sabre,
    );

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);

    expect(controller.equipStoredWeapon(), isTrue);
    final GameState after = container.read(gameControllerProvider)!;
    expect(after.activePlayer.weapon?.name, 'Sabre Laser de Luke');
    expect(after.activePlayer.storedWeapon?.name, 'Bowcaster');
  });

  test('équipe pleine : défausse intégrée puis recrutement (Sprint 4.2)', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final List<Ally> fullTeam = List<Ally>.generate(
        10, (int i) => CardConstants.squads.first); // 10 × 1 PP = équipe pleine
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
      allies: fullTeam,
    );
    final Ally hera = CardConstants.healers
        .firstWhere((Ally a) => a.name == 'Hera Syndulla'); // Rebel, 2 PP
    final Position target = _neighborWith(planet, <Player>[player], ally: hera);

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);
    controller.moveActivePlayerTo(target.x, target.y);

    // Équipe pleine : le recrutement est bloqué...
    expect(controller.canRecruitPendingAlly(), isFalse);
    // ...la défausse de 2 alliés (2 places libérées) réactive le recrutement...
    controller.discardAlly(0);
    controller.discardAlly(0);
    expect(controller.canRecruitPendingAlly(), isTrue);

    controller.recruitPendingAlly();
    final GameState after = container.read(gameControllerProvider)!;
    expect(after.activePlayer.allies.length, 9,
        reason: '8 restants + Hera (2 PP)');
    expect(
      after.activePlayer.allies.any((Ally a) => a.name == 'Hera Syndulla'),
      isTrue,
    );
  });

  test('case soin : lancer le dé et appliquer le montant (plafonné)', () {
    final Planet planet = mapService.generateStartPlanet(PlanetType.hoth, seed: 42);
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 1,
      xp: 0,
      attack: 125,
      hp: 150,
      maxHp: 200,
    );
    final Position target = _neighborWith(planet, <Player>[player], healSite: true);

    final GameController controller = container.read(gameControllerProvider.notifier);
    controller.state = _stateWith(planet, <Player>[player]);

    final MoveResult result =
        controller.moveActivePlayerTo(target.x, target.y);
    expect(result, MoveResult.healEncounter);

    final GameState after = container.read(gameControllerProvider)!;
    final int roll = controller.lastHealRoll!;
    expect(roll, inInclusiveRange(1, 6));
    expect(controller.lastHealAmount,
        lessThanOrEqualTo(GameConstants.healForRoll(roll, maxHp: 200)),
        reason: 'soin plafonné au max PV');
    expect(
      after.activePlayer.hp,
      min(150 + GameConstants.healForRoll(roll, maxHp: 200), 200),
      reason: '150 PV + soin au dé (5-30 % des PV max), plafonné au max PV',
    );
    expect(after.currentPlanet.tileAt(target.x, target.y).healSite, isFalse,
        reason: 'la case de soin est consommée');
  });

  test('tank : bonus PV au total et dégâts divisés par 2', () {
    final Ally savage = CardConstants.tanks
        .firstWhere((Ally a) => a.name == 'Savage Opress'); // +500 PV
    final Ally malgus = CardConstants.tanks
        .firstWhere((Ally a) => a.name == 'Dark Malgus'); // dégâts ÷ 2
    final Player player = Player(
      id: 'p1',
      name: 'Luke',
      faction: Faction.rebel,
      position: const Position(0, 0),
      level: 1,
      xp: 0,
      attack: 125,
      hp: 200,
      maxHp: 200,
      allies: <Ally>[savage, malgus],
    );
    expect(player.tankHpBonus, 500, reason: 'Savage Opress +500 PV');
    expect(player.hasDamageDivider, isTrue, reason: 'Dark Malgus ÷ 2');
    expect(player.totalMaxHp, 700);
  });
}
