import 'package:flutter/material.dart';

import '../models/boss.dart';

/// Icône représentative de chaque boss, partagée par le plateau et
/// l'écran de combat (Sprint 5 — aucun visuel définitif, placeholders
/// Material en attendant les images du Sprint 6).
IconData bossIcon(BossType type) => switch (type) {
      BossType.exogorth => Icons.blur_circular,
      BossType.kraytDragon => Icons.whatshot,
      BossType.atAt => Icons.directions_walk,
      BossType.rancor => Icons.pets,
    };
