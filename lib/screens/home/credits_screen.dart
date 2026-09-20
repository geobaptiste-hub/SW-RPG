import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/screen_music.dart';
import '../../widgets/app_background.dart';

/// Écran Crédits (bouton de l'écran d'accueil — CDC §3).
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crédits'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => context.go('/'),
        ),
      ),
      body: AppBackground(
        imageId: 'screens/credits/credits',
        child: ScreenMusic(
        track: 'credits',
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Star Wars RPG',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineLarge?.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 6),
                Text(
                  'Jeu de plateau RPG numérique au tour par tour',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                _sectionTitle('Documents de conception'),
                _item(context, 'Game Design Document v1.0'),
                _item(context, 'Cahier des charges v1.0'),
                _item(context, 'Architecture Flutter v1.0'),
                const SizedBox(height: 20),
                _sectionTitle('Technologies'),
                _item(context, 'Flutter (Desktop, Web, iOS)'),
                _item(context, 'Riverpod — gestion d\u2019état'),
                _item(context, 'Hive — sauvegarde locale'),
                _item(context, 'GoRouter — navigation'),
                _item(context, 'Aucun moteur de jeu en V1 (Flame prévu en V2)'),
                const SizedBox(height: 20),
                _sectionTitle('Mentions'),
                Text(
                  'Projet de fan non commercial. Star Wars et tous les noms '
                  'associés sont la propriété de Lucasfilm Ltd. et de The '
                  'Walt Disney Company.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                Text(
                  'Que la Force soit avec vous.',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(color: AppColors.gold),
                ),
              ],
            ),
          ),
        ),
        ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.blue,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _item(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
}
