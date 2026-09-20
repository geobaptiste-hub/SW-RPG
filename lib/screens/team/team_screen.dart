import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart' show AllyType;
import '../../core/constants/game_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ally.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/game_service.dart';
import '../../widgets/sub_screen_shell.dart';
import '../../widgets/card_image.dart';

/// Écran Équipe (CDC §12, refonte playtest Sprint 6) : les alliés en
/// COLONNES côte à côte (carte en grand + textes), la RÉSERVE en dernière
/// colonne à droite. Capacité maximale : 10 places (le personnage
/// principal n'en consomme aucune — GDD §8).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameState? state = ref.watch(gameControllerProvider);
    if (state == null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.mounted ? context.go('/') : null);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final GameController controller = ref.read(gameControllerProvider.notifier);
    final Player active = state.activePlayer;
    final int usedSlots = active.usedTeamSlots;

    return SubScreenShell(
      route: '/team',
      title: 'Équipe',
      body: Column(
        children: <Widget>[
          // Places utilisées (pleine largeur).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text('Places d\u2019équipe',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('$usedSlots / ${active.teamCapacity}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: usedSlots / active.teamCapacity,
                        minHeight: 8,
                        color: AppColors.blue,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Le personnage principal ne consomme aucune place '
                      '(GDD §8). Les alliés occupent des places selon leur '
                      'rareté et leur rôle.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Bonus d'équipe (pleine largeur).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Bonus d\u2019équipe',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                        'Escouades : +${active.squadAttackBonus} ATK · '
                        'Nukers : +${active.nukerAttackBonus} ATK'),
                    Text('Tanks : +${active.tankHpBonus} PV max'),
                    if (active.specialAttackBonus > 0 ||
                        active.specialHpBonus > 0)
                      Text(
                          'Spéciales : +${active.specialAttackBonus} ATK · '
                          '+${active.specialHpBonus} PV max'),
                    Text(
                        'Healers : +${active.healerAfterCombatHeal} PV '
                        'après chaque victoire'),
                    if (active.hasDamageDivider)
                      const Text('Dégâts subis divisés par 2'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Colonnes : un allié par colonne, la RÉSERVE en dernière position
          // (défilement horizontal si l'équipe dépasse la largeur).
          Expanded(
            child: LayoutBuilder(
              builder:
                  (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    height: constraints.maxHeight - 12,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (active.allies.isEmpty)
                          const SizedBox(
                            width: 300,
                            child: _EmptyTeamColumn(),
                          ),
                        // Escouades regroupées (Sprint 4.3) : « Padawan ×2 »
                        // avec le bonus cumulé de la formule du GDD.
                        for (final MapEntry<String, List<int>> group
                            in _squadGroups(active).entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: SizedBox(
                              width: 210,
                              child: _AllyColumnCard(
                                ally: active.allies[group.value.first],
                                countLabel: '×${group.value.length}',
                                // La mise en réserve ÉCHANGE avec l'allié
                                // stocké (playtest).
                                onStore: () =>
                                    controller.storeTeamAlly(group.value.first),
                                onDiscard: () => _confirmDiscard(
                                    context, controller, group.value.first),
                              ),
                            ),
                          ),
                        for (final int index in _nonSquadIndexes(active))
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: SizedBox(
                              width: 210,
                              child: _AllyColumnCard(
                                ally: active.allies[index],
                                onHeal: active.allies[index].healInstant !=
                                            null &&
                                        active.hp < active.totalMaxHp
                                    ? () => controller.useHealerHeal(index)
                                    : null,
                                healAmount: active.allies[index].healInstant,
                                onStore: () => controller.storeTeamAlly(index),
                                onDiscard: () =>
                                    _confirmDiscard(context, controller, index),
                              ),
                            ),
                          ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 210,
                          child: _ReserveColumnCard(
                            storedAlly: active.storedAlly,
                            rarityAllowed: active.storedAlly != null &&
                                GameController.rarityAllowedForLevel(
                                    active.storedAlly!.rarity, active.level),
                            canRecruit: active.storedAlly != null &&
                                active.canRecruit(
                                    active.storedAlly!.teamCost) &&
                                GameController.rarityAllowedForLevel(
                                    active.storedAlly!.rarity, active.level),
                            onRecruit: () => controller.recruitStoredAlly(),
                            onDiscard: () =>
                                _confirmDiscardStored(context, controller),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Confirmation avant défausse définitive d'un allié de l'équipe.
  Future<void> _confirmDiscard(
      BuildContext context, GameController controller, int index) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Défausser cet allié ?'),
        content: const Text(
            'L\u2019allié sera retiré définitivement de l\u2019équipe '
            '(CDC §12 — possibilité de défausse).'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Défausser'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.discardAlly(index);
    }
  }

  /// Confirmation avant défausse de l'allié en réserve.
  Future<void> _confirmDiscardStored(
      BuildContext context, GameController controller) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Défausser cet allié ?'),
        content: const Text(
            'L\u2019allié en réserve sera détruit définitivement '
            '(la défausse est irréversible).'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Défausser'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.discardStoredAlly();
    }
  }
}

/// Colonne d'un allié de l'équipe : carte en grand, identité, effet,
/// coût et actions en bas.
class _AllyColumnCard extends StatelessWidget {
  final Ally ally;
  final VoidCallback onDiscard;

  /// Mise en réserve (échange avec l'allié stocké s'il y en a un).
  final VoidCallback onStore;

  /// Charge de soin du healer : bouton actif si non null (retours
  /// playtest — soigner quand on veut depuis l'équipe).
  final VoidCallback? onHeal;
  final int? healAmount;

  /// Nombre de copies pour les escouades regroupées (« ×2 »).
  final String? countLabel;

  const _AllyColumnCard({
    required this.ally,
    required this.onDiscard,
    required this.onStore,
    this.onHeal,
    this.healAmount,
    this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color rarityColor = AppColors.rarityColor(ally.rarity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CardImage(
              category: allyImageCategory(ally.type),
              id: cardImageId(ally.name),
              width: double.infinity,
              height: 190,
              fit: BoxFit.contain,
              fallbackIcon: Icons.person_outline,
            ),
            const SizedBox(height: 8),
            Text(
              countLabel == null ? ally.name : '${ally.name} $countLabel',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: rarityColor),
            ),
            const SizedBox(height: 4),
            Text(
              '${ally.type.displayName} · ${ally.faction.displayName}',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  ally.effectSummary,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall,
                ),
              ),
            ),
            Text(
              '${ally.teamCost} place${ally.teamCost > 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            if (onHeal != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.icon(
                  icon: const Icon(Icons.healing, size: 18),
                  label: Text('Soigner +$healAmount PV',
                      overflow: TextOverflow.ellipsis),
                  onPressed: onHeal,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: 'Mettre en réserve (échange avec l’allié stocké)',
                  icon: const Icon(Icons.archive_outlined,
                      size: 20, color: Colors.white70),
                  onPressed: onStore,
                ),
                IconButton(
                  tooltip: 'Défausser',
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.white38),
                  onPressed: onDiscard,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Colonne de l'allié en RÉSERVE (retours playtest : une colonne dédiée à
/// droite, comme sur la maquette).
class _ReserveColumnCard extends StatelessWidget {
  final Ally? storedAlly;
  final bool rarityAllowed;
  final bool canRecruit;
  final VoidCallback onRecruit;
  final VoidCallback onDiscard;

  const _ReserveColumnCard({
    required this.storedAlly,
    required this.rarityAllowed,
    required this.canRecruit,
    required this.onRecruit,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Ally? ally = storedAlly;
    final Color rarityColor =
        ally == null ? Colors.white24 : AppColors.rarityColor(ally.rarity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Réserve',
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                    color: AppColors.gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (ally == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.archive_outlined,
                          size: 40, color: Colors.white24),
                      const SizedBox(height: 10),
                      Text(
                        'Aucun allié en réserve',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else ...<Widget>[
              CardImage(
                category: allyImageCategory(ally.type),
                id: cardImageId(ally.name),
                width: double.infinity,
                height: 190,
                fit: BoxFit.contain,
                fallbackIcon: Icons.person_outline,
              ),
              const SizedBox(height: 8),
              Text(ally.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: rarityColor)),
              const SizedBox(height: 4),
              Text(
                '${ally.type.displayName} · ${ally.faction.displayName}',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      Text(
                        '${ally.rarity.displayName} · '
                        '${ally.teamCost} place${ally.teamCost > 1 ? 's' : ''}',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall
                            ?.copyWith(color: rarityColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ally.effectSummary,
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                      if (!canRecruit)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            rarityAllowed
                                ? 'Recrutement impossible : places '
                                    'd’équipe insuffisantes.'
                                : 'Niveau ${GameConstants.minLevelForRarity(ally.rarity.index)} '
                                    'requis (${ally.rarity.displayName}).',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall
                                ?.copyWith(color: AppColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: canRecruit ? 'Recruter' : 'Recrutement impossible',
                    icon: Icon(
                      Icons.check_circle_outline,
                      color: canRecruit
                          ? AppColors.moveHighlight
                          : Colors.white24,
                    ),
                    onPressed: canRecruit ? onRecruit : null,
                  ),
                  IconButton(
                    tooltip: 'Défausser',
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.white38),
                    onPressed: onDiscard,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Colonne « équipe vide » (aucun allié recruté).
class _EmptyTeamColumn extends StatelessWidget {
  const _EmptyTeamColumn();

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.group_add_outlined,
                size: 44, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text('Aucun allié recruté',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Touchez une case Allié sur le plateau pour recruter '
              '(GDD §8).',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Index des escouades regroupées par nom (Sprint 4.3).
Map<String, List<int>> _squadGroups(Player player) {
  final Map<String, List<int>> groups = <String, List<int>>{};
  for (int i = 0; i < player.allies.length; i++) {
    final Ally ally = player.allies[i];
    if (ally.type == AllyType.escouade) {
      groups.putIfAbsent(ally.name, () => <int>[]).add(i);
    }
  }
  return groups;
}

/// Index des alliés qui ne sont pas des escouades.
List<int> _nonSquadIndexes(Player player) {
  final List<int> indexes = <int>[];
  for (int i = 0; i < player.allies.length; i++) {
    if (player.allies[i].type != AllyType.escouade) indexes.add(i);
  }
  return indexes;
}
