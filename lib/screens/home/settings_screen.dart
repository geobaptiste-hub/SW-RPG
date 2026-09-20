import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/game_service.dart';
import '../../services/settings_service.dart';
import '../../services/sound_service.dart';
import '../../widgets/screen_music.dart';
import '../../widgets/app_background.dart';

/// Écran Paramètres (Sprint 6) : effets sonores (réglage persisté, prêt
/// pour l'arrivée des sons) et effacement de la sauvegarde de partie.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmDeleteSave(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Effacer la sauvegarde ?'),
        content: const Text(
            'La partie en cours (si elle existe) sera définitivement '
            'supprimée. Cette action est irréversible.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(saveServiceProvider).deleteSave();
    ref.invalidate(hasSaveProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sauvegarde effacée.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool sound = ref.watch(soundEnabledProvider);
    final bool music = ref.watch(musicEnabledProvider);
    final bool fullScreen = ref.watch(fullScreenProvider);
    final bool isDesktop =
        !kIsWeb;
    final AsyncValue<bool> hasSave = ref.watch(hasSaveProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => context.go('/'),
        ),
      ),
      body: AppBackground(
        imageId: 'screens/parametres/parametres',
        child: ScreenMusic(
        track: 'parametres',
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Affichage', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          if (isDesktop)
            Card(
              child: SwitchListTile(
                secondary:
                    const Icon(Icons.fullscreen, color: AppColors.gold),
                title: const Text('Plein écran'),
                subtitle: const Text(
                    'Démarrer le jeu en plein écran (désactivez pour '
                    'retrouver une fenêtre avec barre de titre).'),
                value: fullScreen,
                activeThumbColor: AppColors.gold,
                onChanged: (bool value) =>
                    ref.read(fullScreenProvider.notifier).set(value),
              ),
            ),
          const SizedBox(height: 16),
          Text('Audio', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary:
                  const Icon(Icons.music_note, color: AppColors.gold),
              title: const Text('Musique'),
              subtitle: const Text(
                  'Musique de l’accueil en boucle. Déposez vos fichiers '
                  'dans assets/audio/music/.'),
              value: music,
              activeThumbColor: AppColors.gold,
              onChanged: (bool value) {
                ref.read(musicEnabledProvider.notifier).set(value);
                if (value) {
                  ref
                      .read(soundControllerProvider)
                      .playScreenMusic('parametres');
                } else {
                  ref.read(soundControllerProvider).stopMusic();
                }
              },
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.volume_up, color: AppColors.gold),
              title: const Text('Effets sonores'),
              subtitle: const Text(
                  'Niveaux, victoires, éliminations… Déposez vos fichiers '
                  'dans assets/audio/sfx/.'),
              value: sound,
              activeThumbColor: AppColors.gold,
              onChanged: (bool value) =>
                  ref.read(soundEnabledProvider.notifier).set(value),
            ),
          ),
          const SizedBox(height: 16),
          Text('Données', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.save_outlined,
                color:
                    hasSave.value ?? false ? AppColors.moveHighlight : null,
              ),
              title: const Text('Sauvegarde de partie'),
              subtitle: Text((hasSave.value ?? false)
                  ? 'Une partie sauvegardée existe (reprise depuis '
                      'l’accueil).'
                  : 'Aucune partie sauvegardée.'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.danger),
              title: const Text('Effacer la sauvegarde',
                  style: TextStyle(color: AppColors.danger)),
              subtitle: const Text('Supprime définitivement la partie en '
                  'cours sauvegardée.'),
              onTap: () => _confirmDeleteSave(context, ref),
            ),
          ),
        ],
        ),
        ),
      ),
    );
  }
}
