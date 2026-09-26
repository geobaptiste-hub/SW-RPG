
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/planet_constants.dart' show PlanetConstants;
import '../../core/utils/slug.dart';
import '../../services/image_service.dart';
import '../../models/boss.dart' show BossType;
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/game_service.dart';
import '../../widgets/sub_screen_shell.dart';

/// Écran Joueurs (CDC §14) : pour tous les joueurs — niveau, XP, ATK, PV.
class PlayersScreen extends ConsumerWidget {
  const PlayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameState? state = ref.watch(gameControllerProvider);
    if (state == null) {
      // Garde-fou : aucune partie en cours → retour à l'accueil.
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.mounted ? context.go('/') : null);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SubScreenShell(
      route: '/players',
      title: 'Joueurs',
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: state.players.length,
        itemBuilder: (BuildContext context, int index) {
          return _PlayerCard(
            player: state.players[index],
            playerIndex: index,
            isActive: index == state.currentPlayerIndex,
          );
        },
      ),
    );
  }
}

class _PlayerCard extends ConsumerWidget {
  final Player player;
  final int playerIndex;
  final bool isActive;

  const _PlayerCard({
    required this.player,
    required this.playerIndex,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color tokenColor = AppColors.playerTokenColor(playerIndex);
    final ImageProvider? avatarImage = ref
        .watch(imageServiceProvider)
        .providerFor('characters', slugify(player.name));

    return Card(
      shape: isActive
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.gold, width: 1.6),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: tokenColor.withValues(alpha: 0.3),
              foregroundImage: avatarImage,
              child: Text(
                player.name.characters.first,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: tokenColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          player.eliminated
                              ? '${player.name} (éliminé)'
                              : player.name,
                          style: textTheme.titleMedium?.copyWith(
                            color: player.eliminated
                                ? AppColors.textSecondary
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        player.faction.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.factionColor(player.faction),
                        ),
                      ),
                      if (player.team != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          player.team!.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.teamColor(player.team!),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _StatChip(label: 'Niv. ${player.level}'),
                      _StatChip(label: '${player.xp} XP'),
                      _StatChip(label: '${player.totalAttack} ATK'),
                      _StatChip(label: '${player.hp}/${player.totalMaxHp} PV'),
                      // Élimination et boss vaincus (retours playtest v3).
                      if (player.eliminated)
                        const _StatChip(
                          label: '💀 Éliminé',
                          color: AppColors.danger,
                        ),
    for (final BossType boss in player.defeatedBosses)
      _StatChip(
        label: '🏆 ${boss.displayName} '
            '(${PlanetConstants.bossFactionByType[boss]!.displayName})',
        color: AppColors.gold,
      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.play_arrow, color: AppColors.gold),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pastille de statistique (CDC §14).
class _StatChip extends StatelessWidget {
  final String label;

  /// Couleur du texte (défaut : texte principal).
  final Color? color;

  const _StatChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: color?.withValues(alpha: 0.4) ?? Colors.white10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: color ?? AppColors.textPrimary,
            ),
      ),
    );
  }
}
