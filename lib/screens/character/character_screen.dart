import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/game_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/game_service.dart';
import '../../widgets/sub_screen_shell.dart';
import '../../widgets/card_image.dart';

/// Écran Personnage (CDC §11) : niveau, XP, ATK, PV, boss vaincus du
/// joueur actif.
class CharacterScreen extends ConsumerWidget {
  const CharacterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameState? state = ref.watch(gameControllerProvider);
    if (state == null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.mounted ? context.go('/') : null);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Player player = state.activePlayer;
    final int? nextLevelXp = GameConstants.xpRequiredForNextLevel(player.level);
    final int currentLevelXp =
        GameConstants.xpRequiredPerLevel[player.level - 1];

    return SubScreenShell(
      route: '/character',
      title: 'Personnage',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeaderCard(player: player, playerIndex: state.currentPlayerIndex),
          const SizedBox(height: 12),
          _StatRow(label: 'Niveau', value: '${player.level}'),
          _StatRow(label: 'XP', value: '${player.xp}'),
          if (nextLevelXp != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (player.xp - currentLevelXp) /
                          (nextLevelXp - currentLevelXp),
                      minHeight: 8,
                      color: AppColors.blue,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${player.xp - currentLevelXp} / '
                    '${nextLevelXp - currentLevelXp} XP vers le niveau ${player.level + 1}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else
            _StatRow(label: 'Progression', value: 'Niveau maximum atteint'),
          _StatRow(
              label: 'ATK',
              value:
                  '${player.totalAttack} (base ${player.attack}${player.weapon != null ? ' + arme ${player.weapon!.attackBonus}' : ''})'),
          _StatRow(
              label: 'PV',
              value:
                  '${player.hp} / ${player.totalMaxHp} (base ${player.maxHp}${player.armor != null ? ' + tenue ${player.armor!.hpBonus}' : ''})'),
          const SizedBox(height: 8),
          _BossCard(
              defeatedBosses: player.defeatedBosses
                  .map((boss) => boss.displayName)
                  .toList()),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Player player;
  final int playerIndex;

  const _HeaderCard({required this.player, required this.playerIndex});

  @override
  Widget build(BuildContext context) {
    final Color factionColor = AppColors.factionColor(player.faction);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CardImage(
              category: 'characters',
              id: cardImageId(player.name),
              size: 64,
              fallback: CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.playerTokenColor(playerIndex)
                    .withValues(alpha: 0.3),
                child: Text(
                  player.name.characters.first,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(player.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    player.faction.displayName,
                    style: TextStyle(color: factionColor),
                  ),
                  if (player.team != null)
                    Text(
                      player.team!.displayName,
                      style:
                          TextStyle(color: AppColors.teamColor(player.team!)),
                    ),
                ],
              ),
            ),
            Text('Niv. ${player.level}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: AppColors.gold)),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      ),
    );
  }
}

class _BossCard extends StatelessWidget {
  final List<String> defeatedBosses;

  const _BossCard({required this.defeatedBosses});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boss vaincus',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (defeatedBosses.isEmpty)
              Text(
                'Aucun boss vaincu pour le moment.\n'
                'Les boss apparaîtront à partir du Sprint 5.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final String bossName in defeatedBosses)
                    Chip(
                      avatar: const Icon(Icons.emoji_events,
                          size: 16, color: AppColors.gold),
                      label: Text(bossName),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
