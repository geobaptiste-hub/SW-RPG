import io

# ---------- game_service : victoire Big Four ----------
p = 'lib/services/game_service.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

patch(
    """    // Modes à équipes (Équipes, Big Four) : la partie se termine quand une""",
    """    // Big Four : victoire d'équipe par objectifs — union des boss de
    // l'équipe, HORS boss des factions des membres (chaque équipe
    // représente une faction : son boss ne compte pas).
    if (s.mode == GameMode.bigFour) {
      for (final TeamSide side in TeamSide.values) {
        final List<Player> members = s.players
            .where((Player p) => p.team == side && !p.eliminated)
            .toList();
        if (members.isEmpty) continue;
        final Set<Faction> teamFactions = <Faction>{
          for (final Player p in members) p.faction,
        };
        final Set<BossType> adverseBosses = <BossType>{
          for (final Player p in members)
            for (final BossType boss in p.defeatedBosses)
              if (!teamFactions
                  .contains(PlanetConstants.bossFactionByType[boss]))
                boss,
        };
        if (adverseBosses.length >= GameConstants.bossesToWin) {
          return s.copyWith(status: GameStatus.finished);
        }
      }
    }

    // Modes à équipes (Équipes, Big Four) : la partie se termine quand une""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('game_service OK')

# ---------- game_over_screen : resolveWinner générique ----------
p = 'lib/screens/game_over/game_over_screen.dart'
s = io.open(p, encoding='utf-8').read()

patch(
    """    // Modes à équipes.
    // 1) Équipe adverse entièrement éliminée ;
    // 2) union des boss vaincus couvrant 3 boss différents.
    for (final TeamSide side in TeamSide.values) {
      final bool anyAlive =
          state.players.any((Player p) => p.team == side && !p.eliminated);
      if (!anyAlive) {
        final TeamSide winner =
            side == TeamSide.teamA ? TeamSide.teamB : TeamSide.teamA;
        return (
          title: 'L’équipe ${winner.displayName} remporte la partie !',
          detail: 'L’équipe ${side.displayName} a été entièrement éliminée.'
        );
      }
    }
    for (final TeamSide side in TeamSide.values) {
      final Set<BossType> defeated = <BossType>{
        for (final Player p in state.players)
          if (p.team == side) ...p.defeatedBosses,
      };
      if (defeated.length >= GameConstants.bossesToWin) {
        return (
          title: 'L’équipe ${side.displayName} remporte la partie !',
          detail: 'Victoire par objectifs : ${defeated.length} boss '
              'différents vaincus par l’équipe.'
        );
      }
    }
    return (title: 'Partie terminée', detail: 'Toutes les conditions de fin.');""",
    """    // Modes à équipes (Équipes, Big Four) — générique à N équipes.
    // 1) Victoire par objectifs : union des boss de l'équipe (en Big Four,
    //    le boss de la faction de l'équipe ne compte pas).
    for (final TeamSide side in TeamSide.values) {
      final List<Player> members =
          state.players.where((Player p) => p.team == side).toList();
      if (members.isEmpty) continue;
      final Set<BossType> defeated = <BossType>{
        for (final Player p in members) ...p.defeatedBosses,
      };
      final Set<Faction> teamFactions = <Faction>{
        for (final Player p in members) p.faction,
      };
      final int adverse = state.mode == GameMode.bigFour
          ? defeated
              .where((BossType b) =>
                  !teamFactions.contains(
                      PlanetConstants.bossFactionByType[b]))
              .length
          : defeated.length;
      if (adverse >= GameConstants.bossesToWin) {
        return (
          title: 'L’équipe ${side.displayName} remporte la partie !',
          detail: 'Victoire par objectifs : $adverse boss adverses vaincus '
              'par l’équipe.'
        );
      }
    }
    // 2) Dernière équipe vivante (toutes les autres éliminées).
    final Set<TeamSide> aliveTeams = <TeamSide>{
      for (final Player p in state.players)
        if (!p.eliminated && p.team != null) p.team!,
    };
    if (aliveTeams.length == 1) {
      final TeamSide winner = aliveTeams.first;
      return (
        title: 'L’équipe ${winner.displayName} remporte la partie !',
        detail: 'Dernière équipe debout de la galaxie.'
      );
    }
    // 3) Dernier joueur actif (sans équipe).
    final List<Player> alive =
        state.players.where((Player p) => !p.eliminated).toList();
    if (alive.length == 1) {
      return (
        title: '${alive.first.name} remporte la partie !',
        detail: 'Dernier joueur actif de la galaxie.'
      );
    }
    return (
      title: 'Partie terminée',
      detail: 'Les conditions de fin sont réunies.'
    );""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('game_over OK')
