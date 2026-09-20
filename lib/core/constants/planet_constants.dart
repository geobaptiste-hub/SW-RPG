import '../../models/boss.dart';
import '../../models/planet.dart';
import '../../models/player.dart' show Faction;
import '../../models/tile.dart' show Position;

/// Ambiance visuelle d'une planète (GDD §4 : « sa propre ambiance visuelle,
/// ses couleurs, ses décors »).
class PlanetVisual {
  final int primaryColor;
  final int accentColor;
  final int blockedColor;

  const PlanetVisual({
    required this.primaryColor,
    required this.accentColor,
    required this.blockedColor,
  });
}

/// Constantes des planètes : planètes de départ, planètes secondaires,
/// correspondance planète → boss, et thèmes visuels.
class PlanetConstants {
  PlanetConstants._();

  /// Planètes de départ (GDD §4, CDC §4 — étape 3).
  static const List<PlanetType> startPlanets = [
    PlanetType.coruscant,
    PlanetType.alderande,
    PlanetType.endor,
    PlanetType.hoth,
    PlanetType.tatooine,
  ];

  /// Planètes secondaires, accessibles uniquement via les portails
  /// (GDD §4 — 4 planètes de 50 cases, une seule génération possible).
  static const List<PlanetType> secondaryPlanets = [
    PlanetType.mustafar,
    PlanetType.yavin4,
    PlanetType.etoileNoire,
    PlanetType.dagobah,
  ];

  /// Boss associé à chaque planète secondaire (GDD — addendum).
  static const Map<PlanetType, BossType> bossBySecondaryPlanet = {
    PlanetType.mustafar: BossType.exogorth,
    PlanetType.yavin4: BossType.kraytDragon,
    PlanetType.etoileNoire: BossType.atAt,
    PlanetType.dagobah: BossType.rancor,
  };

  /// Grille des planètes secondaires : 9x9 = 81 cases, toutes jouables
  /// (retours playtest 10/09/2026 : les 8x7 = 50 cases étaient trop
  /// petites ; plus aucune case bloquée sur les planètes secondaires).
  static const int secondaryGridWidth = 9;
  static const int secondaryGridHeight = 9;
  static const int secondaryPlanetTileCount = 81;
  static const int secondaryBlockedTiles = 0;

  /// Position du portail de retour sur une planète secondaire (centre).
  static const Position secondaryPortalPosition = Position(4, 4);

  /// Faction de chaque boss (GDD — table planètes/boss : Mustafar → Exogorth
  /// Sith, Yavin IV → Krayt Dragon Rebel, Étoile Noire → AT-AT Empire,
  /// Dagobah → Rancor Jedi).
  static const Map<BossType, Faction> bossFactionByType = {
    BossType.exogorth: Faction.sith,
    BossType.kraytDragon: Faction.rebel,
    BossType.atAt: Faction.empire,
    BossType.rancor: Faction.jedi,
  };

  /// Nom affiché de chaque planète (orthographe reprise du GDD/CDC,
  /// y compris « Aldérande »).
  static const Map<PlanetType, String> displayNames = {
    PlanetType.coruscant: 'Coruscant',
    PlanetType.alderande: 'Aldérande',
    PlanetType.endor: 'Endor',
    PlanetType.hoth: 'Hoth',
    PlanetType.tatooine: 'Tatooine',
    PlanetType.mustafar: 'Mustafar',
    PlanetType.yavin4: 'Yavin IV',
    PlanetType.etoileNoire: 'Étoile Noire',
    PlanetType.dagobah: 'Dagobah',
    PlanetType.cantina: 'Cantina',
  };

  /// Position d'arrivée / de départ DANS la cantina (milieu de la rangée
  /// du bas — la rangée du milieu est le comptoir, celle du haut le bar).
  static const Position cantinaArrival = Position(1, 2);

  /// Ambiances visuelles : chaque planète possède ses propres couleurs.
  static const Map<PlanetType, PlanetVisual> visuals = {
    PlanetType.coruscant: PlanetVisual(
      primaryColor: 0xFF3D4E6E,
      accentColor: 0xFF8FB8DE,
      blockedColor: 0xFF232C42,
    ),
    PlanetType.alderande: PlanetVisual(
      primaryColor: 0xFF3E7C59,
      accentColor: 0xFFA8D8B9,
      blockedColor: 0xFF1F3D2C,
    ),
    PlanetType.endor: PlanetVisual(
      primaryColor: 0xFF2E5D34,
      accentColor: 0xFF7FB069,
      blockedColor: 0xFF17301B,
    ),
    PlanetType.hoth: PlanetVisual(
      primaryColor: 0xFF7FA8C9,
      accentColor: 0xFFE8F4FB,
      blockedColor: 0xFF46647E,
    ),
    PlanetType.tatooine: PlanetVisual(
      primaryColor: 0xFFC2A15C,
      accentColor: 0xFFE8D5A3,
      blockedColor: 0xFF6E5A32,
    ),
    PlanetType.mustafar: PlanetVisual(
      primaryColor: 0xFF8C2B1A,
      accentColor: 0xFFFF7A45,
      blockedColor: 0xFF4A140C,
    ),
    PlanetType.yavin4: PlanetVisual(
      primaryColor: 0xFF35604A,
      accentColor: 0xFF9CCB8B,
      blockedColor: 0xFF1B3327,
    ),
    PlanetType.etoileNoire: PlanetVisual(
      primaryColor: 0xFF4A4F58,
      accentColor: 0xFF9AA3B0,
      blockedColor: 0xFF26292F,
    ),
    PlanetType.dagobah: PlanetVisual(
      primaryColor: 0xFF44543A,
      accentColor: 0xFF8FA97C,
      blockedColor: 0xFF232B1D,
    ),
    // Cantina : bois chaud et lumière ambrée.
    PlanetType.cantina: PlanetVisual(
      primaryColor: 0xFF6E4A2A,
      accentColor: 0xFFD9A05B,
      blockedColor: 0xFF3A2614,
    ),
  };

  /// Ambiance visuelle d'une planète.
  static PlanetVisual visualFor(PlanetType type) => visuals[type]!;
}
