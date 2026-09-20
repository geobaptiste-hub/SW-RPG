import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/image_service.dart';

/// Fond d'écran des écrans HORS PARTIE (accueil, création, paramètres,
/// crédits, game over) : l'image déposée dans
/// `assets/images/screens/accueil.png|jpg` (1920×1080 conseillé) remplit
/// l'écran derrière le contenu, avec un voile sombre léger pour la
/// lisibilité. Sans image déposée : le fond sombre habituel.
///
/// Le contenu est par-dessus l'image : rien n'est caché.
class AppBackground extends ConsumerWidget {
  /// Chemin relatif de l'image de fond (sans extension), ex.
  /// `screens/accueil` ou `screens/credits`. Par défaut : l'image de
  /// l'accueil ; si elle est absente aussi, fond sombre.
  final String imageId;

  final Widget child;

  const AppBackground({super.key, this.imageId = 'screens/accueil', required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Image spécifique d'abord, sinon repli sur l'image de l'accueil,
    // sinon fond sombre.
    final File? background = ref
            .watch(imageServiceProvider)
            .resolveImage(imageId) ??
        ref.watch(imageServiceProvider).resolveImage('screens/accueil');

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (background != null) ...<Widget>[
          Image.file(
            background,
            fit: BoxFit.cover,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                    const SizedBox.shrink(),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
        ],
        child,
      ],
    );
  }
}
