import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/game_service.dart';
import '../../widgets/sub_screen_shell.dart';

/// Journal de partie (GDD §14 — Sprint 6) : montées de niveau, découverte
/// de portail/planète, objet rare, victoire de boss, élimination. Les
/// entrées sont ajoutées par le GameController ; le plus récent en tête.
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return SubScreenShell(
      route: '/journal',
      title: 'Journal de partie',
      body: ValueListenableBuilder<int>(
        valueListenable: controller.gameLogVersion,
        builder: (BuildContext context, int _, Widget? child) {
          final List<String> entries =
              controller.gameLog.reversed.toList(growable: false);
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.receipt_long,
                        size: 52, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      'Aucun événement pour le moment.\n'
                      'Montées de niveau, portails, objets rares, boss et '
                      'éliminations s’inscriront ici.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 4),
            itemBuilder: (BuildContext context, int index) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  entries[index],
                  style: textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
