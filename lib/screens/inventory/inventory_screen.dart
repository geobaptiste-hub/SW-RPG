import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/constants/game_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game_state.dart';
import '../../services/game_service.dart';
import '../../widgets/sub_screen_shell.dart';
import '../../models/player.dart';
import '../../widgets/card_image.dart';

/// Écran Inventaire (CDC §13, refonte playtest Sprint 6) : 4 colonnes —
/// à gauche l'équipé (arme, tenue), à droite la réserve (arme, tenue).
/// Chaque emplacement affiche la CARTE remplissant la hauteur disponible
/// (format portrait des illustrations), avec son texte dessous.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

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

    return SubScreenShell(
      route: '/inventory',
      title: 'Inventaire',
      // Column (pas ListView) : les cartes peuvent s'étendre sur toute la
      // hauteur disponible (Expanded) au lieu d'une hauteur figée.
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        const Icon(Icons.flash_on, color: AppColors.gold),
                        const SizedBox(height: 4),
                        Text('${active.totalAttack} ATK',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: AppColors.gold)),
                      ],
                    ),
                    Column(
                      children: <Widget>[
                        const Icon(Icons.favorite, color: AppColors.danger),
                        const SizedBox(height: 4),
                        Text('${active.hp} / ${active.totalMaxHp} PV',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: AppColors.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 4 colonnes : moitié GAUCHE = ÉQUIPEMENT (arme, tenue),
          // moitié DROITE = RÉSERVE (arme, tenue).
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // --- Moitié gauche : ÉQUIPEMENT ---
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text('ÉQUIPEMENT',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: AppColors.gold)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: _EquipSlot(
                                  icon: Icons.flash_on,
                                  title: 'Arme',
                                  emptyLabel: 'Aucune arme équipée',
                                  name: active.weapon?.name,
                                  rarity: active.weapon?.rarity,
                                  imageCategory: 'weapons',
                                  imageId: active.weapon?.id,
                                  bonusText: active.weapon == null
                                      ? null
                                      : '+${active.weapon!.attackBonus} ATK',
                                  onDiscard: active.weapon == null
                                      ? null
                                      : () => _confirmDiscard(
                                            context,
                                            name: active.weapon!.name,
                                            onConfirm: controller
                                                .discardEquippedWeapon,
                                          ),
                                  onStore: active.weapon == null ||
                                          active.storedWeapon != null
                                      ? null
                                      : () =>
                                          controller.storeEquippedWeapon(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _EquipSlot(
                                  icon: Icons.shield_outlined,
                                  title: 'Tenue',
                                  emptyLabel: 'Aucune tenue équipée',
                                  name: active.armor?.name,
                                  rarity: active.armor?.rarity,
                                  imageCategory: 'armors',
                                  imageId: active.armor?.id,
                                  bonusText: active.armor == null
                                      ? null
                                      : '+${active.armor!.hpBonus} PV',
                                  onDiscard: active.armor == null
                                      ? null
                                      : () => _confirmDiscard(
                                            context,
                                            name: active.armor!.name,
                                            onConfirm: controller
                                                .discardEquippedArmor,
                                          ),
                                  onStore: active.armor == null ||
                                          active.storedArmor != null
                                      ? null
                                      : () =>
                                          controller.storeEquippedArmor(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // --- Moitié droite : RÉSERVE ---
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text('RÉSERVE',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: AppColors.blue)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: _ReserveSlot(
                                  title: 'Arme',
                                  emptyLabel: 'Vide',
                                  name: active.storedWeapon?.name,
                                  rarity: active.storedWeapon?.rarity,
                                  imageCategory: 'weapons',
                                  imageId: active.storedWeapon?.id,
                                  bonusText: active.storedWeapon == null
                                      ? null
                                      : '+${active.storedWeapon!.attackBonus} ATK',
                                  equipLabel: 'Équiper l\'arme',
                                  allowed: active.storedWeapon != null &&
                                      GameController.rarityAllowedForLevel(
                                          active.storedWeapon!.rarity,
                                          active.level),
                                  requiredLevel: active.storedWeapon == null
                                      ? null
                                      : GameConstants.minLevelForRarity(
                                          active.storedWeapon!.rarity.index),
                                  onEquip: () =>
                                      controller.equipStoredWeapon(),
                                  onDiscard: active.storedWeapon == null
                                      ? null
                                      : () => _confirmDiscard(
                                            context,
                                            name: active.storedWeapon!.name,
                                            onConfirm: controller
                                                .discardStoredWeapon,
                                          ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ReserveSlot(
                                  title: 'Tenue',
                                  emptyLabel: 'Vide',
                                  name: active.storedArmor?.name,
                                  rarity: active.storedArmor?.rarity,
                                  imageCategory: 'armors',
                                  imageId: active.storedArmor?.id,
                                  bonusText: active.storedArmor == null
                                      ? null
                                      : '+${active.storedArmor!.hpBonus} PV',
                                  equipLabel: 'Équiper la tenue',
                                  allowed: active.storedArmor != null &&
                                      GameController.rarityAllowedForLevel(
                                          active.storedArmor!.rarity,
                                          active.level),
                                  requiredLevel: active.storedArmor == null
                                      ? null
                                      : GameConstants.minLevelForRarity(
                                          active.storedArmor!.rarity.index),
                                  onEquip: () =>
                                      controller.equipStoredArmor(),
                                  onDiscard: active.storedArmor == null
                                      ? null
                                      : () => _confirmDiscard(
                                            context,
                                            name: active.storedArmor!.name,
                                            onConfirm: controller
                                                .discardStoredArmor,
                                          ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Restrictions (GDD §9) : Commun jusqu\'au niveau 2, '
              'Rare au niveau 3, Épique au niveau 4, '
              'Légendaire au niveau 5, Mythique au niveau 6.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// Confirmation avant défausse définitive d'un objet (retours playtest
  /// — même pattern que la défausse d'allié de l'écran Équipe).
  Future<void> _confirmDiscard(
    BuildContext context, {
    required String name,
    required VoidCallback onConfirm,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Défausser cet objet ?'),
        content: Text(
            '$name sera détruit définitivement (la défausse est '
            'irréversible).'),
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
      onConfirm();
    }
  }
}

/// Emplacement d'équipement (retours playtest Sprint 6) : la CARTE
/// remplit la hauteur disponible au-dessus du texte, boutons en rangée
/// dessous.
class _EquipSlot extends StatelessWidget {
  final IconData icon;
  final String title;
  final String emptyLabel;
  final String? name;
  final Rarity? rarity;
  final String? bonusText;

  /// Image de la carte : `assets/images/<imageCategory>/<imageId>.png`.
  final String imageCategory;
  final String? imageId;

  /// Range l'objet équipé en réserve (null si réserve occupée ou vide).
  final VoidCallback? onStore;

  /// Défausse de l'objet équipé (null si l'emplacement est vide).
  final VoidCallback? onDiscard;

  const _EquipSlot({
    required this.icon,
    required this.title,
    required this.emptyLabel,
    required this.name,
    required this.rarity,
    required this.bonusText,
    this.imageCategory = 'weapons',
    this.imageId,
    this.onStore,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool has = name != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            if (has) ...<Widget>[
              // La carte occupe TOUTE la hauteur restante de la colonne.
              Expanded(
                child: CardImage(
                  category: imageCategory,
                  id: imageId!,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  fallbackIcon: icon,
                  fallbackIconColor: AppColors.gold,
                ),
              ),
              const SizedBox(height: 8),
              Text(name!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Chip(
                    label: Text(
                      rarity!.displayName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: AppColors.rarityColor(rarity!),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(bonusText!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.moveHighlight)),
                  ),
                ],
              ),
              if (onStore != null || onDiscard != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (onStore != null)
                      IconButton(
                        tooltip: 'Ranger en réserve',
                        icon: const Icon(Icons.archive_outlined,
                            size: 20, color: Colors.white70),
                        onPressed: onStore,
                      ),
                    if (onDiscard != null)
                      IconButton(
                        tooltip: 'Défausser',
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Colors.white38),
                        onPressed: onDiscard,
                      ),
                  ],
                ),
            ] else ...<Widget>[
              Expanded(
                child: Center(
                    child: Icon(icon, size: 44, color: Colors.white24)),
              ),
              Text(emptyLabel,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// Emplacement de réserve : carte remplissant la hauteur disponible,
/// équipement possible si la rareté est autorisée au niveau (sinon
/// « Niveau X requis » affiché).
class _ReserveSlot extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final String? name;
  final Rarity? rarity;
  final String? bonusText;
  final String equipLabel;
  final bool allowed;

  /// Image de la carte (Sprint 6).
  final String? imageCategory;
  final String? imageId;

  /// Niveau minimum requis (affiché quand [allowed] est faux).
  final int? requiredLevel;
  final VoidCallback onEquip;

  /// Défausse de l'objet en réserve (null si l'emplacement est vide).
  final VoidCallback? onDiscard;

  const _ReserveSlot({
    required this.title,
    required this.emptyLabel,
    required this.name,
    required this.rarity,
    required this.bonusText,
    required this.equipLabel,
    required this.allowed,
    required this.onEquip,
    this.imageCategory,
    this.imageId,
    this.requiredLevel,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool has = name != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            if (has) ...<Widget>[
              Expanded(
                child: CardImage(
                  category: imageCategory ?? 'weapons',
                  id: imageId!,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  fallbackIcon: Icons.image_outlined,
                ),
              ),
              const SizedBox(height: 8),
              Text(name!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Chip(
                    label: Text(
                      rarity!.displayName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: AppColors.rarityColor(rarity!),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(bonusText!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.moveHighlight)),
                  ),
                ],
              ),
              if (!allowed && requiredLevel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Niveau $requiredLevel requis pour équiper '
                    '(${rarity!.displayName}).',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: allowed ? equipLabel : 'Niveau requis',
                    icon: Icon(
                      Icons.check_circle_outline,
                      color:
                          allowed ? AppColors.moveHighlight : Colors.white24,
                    ),
                    onPressed: allowed ? onEquip : null,
                  ),
                  if (onDiscard != null)
                    IconButton(
                      tooltip: 'Défausser',
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: Colors.white38),
                      onPressed: onDiscard,
                    ),
                ],
              ),
            ] else ...<Widget>[
              Expanded(
                child: Center(
                    child: Icon(Icons.image_outlined,
                        size: 44, color: Colors.white24)),
              ),
              Text(emptyLabel,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
