import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/tile.dart';

/// Rendu du brouillard de guerre pour une case (Architecture — Gestion du
/// brouillard) :
///
///  - jamais vue        : discovered = false, visible = false → masquée ;
///  - déjà explorée     : discovered = true,  visible = false → assombrie ;
///  - actuellement visible : discovered = true, visible = true → nette.
class FogWidget extends StatelessWidget {
  final Tile tile;
  final Widget child;

  const FogWidget({
    super.key,
    required this.tile,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!tile.discovered) {
      // Case jamais découverte : totalement masquée (noir spatial + voile).
      return Container(
        foregroundDecoration: const BoxDecoration(
          color: Color(0xFF05070F),
        ),
        child: child,
      );
    }
    if (!tile.visible) {
      // Case déjà explorée mais hors du rayon visible : assombrie.
      return Container(
        foregroundDecoration: const BoxDecoration(
          color: Color(0x99101420),
        ),
        child: child,
      );
    }
    // Case actuellement visible.
    return child;
  }
}

/// Petit indicateur décoratif étoilé posé sur les cases non découvertes,
/// pour évoquer l'espace sans révéler le terrain.
// TODO(V2 — Polish) : remplacer par des décors de planète réels
// (décors visuels propres à chaque planète, GDD §4) éventuellement animés.
class UndiscoveredTileDeco extends StatelessWidget {
  const UndiscoveredTileDeco({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.auto_awesome_outlined,
        size: 12,
        color: AppColors.textSecondary.withValues(alpha: 0.12),
      ),
    );
  }
}
