import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_theme.dart';
import '../../services/game_service.dart';
import '../../widgets/app_background.dart';
import '../../widgets/screen_music.dart';

/// Écran d'accueil (CDC §3) : Nouvelle partie, Reprendre partie,
/// Paramètres, Crédits.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool? _hasSave;

  @override
  void initState() {
    super.initState();
    _refreshHasSave();
  }

  Future<void> _refreshHasSave() async {
    final bool hasSave = await ref.read(saveServiceProvider).hasSave();
    if (mounted) setState(() => _hasSave = hasSave);
  }

  Future<void> _resumeGame() async {
    final bool success =
        await ref.read(gameControllerProvider.notifier).resumeGame();
    if (!mounted) return;
    if (success) {
      context.go('/board');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune sauvegarde exploitable trouvée.')),
      );
      _refreshHasSave();
    }
  }

  /// Quitte l'application (retours playtest : en plein écran il n'y a
  /// plus de croix de fenêtre — il faut un bouton explicite).
  Future<void> _quitGame() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Quitter le jeu ?'),
        content: const Text(
            'La partie sauvegardée est conservée : vous pourrez la reprendre '
            'depuis l’accueil.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!kIsWeb && (!kIsWeb)) {
      await windowManager.destroy();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    // Fix 19/09 : lisibilité sur l'image de fond (comme le Game Over) —
    // ombres portées sur le bloc titre, et boutons secondaires opaques
    // reprenant le style des cartes de l'écran Paramètres.
    const List<Shadow> titleShadows = <Shadow>[
      Shadow(color: Color(0xCC000000), blurRadius: 12, offset: Offset(0, 2)),
    ];
    final ButtonStyle cardButtonStyle = OutlinedButton.styleFrom(
      backgroundColor: AppColors.card,
      side: const BorderSide(color: Colors.white10),
    );

    return Scaffold(
      body: ScreenMusic(
        track: 'accueil',
        child: AppBackground(
          child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 32),
                    Text(
                      'STAR WARS',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineLarge?.copyWith(
                          fontSize: 44, shadows: titleShadows),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R P G',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        color: AppColors.blue,
                        letterSpacing: 12,
                        fontWeight: FontWeight.w800,
                        shadows: titleShadows,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Jeu de plateau RPG au tour par tour',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w600,
                        shadows: titleShadows,
                      ),
                    ),
                    const SizedBox(height: 48),
                    FilledButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Nouvelle Partie'),
                      onPressed: () => context.go('/new-game'),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(
                        'Reprendre Partie',
                        style: _hasSave == false
                            ? const TextStyle(color: Colors.black38)
                            : null,
                      ),
                      style: _hasSave == false
                          ? FilledButton.styleFrom(
                              backgroundColor:
                                  AppColors.gold.withValues(alpha: 0.45))
                          : null,
                      onPressed:
                          _hasSave == false ? null : () => _resumeGame(),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.settings_outlined,
                          color: AppColors.gold),
                      label: const Text('Paramètres'),
                      style: cardButtonStyle,
                      onPressed: () => context.go('/settings'),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.info_outline,
                          color: AppColors.gold),
                      label: const Text('Crédits'),
                      style: cardButtonStyle,
                      onPressed: () => context.go('/credits'),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.exit_to_app,
                          color: AppColors.gold),
                      label: const Text('Quitter le jeu'),
                      style: cardButtonStyle,
                      onPressed: _quitGame,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
        ),
    );
  }
}
