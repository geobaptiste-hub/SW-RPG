import 'package:flutter/material.dart';

import '../core/constants/board_constants.dart';
import '../core/constants/planet_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/planet.dart';
import '../models/tile.dart';
import 'card_image.dart';
import 'fog_widget.dart';

/// Rendu d'une case du plateau : terrain, brouillard, surbrillance de
/// déplacement, et éventuellement le pion du joueur (en enfant).
class TileWidget extends StatelessWidget {
  final Tile tile;
  final Planet planet;

  /// La case est-elle une cible de déplacement valide pour le joueur actif ?
  /// Si oui, elle est surlignée et réagit au tap (CDC §7 : « les cases
  /// voisines disponibles sont surlignées »).
  final bool isMoveTarget;
  final VoidCallback? onTap;

  /// Éventuel pion(s) posé(s) sur cette case.
  final Widget? child;

  const TileWidget({
    super.key,
    required this.tile,
    required this.planet,
    this.isMoveTarget = false,
    this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final PlanetVisual visual = PlanetConstants.visualFor(planet.type);
    final double extent = BoardConstants.tileExtent;

    final Color surfaceColor =
        tile.walkable ? Color(visual.primaryColor) : Color(visual.blockedColor);

    Widget content = FogWidget(
      tile: tile,
      child: Container(
        width: extent,
        height: extent,
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border.all(
            color: tile.walkable
                ? Color(visual.accentColor).withValues(alpha: 0.25)
                : Colors.black54,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(tile.walkable ? 6 : 2),
        ),
        child: Stack(
          children: [
            if (!tile.discovered)
              const UndiscoveredTileDeco()
            else if (tile.monster != null)
              // Contenu de case : visible uniquement une fois la case
              // découverte (convention brouillard de guerre — Sprint 2).
              // Retours playtest 19/09 : image GÉNÉRIQUE (inconnu.png) —
              // impossible de savoir quel monstre attend sur la case ; le
              // vrai monstre n'est révélé que dans l'écran de combat.
              Center(
                child: CardImage(
                  category: 'monsters',
                  id: 'inconnu',
                  size: 34,
                  fallbackIcon: Icons.pest_control,
                  fallbackIconColor: AppColors.danger,
                ),
              ),
            if (child != null) Center(child: child),
          ],
        ),
      ),
    );

    if (isMoveTarget) {
      content = _MoveTargetHighlight(extent: extent, child: content);
    }

    return GestureDetector(
      onTap: onTap,
      child: content,
    );
  }
}

/// Surbrillance animée des cases de déplacement valides.
class _MoveTargetHighlight extends StatefulWidget {
  final double extent;
  final Widget child;

  const _MoveTargetHighlight({required this.extent, required this.child});

  @override
  State<_MoveTargetHighlight> createState() => _MoveTargetHighlightState();
}

class _MoveTargetHighlightState extends State<_MoveTargetHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.moveHighlight.withValues(alpha: 0.5 + 0.5 * t),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.moveHighlight.withValues(alpha: 0.25 * t),
                blurRadius: 8,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
