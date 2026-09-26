
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart' show GameStatus;

import '../../core/theme/app_theme.dart';
import '../../core/constants/game_constants.dart';
import '../../core/constants/planet_constants.dart' show PlanetConstants;
import '../../models/boss.dart' show BossType;
import '../../models/game_state.dart';
import '../../models/monster.dart';
import '../../models/player.dart';
import '../../services/image_service.dart';
import '../../services/sound_service.dart';
import '../../services/combat_service.dart';
import '../../services/game_service.dart';
import '../../widgets/boss_icon.dart';
import '../../widgets/card_image.dart';
import '../../widgets/dice_widget.dart';

/// Écran Combat (CDC §15) :
///  - gauche : carte du joueur (initiales, niveau, ATK, PV) ;
///  - centre : dé animé, bouton « Lancer le dé », messages ;
///  - droite : carte du monstre (ou du joueur défenseur, Sprint 3 JvJ) ;
///  - messages « Critique ! », « Victoire ! », « +XP », dégâts subis ;
///  - retour automatique au plateau une fois le combat résolu.
class CombatScreen extends ConsumerStatefulWidget {
  const CombatScreen({super.key});

  @override
  ConsumerState<CombatScreen> createState() => _CombatScreenState();
}

class _CombatScreenState extends ConsumerState<CombatScreen> {
  bool _sfxPlayed = false;

  @override
  void initState() {
    super.initState();
    // Musique de combat EN BOUCLE (fix 19/09) : une piste pour les
    // combats contre les monstres, une pour les duels entre joueurs —
    // remplace l'ambiance de planète sur le canal musique ; au retour au
    // plateau, l'ambiance de la planète reprend (initState du board).
    // Les combats de BOSS conservent l'ambiance de la planète.
    final CombatSession? session = ref.read(combatControllerProvider);
    final String? track = session == null
        ? null
        : switch (session.kind) {
            CombatKind.monster => 'combats/monstre',
            CombatKind.player => 'combats/joueurs',
            CombatKind.boss => null,
          };
    if (track != null) {
      ref.read(soundControllerProvider).playScreenMusic(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CombatSession? session = ref.watch(combatControllerProvider);

    // Effets sonores de fin de combat (une seule fois par combat).
    if (session != null && session.finished && !_sfxPlayed) {
      _sfxPlayed = true;
      if (session.levelsGained > 0) {
        ref.read(soundControllerProvider).playSfx('niveau');
      } else if (session.victory && session.kind == CombatKind.boss) {
        ref.read(soundControllerProvider).playSfx('victoire_boss');
      } else if (session.victory) {
        ref.read(soundControllerProvider).playSfx('victoire_monstre');
      }
      if (session.playerEliminated) {
        ref.read(soundControllerProvider).playSfx('elimination');
      }
    }

    if (session == null) {
      // Garde-fou : aucun combat en cours → retour au plateau.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/board');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final GameState? game = ref.watch(gameControllerProvider);
    if (game == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Player active = game.activePlayer;
    final bool rolling = false; // le dé affiche directement le dernier jet.

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (session.kind) {
          CombatKind.monster => session.monster2 == null
              ? 'Combat — ${session.monster!.name}'
              : 'Combat — ${session.monster!.name} & '
                  '${session.monster2!.name}',
          CombatKind.boss => 'Boss — ${session.bossType!.displayName}',
          CombatKind.player => 'Combat — ${session.defenderName}',
        }),
        leading: const SizedBox.shrink(),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _FighterCard(
                      title: active.name,
                      subtitle: 'Niveau ${active.level}',
                      initials: active.name.characters.first,
                      color:
                          AppColors.playerTokenColor(game.currentPlayerIndex),
                      stats: <String, String>{
                        'ATK': '${session.playerAttackTotal}',
                        'PV': '${session.playerHp} / ${session.playerMaxHp}',
                        'XP': '${active.xp}',
                      },
                      footer: _XpGauge(level: active.level, xp: active.xp),
                      header: _FighterPhoto(
                          name: active.name,
                          color: AppColors.playerTokenColor(
                              game.currentPlayerIndex)),
                    )),
                    const SizedBox(width: 10),
                    _CenterPanel(
                      session: session,
                      rolling: rolling,
                      onAttack: () {
                        // Lancer de dé d'attaque (sfx/attaque).
                        ref.read(soundControllerProvider).playSfx('attaque');
                        ref
                            .read(combatControllerProvider.notifier)
                            .attack();
                      },
                      // Retour au plateau PAR CLIC (retours playtest : le
                      // retour automatique masquait le passage de niveau).
                      onReturn: () {
                        ref.read(combatControllerProvider.notifier).leave();
                        if (mounted) context.go('/board');
                      },
                      onEndGame: () {
                        ref.read(combatControllerProvider.notifier).leave();
                        if (mounted) context.go('/game-over');
                      },
                      gameFinished:
                          game.status == GameStatus.finished,
                      // Soutien « attaque ×dé » — usage unique (playtest).
                      hasAttackTimesDice: active.hasAttackTimesDice,
                      onAttackTimesDice: () {
                        ref.read(soundControllerProvider).playSfx('attaque');
                        ref
                            .read(combatControllerProvider.notifier)
                            .attack(useAttackTimesDice: true);
                      },
                      // Fuite possible contre un monstre ou un boss
                      // (GDD §10, Sprint 5) — pas en JvJ.
                      onFlee: session.kind != CombatKind.player
                          ? () =>
                              ref.read(combatControllerProvider.notifier).flee()
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: switch (session.kind) {
                      CombatKind.monster when session.monster2 != null =>
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _MonsterCard(
                                monster: session.monster!,
                                hpRemaining: session.monsterHpRemaining,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _MonsterCard(
                                monster: session.monster2!,
                                hpRemaining: session.monsterHpRemaining,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      CombatKind.monster => _MonsterCard(
                          monster: session.monster!,
                          hpRemaining: session.monsterHpRemaining,
                        ),
                      CombatKind.boss => _BossCard(session: session),
                      CombatKind.player => _FighterCard(
                          title: session.defenderName ?? '',
                          subtitle: 'Défenseur',
                          initials: (session.defenderName ?? '?')
                              .characters
                              .first,
                          color: AppColors.danger,
                          stats: <String, String>{
                            'ATK': '${session.defenderAttackTotal}',
                            'PV restants': '${session.defenderHpRemaining}',
                          },
                          header: _FighterPhoto(
                              name: session.defenderName ?? '',
                              color: AppColors.danger),
                        ),
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panneau central : dé animé, bouton « Lancer le dé », messages
// ---------------------------------------------------------------------------

class _CenterPanel extends StatelessWidget {
  final CombatSession session;
  final bool rolling;
  final VoidCallback onAttack;

  /// Soutien « attaque ×dé » disponible (usage unique — retours playtest).
  final bool hasAttackTimesDice;
  final VoidCallback? onAttackTimesDice;

  /// Fuite possible contre un monstre ou un boss (Sprint 5).
  final VoidCallback? onFlee;

  /// Retour au plateau une fois le combat résolu (par clic).
  final VoidCallback? onReturn;

  /// Aller à l'écran de fin de partie (partie terminée pendant ce combat).
  final VoidCallback? onEndGame;

  /// La partie est terminée (afficher l'annonce + bouton Game Over).
  final bool gameFinished;

  const _CenterPanel({
    required this.session,
    required this.rolling,
    required this.onAttack,
    this.hasAttackTimesDice = false,
    this.onAttackTimesDice,
    this.onFlee,
    this.onReturn,
    this.onEndGame,
    this.gameFinished = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool canAttack = !session.finished;

    return SizedBox(
      width: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DiceWidget(
            value: session.lastRoll ?? 1,
            rolling: rolling,
            size: 64,
          ),
          const SizedBox(height: 8),
          if (session.lastRoll != null)
            Text('Dé : ${session.lastRoll}',
                style: textTheme.titleMedium?.copyWith(color: AppColors.gold)),
          if (CombatService.isCritical(session.lastRoll ?? 0,
              critOn5: session.critOn5))
            Text('Critique !',
                style: textTheme.titleLarge?.copyWith(
                    color: AppColors.danger, fontWeight: FontWeight.w800)),
          if (session.attackTimesDiceUsed)
            Text('Attaque ×${session.lastRoll} !',
                style: textTheme.titleMedium?.copyWith(
                    color: AppColors.gold, fontWeight: FontWeight.w800)),
          if (session.lastDamage > 0)
            Text('-${session.lastDamage} PV',
                style: textTheme.titleMedium
                    ?.copyWith(color: AppColors.moveHighlight)),
          const SizedBox(height: 12),
          if (canAttack) ...<Widget>[
            FilledButton(
              onPressed: onAttack,
              child: const Text('Lancer le dé'),
            ),
            if (hasAttackTimesDice && onAttackTimesDice != null) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Attaque ×dé',
                    overflow: TextOverflow.ellipsis),
                onPressed: onAttackTimesDice,
              ),
            ],
            if (onFlee != null) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.directions_run),
                label: const Text('Fuir'),
                onPressed: onFlee,
              ),
            ],
          ] else ...[
            Text(
              session.fled
                  ? 'Vous fuyez !'
                  : session.victory
                      ? 'Victoire !'
                      : session.playerEliminated
                          ? 'Défaite…'
                          : 'Échange terminé',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                  color: AppColors.gold, fontWeight: FontWeight.w800),
            ),
            // Passage de niveau après le combat (retours playtest).
            if (session.levelsGained > 0)
              Text(
                '⬆ Niveau ${session.playerStartLevel + session.levelsGained} '
                'atteint !',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                    color: AppColors.moveHighlight,
                    fontWeight: FontWeight.w800),
              ),
            // Une carte « empêche la mort » a sauvé un combattant à 1 PV.
            if (session.deathPrevented)
              Text('🛡 Mort empêchée : survit à 1 PV !',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium
                      ?.copyWith(color: AppColors.moveHighlight)),
            if (session.xpGained > 0)
              Text('+${session.xpGained} XP',
                  style: textTheme.titleMedium
                      ?.copyWith(color: AppColors.moveHighlight)),
            // Récompenses de boss (retours playtest 19/09) : rappeler
            // ce que rapporte la victoire, en plus de l'XP de rang.
            if (session.victory && session.kind == CombatKind.boss)
              Text(
                '🎁 +${GameConstants.bossVictoryHeal} PV rendus · '
                '+${GameConstants.bossTeamCapacityBonus} places d’équipe !',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium
                    ?.copyWith(color: AppColors.gold, fontWeight: FontWeight.w700),
              ),
            if (session.targetEliminated)
              Text('Élimination !',
                  style:
                      textTheme.titleMedium?.copyWith(color: AppColors.danger)),
            if (session.damageTaken > 0)
              Text('Dégâts subis : -${session.damageTaken} PV',
                  textAlign: TextAlign.center,
                  style:
                      textTheme.bodyLarge?.copyWith(color: AppColors.danger)),
            if (session.playerEliminated)
              Text('Vous êtes éliminé…',
                  textAlign: TextAlign.center,
                  style:
                      textTheme.titleMedium?.copyWith(color: AppColors.danger)),
            // La partie vient de se terminer pendant ce combat : l'annoncer
            // clairement et proposer d'aller DIRECTEMENT au Game Over
            // (retours playtest : aucune visibilité sur la fin).
            if (gameFinished) ...<Widget>[
              const SizedBox(height: 12),
              Text('🏆 La partie est terminée !',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                      color: AppColors.gold, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.emoji_events),
                label: const Text('Voir la fin de partie'),
                onPressed: onEndGame,
              ),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: const Text('Retour au plateau'),
                onPressed: onReturn,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte du monstre (CDC §15 : image placeholder, PV, ATK, XP)
// ---------------------------------------------------------------------------

class _MonsterCard extends StatelessWidget {
  /// Monstre à afficher + PV du pool partagé (doubles monstres : les deux
  /// cartes montrent le même pool combiné — retours playtest 20/09).
  final Monster monster;
  final int hpRemaining;

  /// Version resserrée pour l'affichage de DEUX monstres côte à côte.
  final bool compact;

  const _MonsterCard({
    required this.monster,
    required this.hpRemaining,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Monster monster = this.monster;
    final double imageSize = compact ? 48 : 72;
    final IconData icon = switch (monster.level) {
      1 => Icons.pest_control,
      2 => Icons.pest_control_rodent,
      3 => Icons.cruelty_free,
      4 => Icons.smart_toy,
      _ => Icons.animation,
    };

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CardImage(
              category: 'monsters',
              id: cardImageId(monster.name),
              size: imageSize,
              fallback: CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.danger.withValues(alpha: 0.25),
                child: Icon(icon, size: 34, color: AppColors.danger),
              ),
            ),
            const SizedBox(height: 8),
            Text(monster.name,
                textAlign: TextAlign.center, style: textTheme.titleMedium),
            Text('Monstre niveau ${monster.level}',
                style: textTheme.bodyMedium),
            const SizedBox(height: 10),
            _Stat(
                label: 'PV',
                value: '$hpRemaining / ${monster.hp}'),
            _Stat(label: 'ATK', value: '${monster.attack}'),
            if (!compact) _Stat(label: 'XP', value: '+${monster.xpReward}'),
          ],
        ),
      ),
    );
  }
}

/// Carte du boss (Sprint 5 — GDD §12, CDC §16) : 10 000 PV, attaque
/// aléatoire 250–500, XP selon le rang du vainqueur.
class _BossCard extends StatelessWidget {
  final CombatSession session;

  const _BossCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final BossType type = session.bossType!;
    final IconData icon = bossIcon(type);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CardImage(
              category: 'bosses',
              id: bossImageId(type),
              size: 72,
              fallback: CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.danger.withValues(alpha: 0.25),
                child: Icon(icon, size: 34, color: AppColors.danger),
              ),
            ),
            const SizedBox(height: 8),
            Text(type.displayName,
                textAlign: TextAlign.center, style: textTheme.titleMedium),
            Text('Boss · ${PlanetConstants.bossFactionByType[type]?.displayName ?? ''}',
                style: textTheme.bodyMedium),
            const SizedBox(height: 10),
            _Stat(
                label: 'PV',
                value:
                    '${session.monsterHpRemaining} / ${GameConstants.bossHp}'),
            _Stat(
                label: 'ATK',
                value:
                    '${GameConstants.bossAttackMin}–${GameConstants.bossAttackMax}'),
            const _Stat(label: 'XP', value: '400 / 300 / 200 / 100'),
          ],
        ),
      ),
    );
  }
}

/// Carte de combattant (joueur actif ou défenseur JvJ).
class _FighterCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String initials;
  final Color color;
  final Map<String, String> stats;

  /// Section optionnelle sous les stats (jauge d'XP du joueur — playtest).
  final Widget? footer;

  /// Section optionnelle au-dessus des stats : photo du combattant
  /// (Sprint 6 — carte du personnage pendant le combat).
  final Widget? header;

  const _FighterCard({
    required this.title,
    required this.subtitle,
    required this.initials,
    required this.color,
    required this.stats,
    this.footer,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (header != null) header!,
            if (header == null) ...<Widget>[
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withValues(alpha: 0.3),
                child: Text(initials,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              const SizedBox(height: 8),
            ],
            Text(title,
                textAlign: TextAlign.center, style: textTheme.titleMedium),
            Text(subtitle, style: textTheme.bodyMedium),
            const SizedBox(height: 10),
            for (final MapEntry<String, String> entry in stats.entries)
              _Stat(label: entry.key, value: entry.value),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

/// Photo du combattant (carte personnage si l'image est déposée),
/// sinon l'avatar à initiales (Sprint 6).
class _FighterPhoto extends ConsumerWidget {
  final String name;
  final Color color;

  const _FighterPhoto({required this.name, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ImageProvider? photo = ref
        .watch(imageServiceProvider)
        .providerFor('characters', cardImageId(name));
    if (photo == null) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: color.withValues(alpha: 0.3),
        child: Text(name.characters.first,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      );
    }
    return SizedBox(
      width: 96,
      height: 96,
      child: ClipOval(
        child: Image(image: photo,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) =>
                Icon(Icons.person, size: 44, color: color)),
      ),
    );
  }
}

/// Jauge de progression vers le niveau suivant (retours playtest v3).
class _XpGauge extends StatelessWidget {
  final int level;
  final int xp;

  const _XpGauge({required this.level, required this.xp});

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int? nextXp = GameConstants.xpRequiredForNextLevel(level);
    final int prevXp = GameConstants.xpRequiredPerLevel[level - 1];
    final double progress = nextXp == null
        ? 1.0
        : ((xp - prevXp) / (nextXp - prevXp)).clamp(0.0, 1.0);

    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            color: AppColors.moveHighlight,
            backgroundColor: Colors.white10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          nextXp == null
              ? 'Niveau maximum atteint'
              : '$xp / $nextXp XP vers le niveau ${level + 1}',
          textAlign: TextAlign.center,
          style:
              textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
