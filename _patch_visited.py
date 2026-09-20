import io

# ---------- portal.dart : champ visited ----------
p = 'lib/models/portal.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

patch(
    """  /// Vrai lorsque le portail a été découvert (à ce moment, tous les
  /// joueurs sont informés — GDD §5).
  final bool discovered;

  const Portal({
    required this.destination,
    required this.position,
    this.discovered = false,
  });

  Portal copyWith({bool? discovered}) => Portal(
        destination: destination,
        position: position,
        discovered: discovered ?? this.discovered,
      );

  Map<String, dynamic> toJson() => {
        'destination': enumToName(destination),
        'position': position.toJson(),
        'discovered': discovered,
      };""",
    """  /// Vrai lorsque le portail a été découvert (à ce moment, tous les
  /// joueurs sont informés — GDD §5).
  final bool discovered;

  /// Vrai lorsqu'au moins un joueur a traversé ce portail (retours
  /// playtest : son illustration devient celle de la planète de
  /// destination sur le plateau).
  final bool visited;

  const Portal({
    required this.destination,
    required this.position,
    this.discovered = false,
    this.visited = false,
  });

  Portal copyWith({bool? discovered, bool? visited}) => Portal(
        destination: destination,
        position: position,
        discovered: discovered ?? this.discovered,
        visited: visited ?? this.visited,
      );

  Map<String, dynamic> toJson() => {
        'destination': enumToName(destination),
        'position': position.toJson(),
        'discovered': discovered,
        'visited': visited,
      };""")

patch(
    "      discovered: json['discovered'] as bool? ?? false,\n    };",
    "      discovered: json['discovered'] as bool? ?? false,\n      visited: json['visited'] as bool? ?? false,\n    };")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('portal OK')

# ---------- game_service : marquer visited à l'aller ----------
p = 'lib/services/game_service.dart'
s = io.open(p, encoding='utf-8').read()

patch(
    """    final int index = current.currentPlayerIndex;
    players[index] = players[index].copyWith(
      position: arrival,
      planet: destination,
      returnPlanet: current.planetType,
      returnPosition: portal.position,
    );
    log('🚀 ${players[index].name} a voyagé vers '
        '${PlanetConstants.displayNames[destination] ?? destination.name}.');""",
    """    final int index = current.currentPlayerIndex;
    players[index] = players[index].copyWith(
      position: arrival,
      planet: destination,
      returnPlanet: current.planetType,
      returnPosition: portal.position,
    );
    log('🚀 ${players[index].name} a voyagé vers '
        '${PlanetConstants.displayNames[destination] ?? destination.name}.');
    // Le portail traversé est marqué « visité » (retours playtest : son
    // illustration devient celle de la planète de destination).
    final List<Portal> portals = <Portal>[
      for (final Portal p in current.portals)
        if (p.position == portal.position && p.destination == portal.destination)
          p.copyWith(visited: true)
        else
          p,
    ];""")

patch(
    """    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: planets,
      currentPlanet: secondary,
      planetType: destination,
      // Le pas sur la case du portail coûte 1 point (comme tout déplacement) ;
      // le voyage lui-même est gratuit — pas de second décrément.
      movementPointsRemaining: current.movementPointsRemaining - 1,
    ));
    return MoveResult.portalTravel;
  }""",
    """    state = _applySurvivorCheck(current.copyWith(
      players: players,
      planets: planets,
      portals: portals,
      currentPlanet: secondary,
      planetType: destination,
      // Le pas sur la case du portail coûte 1 point (comme tout déplacement) ;
      // le voyage lui-même est gratuit — pas de second décrément.
      movementPointsRemaining: current.movementPointsRemaining - 1,
    ));
    return MoveResult.portalTravel;
  }""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('game_service OK')
