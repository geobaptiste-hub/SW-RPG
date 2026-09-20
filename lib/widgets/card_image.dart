
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/enums.dart';
import '../models/boss.dart' show BossType;
import '../models/planet.dart' show PlanetType;
import '../core/utils/slug.dart';
import '../services/image_service.dart';

/// Dossier d'image d'un allié : `allies/<sous-dossier>/<slug>.png`
/// (convention `SW/MD/images-cartes.md`).
String allyImageCategory(AllyType type) => switch (type) {
      AllyType.healer => 'allies/healers',
      AllyType.tank => 'allies/tanks',
      AllyType.nuker => 'allies/nukers',
      AllyType.escouade => 'allies/squads',
      AllyType.soutien => 'allies/supports',
      AllyType.special => 'allies/specials',
    };

/// Identifiant d'image d'une carte nommée (slug du nom).
String cardImageId(String name) => slugify(name);

/// Identifiant d'image d'une planète (`assets/images/planets/<id>.png` —
/// mapping explicite : « Yavin IV » slugifierait yavin_iv au lieu de
/// yavin4, « Étoile Noire » → etoile_noire).
String planetImageId(PlanetType type) => switch (type) {
      PlanetType.coruscant => 'coruscant',
      PlanetType.alderande => 'alderande',
      PlanetType.endor => 'endor',
      PlanetType.hoth => 'hoth',
      PlanetType.tatooine => 'tatooine',
      PlanetType.mustafar => 'mustafar',
      PlanetType.yavin4 => 'yavin4',
      PlanetType.etoileNoire => 'etoile_noire',
      PlanetType.dagobah => 'dagobah',
      PlanetType.cantina => 'cantina',
    };

/// Identifiant d'ambiance AUDIO d'une planète (dossier `assets/audio/
/// music/planetes/`, jouée en boucle tant que le joueur y reste) —
/// mêmes noms de fichiers que les images de planètes : déposer
/// coruscant.mp3 à côté de coruscant.png, etc.
String planetAmbienceTrack(PlanetType type) => planetImageId(type);

/// Identifiant d'image d'un BOSS : slug explicite (les noms d'enum
/// kraytDragon/atAt donneraient kraytdragon/atat au lieu des fichiers
/// `krayt_dragon.png` / `at_at.png` — fix playtest).
String bossImageId(BossType type) => switch (type) {
      BossType.exogorth => 'exogorth',
      BossType.kraytDragon => 'krayt_dragon',
      BossType.atAt => 'at_at',
      BossType.rancor => 'rancor',
    };

/// Image d'une carte (monstre, allié, arme…) chargée depuis
/// `assets/images/<catégorie>/<id>.png` sur le disque, avec repli sur un
/// widget placeholder tant que l'image n'a pas été déposée (Sprint 6 —
/// « tout fichier absent = placeholder automatique, aucun crash »).
///
/// Deux modes de dimensionnement :
///  - [size] : boîte carrée (comportement historique) ;
///  - [width] / [height] : boîte rectangulaire — utile pour les cartes au
///    format portrait (650×1004), avec [fit] à BoxFit.contain.
class CardImage extends ConsumerWidget {
  /// Catégorie = sous-dossier (`characters`, `monsters`, `bosses`,
  /// `allies/healers`, `weapons`, …).
  final String category;

  /// Identifiant de fichier sans extension (slug du nom ou champ `id`).
  final String id;

  /// Côté de la boîte carrée (ignoré si [width]/[height] sont fournis).
  final double size;

  /// Largeur de la boîte (mode rectangulaire).
  final double? width;

  /// Hauteur de la boîte (mode rectangulaire).
  final double? height;

  /// Placeholder affiché si l'image n'existe pas.
  final Widget? fallback;

  /// Icône de repli par défaut (utilisée si [fallback] est null).
  final IconData fallbackIcon;
  final Color fallbackIconColor;

  final BoxFit fit;

  const CardImage({
    super.key,
    required this.category,
    required this.id,
    this.size = 48,
    this.width,
    this.height,
    this.fallback,
    this.fallbackIcon = Icons.image_outlined,
    this.fallbackIconColor = Colors.white24,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ImageProvider? provider =
        ref.watch(imageServiceProvider).providerFor(category, id);
    final double boxWidth = width ?? size;
    final double boxHeight = height ?? size;
    Widget placeholder() => Center(
          child: fallback ??
              Icon(fallbackIcon,
                  size: 24, color: fallbackIconColor),
        );

    if (provider == null) {
      return SizedBox(
        width: boxWidth,
        height: boxHeight,
        child: placeholder(),
      );
    }
    return SizedBox(
      width: boxWidth,
      height: boxHeight,
      child: Image(
        image: provider,
        fit: fit,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                placeholder(),
      ),
    );
  }
}
