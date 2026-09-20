import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/constants/board_constants.dart';
import '../core/utils/slug.dart';
import '../models/player.dart';
import '../services/image_service.dart';

/// Pion d'un joueur sur le plateau : cercle coloré portant la PHOTO du
/// personnage si déposée (`assets/images/characters/<slug>.png`), sinon
/// l'initiale. Le joueur actif est marqué d'un anneau doré (Sprint 6).
class PlayerToken extends ConsumerWidget {
  final Player player;

  /// Index du joueur dans la liste (détermine la couleur du pion).
  final int playerIndex;

  /// Vrai si c'est actuellement le tour de ce joueur.
  final bool isActive;

  const PlayerToken({
    super.key,
    required this.player,
    required this.playerIndex,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double size = BoardConstants.tileExtent * 0.72;
    final Color color = AppColors.playerTokenColor(playerIndex);
    final File? photo = ref
        .watch(imageServiceProvider)
        .resolveFile('characters', slugify(player.name));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: isActive ? AppColors.gold : Colors.black87,
          width: isActive ? 3 : 1.5,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ]
            : const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
      ),
      child: Stack(
        children: [
          if (photo != null)
            Positioned.fill(
              child: ClipOval(
                child: Image.file(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error,
                          StackTrace? stackTrace) =>
                      _initialLabel(color),
                ),
              ),
            )
          else
            Center(child: _initialLabel(color)),
          if (player.team != null)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.teamColor(player.team!),
                  border: Border.all(color: Colors.black87, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initialLabel(Color color) {
    return Text(
      _initials(player.name),
      style: TextStyle(
        color: _readableOn(color),
        fontWeight: FontWeight.w800,
        fontSize: BoardConstants.tileExtent * 0.72 * 0.36,
      ),
    );
  }

  String _initials(String name) {
    final List<String> words = name
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    final String first = words.first.characters.first;
    final String last = words.last.characters.first;
    return (first + last).toUpperCase();
  }

  Color _readableOn(Color background) {
    // Luminance relative : texte sombre sur pion clair, clair sinon.
    return background.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
  }
}
