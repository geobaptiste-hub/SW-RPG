import io

# ============ card_image : ids de boss explicites ============
p = 'lib/widgets/card_image.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

patch(
    "import '../core/constants/enums.dart';\nimport '../core/utils/slug.dart';\nimport '../services/image_service.dart';",
    "import '../core/constants/enums.dart';\nimport '../core/utils/slug.dart';\nimport '../services/image_service.dart';")

patch(
    """/// Identifiant d'image d'une carte nommée (slug du nom).
String cardImageId(String name) => slugify(name);""",
    """/// Identifiant d'image d'une carte nommée (slug du nom).
String cardImageId(String name) => slugify(name);

/// Identifiant d'image d'un BOSS : slug explicite (les noms d'enum
/// kraytDragon/atAt donneraient kraytdragon/atat au lieu des fichiers
/// `krayt_dragon.png` / `at_at.png` — fix playtest).
String bossImageId(BossType type) => switch (type) {
      BossType.exogorth => 'exogorth',
      BossType.kraytDragon => 'krayt_dragon',
      BossType.atAt => 'at_at',
      BossType.rancor => 'rancor',
    };""")

patch(
    "import '../core/constants/enums.dart';",
    "import '../core/constants/enums.dart';\nimport '../models/boss.dart' show BossType;")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('card_image OK')

# ---------- board_widget : utiliser bossImageId ----------
p = 'lib/widgets/board_widget.dart'
s = io.open(p, encoding='utf-8').read()
patch(
    "                        .resolveFile('bosses', cardImageId(boss.type.name));",
    "                        .resolveFile('bosses', bossImageId(boss.type));")
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('board_widget OK')

# ---------- combat_screen : carte du boss avec bossImageId ----------
p = 'lib/screens/combat/combat_screen.dart'
s = io.open(p, encoding='utf-8').read()
patch(
    """            CardImage(
              category: 'bosses',
              id: cardImageId(type.name),
              size: 72,""",
    """            CardImage(
              category: 'bosses',
              id: bossImageId(type),
              size: 72,""")
patch(
    "import '../../widgets/boss_icon.dart';",
    "import '../../widgets/boss_icon.dart';\nimport '../../widgets/card_image.dart';")
# boss_icon import pourrait devenir unused si card_image le remplace — non, les deux utilisés
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('combat_screen OK')

# ---------- populate : jamais de contenu sur une case portail ----------
p = 'lib/services/map_service.dart'
s = io.open(p, encoding='utf-8').read()
patch(
    """      if (starts.contains(position) || occupied.contains(position)) {
        tiles.add(newTile);
        continue;
      }

      // Tirage du type d'événement.""",
    """      if (starts.contains(position) || occupied.contains(position)) {
        tiles.add(newTile);
        continue;
      }
      // La case d'un portail n'est JAMAIS peuplée (retours playtest : un
      // objet posé par la révélation bloquait l'accès au portail — le
      // dialog de trouvaille passait avant le voyage).
      if (existingPortals.any((Portal portal) => portal.position == position)) {
        tiles.add(newTile);
        continue;
      }

      // Tirage du type d'événement.""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('map_service OK')

# ---------- redépôt : loin et hors de vue ----------
patch(
    """    final List<Tile> candidates = <Tile>[
      for (final Tile t in planet.tiles)
        if (t.walkable &&
            !(t.x == target.x && t.y == target.y) &&
            !BoardConstants.startPositions.contains(Position(t.x, t.y)) &&
            !occupied.contains(Position(t.x, t.y)) &&
            t.monster == null &&
            t.ally == null &&
            t.weapon == null &&
            t.armor == null &&
            !t.healSite)
          t,
    ];""",
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
    ];""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('redépôt loin OK')
