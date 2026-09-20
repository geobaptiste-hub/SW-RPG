import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/enums.dart' show GameStatus;
import '../core/constants/game_constants.dart';
import '../models/boss.dart';
import '../models/game_state.dart';
import '../models/monster.dart';
import '../models/player.dart';
import '../models/tile.dart';
import 'game_service.dart';

/// Service de combat (Architecture v1.0 — CombatService), Sprint 3.
///
/// Règles actées (07/09/2026) :
///  - attaque : dé 1 à 6, un 6 est un critique → dégâts doublés (ATK × 2) ;
///  - vs monstre (GDD §11) : attaques successives jusqu'à 0 PV, puis le
///    joueur subit ATK du monstre × nombre d'attaques, en une fois ;
///  - entre joueurs (GDD §13) : un échange par entrée de case, le
///    défenseur ne peut pas critiquer, 0 PV = élimination (+500 XP) ;
///  - fuite (GDD §10) : le pion entre dans la case sans combattre, le
///    monstre reste (nouvelle rencontre en cas de retour).
class CombatService {
  CombatService({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Lancer de dé d'attaque : 1 à 6 (critique sur 6 — GDD §13).
  int rollAttackDice() => _random.nextInt(6) + 1;

  /// Attaque de boss : 250 à 500 par pas de 10 (CDC §16).
  int rollBossAttack() {
    const int min = GameConstants.bossAttackMin;
    const int max = GameConstants.bossAttackMax;
    const int step = GameConstants.bossAttackStep;
    final int steps = ((max - min) ~/ step) + 1;
    return min + _random.nextInt(steps) * step;
  }

  /// Un 6 au dé est un coup critique ; avec le soutien « critOn5 », le 5
  /// aussi (retours playtest 10/09/2026).
  static bool isCritical(int roll, {bool critOn5 = false}) =>
      roll == 6 || (critOn5 && roll == 5);

  /// Dégâts d'une attaque : ATK totale, doublés si critique
  /// (décision du 07/09/2026).
  static int attackDamage({
    required int attackTotal,
    required int roll,
    bool critOn5 = false,
  }) =>
      isCritical(roll, critOn5: critOn5) ? attackTotal * 2 : attackTotal;
}

/// Provider du service de combat (Random injectable pour les tests).
final combatServiceProvider = Provider<CombatService>((ref) => CombatService());

/// Type de combat en cours.
enum CombatKind { monster, player, boss }

/// État immuable d'un combat en cours (écran Combat — CDC §15).
class CombatSession {
  final CombatKind kind;

  /// vs monstre : la case de la carte rencontrée.
  final Position? targetTile;
  final Monster? monster;
  final int monsterHpRemaining;

  /// vs joueur : index du défenseur et ses PV restants.
  final int? defenderIndex;
  final String? defenderName;
  final int defenderHpRemaining;

  final int playerAttackTotal;
  final int playerHp;
  final int playerMaxHp;

  /// Niveau du joueur actif au début du combat : sert à afficher les
  /// niveaux gagnés à la fin (retours playtest 10/09/2026).
  final int playerStartLevel;

  /// Soutien « critOn5 » du porteur (critique aussi sur 5).
  final bool critOn5;

  final int attacksUsed;
  final int? lastRoll;
  final int lastDamage;

  /// Combat terminé (victoire sur le monstre, ou échange JvJ résolu).
  final bool finished;
  final bool victory;

  /// Le joueur a fui en plein combat (monstre toujours sur sa case).
  final bool fled;

  /// Type du boss combattu (combat de boss — Sprint 5).
  final BossType? bossType;

  /// ATK totale du défenseur JvJ (riposte sans critique — GDD §13).
  final int defenderAttackTotal;

  /// Une carte soutien « empêche la mort » a sauvé un combattant à 1 PV
  /// (retours playtest — consommée).
  final bool deathPrevented;

  /// L'attaque « ×dé » (soutien à usage unique) a été utilisée.
  final bool attackTimesDiceUsed;

  /// Niveaux gagnés par le joueur actif pendant le combat.
  final int levelsGained;

  /// Résultats appliqués à la partie.
  final bool targetEliminated;
  final bool playerEliminated;
  final int xpGained;
  final int damageTaken;

  const CombatSession({
    required this.kind,
    required this.playerAttackTotal,
    required this.playerHp,
    required this.playerMaxHp,
    this.playerStartLevel = 1,
    this.critOn5 = false,
    this.targetTile,
    this.monster,
    this.monsterHpRemaining = 0,
    this.defenderIndex,
    this.defenderName,
    this.defenderHpRemaining = 0,
    this.defenderAttackTotal = 0,
    this.attacksUsed = 0,
    this.lastRoll,
    this.lastDamage = 0,
    this.finished = false,
    this.victory = false,
    this.fled = false,
    this.bossType,
    this.deathPrevented = false,
    this.attackTimesDiceUsed = false,
    this.levelsGained = 0,
    this.targetEliminated = false,
    this.playerEliminated = false,
    this.xpGained = 0,
    this.damageTaken = 0,
  });

  CombatSession copyWith({
    int? monsterHpRemaining,
    int? defenderHpRemaining,
    int? attacksUsed,
    int? lastRoll,
    int? lastDamage,
    bool? finished,
    bool? victory,
    bool? fled,
    bool? targetEliminated,
    bool? playerEliminated,
    int? xpGained,
    int? damageTaken,
    int? playerHp,
    bool? deathPrevented,
    bool? attackTimesDiceUsed,
    int? levelsGained,
  }) {
    return CombatSession(
      kind: kind,
      targetTile: targetTile,
      monster: monster,
      monsterHpRemaining: monsterHpRemaining ?? this.monsterHpRemaining,
      defenderIndex: defenderIndex,
      defenderName: defenderName,
      defenderHpRemaining: defenderHpRemaining ?? this.defenderHpRemaining,
      playerAttackTotal: playerAttackTotal,
      playerHp: playerHp ?? this.playerHp,
      playerMaxHp: playerMaxHp,
      playerStartLevel: playerStartLevel,
      critOn5: critOn5,
      defenderAttackTotal: defenderAttackTotal,
      attacksUsed: attacksUsed ?? this.attacksUsed,
      lastRoll: lastRoll ?? this.lastRoll,
      lastDamage: lastDamage ?? this.lastDamage,
      finished: finished ?? this.finished,
      victory: victory ?? this.victory,
      fled: fled ?? this.fled,
      bossType: bossType ?? bossType,
      deathPrevented: deathPrevented ?? this.deathPrevented,
      attackTimesDiceUsed: attackTimesDiceUsed ?? this.attackTimesDiceUsed,
      levelsGained: levelsGained ?? this.levelsGained,
      targetEliminated: targetEliminated ?? this.targetEliminated,
      playerEliminated: playerEliminated ?? this.playerEliminated,
      xpGained: xpGained ?? this.xpGained,
      damageTaken: damageTaken ?? this.damageTaken,
    );
  }
}

/// Contrôleur de combat : session courante, attaques, application des
/// résultats à la partie via le GameController.
final combatControllerProvider =
    NotifierProvider<CombatController, CombatSession?>(CombatController.new);

class CombatController extends Notifier<CombatSession?> {
  @override
  CombatSession? build() => null;

  CombatService get _combat => ref.read(combatServiceProvider);
  GameController get _game => ref.read(gameControllerProvider.notifier);

  /// Démarre un combat contre le monstre présent sur la case [tile].
  void startMonsterCombat(Position tile) {
    final GameState? game = ref.read(gameControllerProvider);
    if (game == null) return;
    final Monster? monster = game.currentPlanet.tileAt(tile.x, tile.y).monster;
    if (monster == null) return;
    final Player active = game.activePlayer;
    state = CombatSession(
      kind: CombatKind.monster,
      targetTile: tile,
      monster: monster,
      monsterHpRemaining: monster.hp,
      playerAttackTotal: active.totalAttack,
      playerHp: active.hp,
      playerMaxHp: active.totalMaxHp,
      playerStartLevel: active.level,
      critOn5: active.hasCritOn5,
    );
  }

  /// Démarre un combat contre le boss [boss] (GDD §12, Sprint 5) :
  /// le champ `monsterHpRemaining` est réutilisé pour les PV du boss.
  void startBossCombat(Boss boss) {
    final GameState? game = ref.read(gameControllerProvider);
    if (game == null) return;
    final Player active = game.activePlayer;
    state = CombatSession(
      kind: CombatKind.boss,
      bossType: boss.type,
      monsterHpRemaining: boss.hp,
      playerAttackTotal: active.totalAttack,
      playerHp: active.hp,
      playerMaxHp: active.totalMaxHp,
      playerStartLevel: active.level,
      critOn5: active.hasCritOn5,
    );
  }

  /// Démarre un échange contre le joueur [defenderIndex] (GDD §13).
  void startPlayerCombat(int defenderIndex) {
    final GameState? game = ref.read(gameControllerProvider);
    if (game == null) return;
    final Player defender = game.players[defenderIndex];
    final Player active = game.activePlayer;
    state = CombatSession(
      kind: CombatKind.player,
      defenderIndex: defenderIndex,
      defenderName: defender.name,
      defenderHpRemaining: defender.hp,
      defenderAttackTotal: defender.totalAttack,
      playerAttackTotal: active.totalAttack,
      playerHp: active.hp,
      playerMaxHp: active.totalMaxHp,
      playerStartLevel: active.level,
      critOn5: active.hasCritOn5,
    );
  }

  /// Résout une attaque du joueur actif. [useAttackTimesDice] : soutien
  /// « une seule fois, multipliez l'attaque par le chiffre du dé » — les
  /// dégâts valent ATK × face, sans critique cumulé, carte consommée.
  void attack({bool useAttackTimesDice = false}) {
    final CombatSession? session = state;
    if (session == null || session.finished) return;
    final GameState game = ref.read(gameControllerProvider)!;
    if (game.status != GameStatus.inProgress) return;

    final int roll = _combat.rollAttackDice();
    // Garde : la carte doit encore être dans l'équipe (anti double-tap).
    final bool timesDice = useAttackTimesDice && game.activePlayer.hasAttackTimesDice;
    final int damage;
    if (timesDice) {
      damage = session.playerAttackTotal * roll;
    } else {
      damage = CombatService.attackDamage(
        attackTotal: session.playerAttackTotal,
        roll: roll,
        critOn5: session.critOn5,
      );
    }
    // La carte ×dé est consommée quel que soit le résultat (usage unique).
    if (timesDice) _game.consumeAttackTimesDice();

    if (session.kind == CombatKind.monster) {
      final int hp = session.monsterHpRemaining - damage;
      final int attacks = session.attacksUsed + 1;

      int playerHp = session.playerHp;
      bool playerDead = false;
      int counter = 0;
      if (hp > 0) {
        // Sprint 4.1 : le monstre riposte après chaque attaque. Retours
        // playtest : dégâts selon le niveau puis ÷ 2 si un tank « dégâts
        // divisés » est dans l'équipe.
        counter = GameConstants.scaleIncomingDamage(
          session.monster!.attack,
          level: game.activePlayer.level,
          maxHp: game.activePlayer.totalMaxHp,
        );
        if (game.activePlayer.hasDamageDivider) {
          counter = (counter / 2).ceil();
        }
        playerHp = playerHp - counter;
        if (playerHp <= 0) {
          playerHp = 0;
          playerDead = true;
        }
      }

      if (hp <= 0) {
        // Victoire (GDD §11) : +XP, retrait du monstre, soins des healers.
        final MonsterVictoryOutcome outcome = _game.applyMonsterVictory(
          tile: session.targetTile!,
          xp: session.monster!.xpReward,
          playerHp: playerHp,
        );
        final int levelAfter =
            ref.read(gameControllerProvider)!.activePlayer.level;
        state = session.copyWith(
          monsterHpRemaining: 0,
          attacksUsed: attacks,
          lastRoll: roll,
          lastDamage: damage,
          attackTimesDiceUsed: timesDice,
          damageTaken: session.damageTaken + counter,
          finished: true,
          victory: true,
          xpGained: outcome.xpGained,
          playerEliminated: outcome.playerEliminated,
          playerHp: outcome.playerHp,
          levelsGained: levelAfter - session.playerStartLevel,
        );
        return;
      }

      if (playerDead) {
        // Soutien « empêche la mort » : survit à 1 PV, la carte est
        // consommée et le combat continue (retours playtest).
        if (_game.consumePreventDeath(game.currentPlayerIndex)) {
          state = session.copyWith(
            monsterHpRemaining: hp,
            attacksUsed: attacks,
            lastRoll: roll,
            lastDamage: damage,
            attackTimesDiceUsed: timesDice,
            damageTaken: session.damageTaken + counter,
            playerHp: 1,
            deathPrevented: true,
          );
          return;
        }
        // Défaite : le joueur est éliminé, le monstre reste sur sa case.
        _game.applyPlayerDefeat();
        state = session.copyWith(
          monsterHpRemaining: hp,
          attacksUsed: attacks,
          lastRoll: roll,
          lastDamage: damage,
          attackTimesDiceUsed: timesDice,
          damageTaken: session.damageTaken + counter,
          playerHp: 0,
          finished: true,
          victory: false,
          playerEliminated: true,
        );
        return;
      }

      state = session.copyWith(
        monsterHpRemaining: hp,
        attacksUsed: attacks,
        lastRoll: roll,
        lastDamage: damage,
        attackTimesDiceUsed: useAttackTimesDice,
        damageTaken: session.damageTaken + counter,
        playerHp: playerHp,
      );
      return;
    }

    // Boss (GDD §12, CDC §16) : riposte 250–500 (par pas de 10) après
    // chaque attaque non létale, ÷ 2 si un tank « dégâts divisés » est
    // dans l'équipe ; victoire = XP de rang puis le boss prend la fuite.
    if (session.kind == CombatKind.boss) {
      final int hp = session.monsterHpRemaining - damage;
      final int attacks = session.attacksUsed + 1;

      int playerHp = session.playerHp;
      bool playerDead = false;
      int counter = 0;
      if (hp > 0) {
        counter = GameConstants.scaleIncomingDamage(
          _combat.rollBossAttack(),
          level: game.activePlayer.level,
          maxHp: game.activePlayer.totalMaxHp,
        );
        if (game.activePlayer.hasDamageDivider) {
          counter = (counter / 2).ceil();
        }
        playerHp = playerHp - counter;
        if (playerHp <= 0) {
          playerHp = 0;
          playerDead = true;
        }
      }

      if (hp <= 0) {
        // Victoire (GDD §12) : XP selon le rang du vainqueur, puis le boss
        // fuit (ou meurt définitivement si tous les joueurs l'ont vaincu).
        final MonsterVictoryOutcome outcome = _game.applyBossVictory(
          type: session.bossType!,
          playerHp: playerHp,
        );
        final int levelAfter =
            ref.read(gameControllerProvider)!.activePlayer.level;
        state = session.copyWith(
          monsterHpRemaining: 0,
          attacksUsed: attacks,
          lastRoll: roll,
          lastDamage: damage,
          attackTimesDiceUsed: timesDice,
          damageTaken: session.damageTaken + counter,
          finished: true,
          victory: true,
          xpGained: outcome.xpGained,
          playerEliminated: outcome.playerEliminated,
          playerHp: outcome.playerHp,
          levelsGained: levelAfter - session.playerStartLevel,
        );
        return;
      }

      if (playerDead) {
        // Soutien « empêche la mort » : survit à 1 PV (retours playtest).
        if (_game.consumePreventDeath(game.currentPlayerIndex)) {
          state = session.copyWith(
            monsterHpRemaining: hp,
            attacksUsed: attacks,
            lastRoll: roll,
            lastDamage: damage,
            attackTimesDiceUsed: timesDice,
            damageTaken: session.damageTaken + counter,
            playerHp: 1,
            deathPrevented: true,
          );
          return;
        }
        // Défaite : le joueur est éliminé, le boss reste en place.
        _game.applyPlayerDefeat();
        state = session.copyWith(
          monsterHpRemaining: hp,
          attacksUsed: attacks,
          lastRoll: roll,
          lastDamage: damage,
          attackTimesDiceUsed: timesDice,
          damageTaken: session.damageTaken + counter,
          playerHp: 0,
          finished: true,
          victory: false,
          playerEliminated: true,
        );
        return;
      }

      state = session.copyWith(
        monsterHpRemaining: hp,
        attacksUsed: attacks,
        lastRoll: roll,
        lastDamage: damage,
        attackTimesDiceUsed: useAttackTimesDice,
        damageTaken: session.damageTaken + counter,
        playerHp: playerHp,
      );
      return;
    }

    // JvJ (GDD §13) : un ÉCHANGE — l'attaquant tire (critique possible),
    // puis le défenseur riposte sans pouvoir critiquer. Fix playtest : la
    // riposte du défenseur n'était pas appliquée, l'attaquant ne subissait
    // jamais de dégâts. Le JvJ reste létal (pas de température de niveau).
    final int hp = session.defenderHpRemaining - damage;
    final bool defenderDown = hp <= 0;
    final bool defenderSaved =
        defenderDown && _game.consumePreventDeath(session.defenderIndex!);
    final bool eliminated = defenderDown && !defenderSaved;

    int xp = 0;
    int defenderXp = 0;
    if (eliminated) {
      xp = GameConstants.playerKillXpReward +
          (game.activePlayer.hasXpBonusSupport
              ? GameConstants.supportBonusXp
              : 0);
    }

    // Riposte du défenseur : ATK totale, sans critique (GDD §13).
    int attackerHp = session.playerHp;
    int counter = 0;
    bool attackerEliminated = false;
    bool deathPrevented = defenderSaved;
    if (!eliminated) {
      counter = session.defenderAttackTotal;
      attackerHp = attackerHp - counter;
      if (attackerHp <= 0) {
        attackerHp = 0;
        if (_game.consumePreventDeath(game.currentPlayerIndex)) {
          attackerHp = 1;
          deathPrevented = true;
        } else {
          attackerEliminated = true;
          defenderXp = GameConstants.playerKillXpReward +
              (game.players[session.defenderIndex!].hasXpBonusSupport
                  ? GameConstants.supportBonusXp
                  : 0);
        }
      }
    }

    _game.applyPlayerCombatResult(
      defenderIndex: session.defenderIndex!,
      defenderHp: defenderDown ? (defenderSaved ? 1 : 0) : max(hp, 0),
      defenderEliminated: eliminated,
      attackerXp: xp,
      attackerHp: attackerHp,
      attackerEliminated: attackerEliminated,
      defenderXp: defenderXp,
    );
    final int levelAfter =
        ref.read(gameControllerProvider)!.activePlayer.level;
    state = session.copyWith(
      defenderHpRemaining: defenderDown ? (defenderSaved ? 1 : 0) : max(hp, 0),
      lastRoll: roll,
      lastDamage: damage,
      attackTimesDiceUsed: useAttackTimesDice,
      damageTaken: session.damageTaken + counter,
      finished: true,
      victory: eliminated,
      targetEliminated: eliminated,
      playerHp: attackerHp,
      playerEliminated: attackerEliminated,
      xpGained: xp,
      deathPrevented: deathPrevented,
      levelsGained: levelAfter - session.playerStartLevel,
    );
  }

  /// Fuite en plein combat (monstre ou boss, GDD §10) : l'adversaire reste
  /// sur sa case, les dégâts déjà subis sont conservés, aucune XP.
  void flee() {
    final CombatSession? session = state;
    if (session == null || session.finished) return;
    if (session.kind != CombatKind.monster &&
        session.kind != CombatKind.boss) {
      return;
    }
    _game.applyPlayerCombatHp(session.playerHp);
    state = session.copyWith(finished: true, victory: false, fled: true);
  }

  /// Quitte l'écran de combat (session close).
  void leave() => state = null;
}
