import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Dé à 6 faces affichant ses points (pips). Pendant l'animation de lancer
/// ([rolling] = vrai), la face affichée tourne au hasard ; le parent fournit
/// la valeur définitive via [value] à l'arrêt.
class DiceWidget extends StatelessWidget {
  final int? value;
  final bool rolling;
  final double size;

  const DiceWidget({
    super.key,
    this.value,
    this.rolling = false,
    this.size = 64,
  });

  /// Position des pips sur une grille 3x3 pour chaque face (index 0..8).
  static const Map<int, List<int>> _pipLayouts = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final int face = value ?? 1;
    final List<int> pips = _pipLayouts[face] ?? const [1];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: rolling ? AppColors.card : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(
          color: AppColors.gold,
          width: rolling ? 2 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: Column(
          children: List.generate(3, (int row) {
            return Expanded(
              child: Row(
                children: List.generate(3, (int col) {
                  final int index = row * 3 + col;
                  final bool hasPip = pips.contains(index);
                  return Expanded(
                    child: Center(
                      child: hasPip
                          ? Container(
                              width: size * 0.14,
                              height: size * 0.14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: rolling
                                    ? AppColors.gold
                                    : const Color(0xFF151515),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Contrôleur d'animation du lancer : fait défiler des faces aléatoires
/// pendant l'animation. La valeur réelle est ensuite tirée par le
/// contrôleur de jeu (`GameController.rollDice`) — l'animation est
/// purement visuelle et ne décide pas du résultat.
class DiceRollAnimation {
  final Random _random = Random();

  /// Fait « rouler » le dé pendant [duration] en notifiant chaque face
  /// affichée via [onTick].
  Future<void> roll({
    required void Function(int face) onTick,
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    const int tickMs = 80;
    final Stopwatch stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < duration) {
      onTick(_random.nextInt(6) + 1);
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
    }
  }
}
