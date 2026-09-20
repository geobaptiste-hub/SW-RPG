import io

# ---------- 2) dialog recrutement : effet des alliés à défausser ----------
p = 'lib/screens/board/board_screen.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

patch(
    """                          Text(
                            '${active.allies[index].type.displayName} · '
                            '${active.allies[index].faction.displayName} · '
                            '${active.allies[index].rarity.displayName} · '
                            '${active.allies[index].teamCost} PP',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.rarityColor(
                                        active.allies[index].rarity)),
                          ),""",
    """                          Text(
                            '${active.allies[index].type.displayName} · '
                            '${active.allies[index].faction.displayName} · '
                            '${active.allies[index].rarity.displayName} · '
                            '${active.allies[index].teamCost} PP',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.rarityColor(
                                        active.allies[index].rarity)),
                          ),
                          // Effet de l'allié (retours playtest : savoir ce
                          // qu'on perd avant de défausser).
                          Text(
                            active.allies[index].effectSummary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),""")

# ---------- 4) HUD : faction de la planète ----------
patch(
    """          // Planète courante (Sprint 5 — multi-planètes).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.public, size: 13, color: AppColors.gold),
                const SizedBox(width: 4),
                Text(
                  PlanetConstants.displayNames[state.planetType] ??
                      state.planetType.name,
                  style:
                      textTheme.labelMedium?.copyWith(color: AppColors.gold),
                ),
              ],
            ),
          ),""",
    """          // Planète courante (Sprint 5 — multi-planètes) + sa faction
          // pour les planètes secondaires (retours playtest).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.public, size: 13, color: AppColors.gold),
                const SizedBox(width: 4),
                Text(
                  PlanetConstants.displayNames[state.planetType] ??
                      state.planetType.name,
                  style:
                      textTheme.labelMedium?.copyWith(color: AppColors.gold),
                ),
                if (_planetFaction(state.planetType) != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    _planetFaction(state.planetType)!.displayName,
                    style: textTheme.labelMedium?.copyWith(
                        color: factionColor(
                            _planetFaction(state.planetType)!)),
                  ),
                ],
              ],
            ),
          ),""")

# helper _planetFaction dans _TopHud
patch(
    """  /// Couleur d'ambiance de chaque faction (chips du HUD et de l'équipe).
  static Color factionColor(Faction faction) => switch (faction) {""",
    """  /// Faction d'une planète secondaire (celle de son boss) ; null pour
  /// les planètes de départ (retours playtest).
  static Faction? _planetFaction(PlanetType type) {
    if (!PlanetConstants.secondaryPlanets.contains(type)) return null;
    final BossType? boss = PlanetConstants.bossBySecondaryPlanet[type];
    return boss == null
        ? null
        : PlanetConstants.bossFactionByType[boss];
  }

  /// Couleur d'ambiance de chaque faction (chips du HUD et de l'équipe).
  static Color factionColor(Faction faction) => switch (faction) {""")

patch(
    "import '../../models/planet.dart' show PlanetType;",
    "import '../../models/boss.dart' show BossType;\nimport '../../models/planet.dart' show PlanetType;")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('board_screen OK')

# ---------- 5) redépôt : jamais sur une case portail ----------
p = 'lib/services/game_service.dart'
s = io.open(p, encoding='utf-8').read()

patch(
    """    final List<Tile> candidates = <Tile>[
      for (final Tile t in planet.tiles)
        if (t.walkable &&
            !(t.x == target.x && t.y == target.y) &&
            Position(t.x, t.y).chebyshevDistanceTo(target) >= 5 &&
            !t.visible &&
            !BoardConstants.startPositions.contains(Position(t.x, t.y)) &&
            !occupied.contains(Position(t.x, t.y)) &&
            t.monster == null &&
            t.ally == null &&
            t.weapon == null &&
            t.armor == null &&
            !t.healSite)
          t,
    ];""",
    """    // Les positions des portails ne sont JAMAIS des candidates (retours
    // playtest : un soin redéposé sur la case du portail bloquait le
    // voyage).
    bool isPortalTile(Position p) =>
        state!.portals.any((Portal portal) => portal.position == p) ||
        (!PlanetConstants.startPlanets.contains(planet.type) &&
            p == PlanetConstants.secondaryPortalPosition);

    final List<Tile> candidates = <Tile>[
      for (final Tile t in planet.tiles)
        if (t.walkable &&
            !(t.x == target.x && t.y == target.y) &&
            Position(t.x, t.y).chebyshevDistanceTo(target) >= 5 &&
            !t.visible &&
            !BoardConstants.startPositions.contains(Position(t.x, t.y)) &&
            !occupied.contains(Position(t.x, t.y)) &&
            !isPortalTile(Position(t.x, t.y)) &&
            t.monster == null &&
            t.ally == null &&
            t.weapon == null &&
            t.armor == null &&
            !t.healSite)
          t,
    ];""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('game_service OK')
