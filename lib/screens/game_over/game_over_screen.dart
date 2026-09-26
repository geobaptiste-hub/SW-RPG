import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart'
    show GameMode, GameStatus, TeamSide;
import '../../core/constants/game_constants.dart';
import '../../core/constants/planet_constants.dart' show PlanetConstants;
import '../../core/theme/app_theme.dart';
import '../../models/boss.dart' show BossType;
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/game_service.dart';
import '../../widgets/app_background.dart';
import '../../widgets/screen_music.dart';

/// Résultat du décompte de victoire : titre affiché, explication, et
/// côté du gagnant (true = lumineux Rebel/Jedi, false = sombre
/// Empire/Sith) — pilote l'image et la musique de la fin
/// (retours playtest : fins lumineuse/sombre).
typedef WinnerResolution = ({String title, String detail, bool lightSide});

/// Côté lumineux : Rebel et Jedi.
bool factionIsLight(Faction faction) =>
    faction == Faction.rebel || faction == Faction.jedi;

/// Écran de fin de partie (CDC §17, Sprint 5) : gagnant, statistiques de la
/// partie (tour final, temps de jeu, palmarès des joueurs) et boutons de
/// sortie. La partie est close à la sortie (aucune reprise possible d'une
/// partie terminée).
class GameOverScreen extends ConsumerWidget {
  const GameOverScreen({super.key});

  /// Détermine le gagnant à partir de l'état final (miroir des règles de
  /// GameController._checkVictoryConditions / _applySurvivorCheck).
  static WinnerResolution resolveWinner(GameState state) {
    // Big Four (retours playtest 20/09) : les équipes étant mono-faction,
    // le titre annonce la FACTION gagnante au lieu de la lettre d'équipe.
    Faction winningFaction(List<Player> members) {
      final Map<Faction, int> counts = <Faction, int>{};
      for (final Player p in members) {
        counts[p.faction] = (counts[p.faction] ?? 0) + 1;
      }
      Faction best = members.first.faction;
      for (final MapEntry<Faction, int> entry in counts.entries) {
        if (entry.value > counts[best]!) best = entry.key;
      }
      return best;
    }

    String teamTitle(List<Player> members) =>
        state.mode == GameMode.bigFour
            ? 'La faction ${winningFaction(members).displayName} remporte '
                'la partie !'
            : 'L’équipe ${members.first.team!.displayName} remporte la '
                'partie !';

    if (state.mode == GameMode.chacunPourSoi) {
      // 1) Victoire par objectifs : 3 boss de factions adverses.
      for (final Player player in state.players) {
        final int adverse = player.defeatedBosses
            .where((BossType boss) =>
                PlanetConstants.bossFactionByType[boss] != player.faction)
            .toSet()
            .length;
        if (adverse >= GameConstants.bossesToWin) {
          return (
            title: '${player.name} remporte la partie !',
            detail:
                'Victoire par objectifs : $adverse boss de factions adverses '
                'ont été vaincus.',
            lightSide: factionIsLight(player.faction),
          );
        }
      }
      // 2) Dernier survivant.
      final List<Player> alive =
          state.players.where((Player p) => !p.eliminated).toList();
      if (alive.length == 1) {
        return (
          title: '${alive.first.name} remporte la partie !',
          detail: 'Dernier survivant de la galaxie.',
          lightSide: factionIsLight(alive.first.faction),
        );
      }
      return (
        title: 'Partie terminée',
        detail: 'Plus aucun joueur actif sur l’échiquier galactique.',
        lightSide: true,
      );
    }

    // Modes à équipes (Équipes, Big Four) — générique à N équipes.
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
        final int lightMembers = members
            .where((Player p) => factionIsLight(p.faction))
            .length;
        return (
          title: teamTitle(members),
          detail: 'Victoire par objectifs : $adverse boss adverses vaincus '
              'par l’équipe.',
          lightSide: lightMembers * 2 >= members.length,
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
      final List<Player> members =
          state.players.where((Player p) => p.team == winner).toList();
      final int lightMembers = members
          .where((Player p) => factionIsLight(p.faction))
          .length;
      return (
        title: teamTitle(members),
        detail: 'Dernière équipe debout de la galaxie.',
        lightSide: lightMembers * 2 >= members.length,
      );
    }
    // 3) Dernier joueur actif (sans équipe).
    final List<Player> alive =
        state.players.where((Player p) => !p.eliminated).toList();
    if (alive.length == 1) {
      return (
        title: '${alive.first.name} remporte la partie !',
        detail: 'Dernier joueur actif de la galaxie.',
        lightSide: factionIsLight(alive.first.faction),
      );
    }
    return (
      title: 'Partie terminée',
      detail: 'Les conditions de fin sont réunies.',
      lightSide: true,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameState? state = ref.watch(gameControllerProvider);
    if (state == null) {
      // Garde-fou : partie déjà close (ou quittée) → accueil.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.status != GameStatus.finished) {
      // Garde-fou : la partie n'est pas terminée → retour au plateau.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/board');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final WinnerResolution winner = resolveWinner(state);
    final TextTheme textTheme = Theme.of(context).textTheme;

    final bool lightSide = winner.lightSide;
    final String endTrack = lightSide ? 'fin_lumineuse' : 'fin_sombre';

    // Fix 19/09 : lisibilité sur les images de fin (flames vives / scène
    // claire) — voile sombre derrière le bloc de texte + ombres portées,
    // comme le voile de l'accueil.
    const List<Shadow> endTextShadows = <Shadow>[
      Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 2)),
    ];

    return Scaffold(
      body: AppBackground(
        imageId: 'screens/game_over/'
            '${lightSide ? 'fin_lumineuse' : 'fin_sombre'}',
        child: ScreenMusic(
        track: endTrack,
        child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.emoji_events,
                      size: 72,
                      color: lightSide
                          ? const Color(0xFF4FC3F7)
                          : const Color(0xFFCE93D8)),
                  const SizedBox(height: 12),
                  Text(
                      lightSide
                          ? '✨ La Force lumineuse l’emporte !'
                          : '☾ Le Côté Obscur l’emporte !',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                          color: lightSide
                              ? const Color(0xFF4FC3F7)
                              : const Color(0xFFCE93D8),
                          fontWeight: FontWeight.w800,
                          shadows: endTextShadows)),
                  const SizedBox(height: 8),
                  Text('Partie terminée !',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white, shadows: endTextShadows)),
                  const SizedBox(height: 8),
                  Text(winner.title,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                          shadows: endTextShadows)),
                  const SizedBox(height: 4),
                  Text(winner.detail,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          shadows: endTextShadows)),
                  const SizedBox(height: 20),
                  _StatsCard(state: state),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Nouvelle partie'),
                    onPressed: () {
                      ref.read(gameControllerProvider.notifier).exitGame();
                      context.go('/new-game');
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.home_outlined),
                    label: const Text("Retour à l’accueil"),
                    onPressed: () {
                      ref.read(gameControllerProvider.notifier).exitGame();
                      context.go('/');
                    },
                  ),
                ],
              ),
            ),
          ),
)
),
),
        ),
);
  }
}

/// Carte de statistiques de fin de partie : configuration, tour final,
/// temps de jeu et palmarès de chaque joueur.
class _StatsCard extends StatelessWidget {
  final GameState state;

  const _StatsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(state.mode.displayName, style: textTheme.titleMedium),
                Text('Tour ${state.turn} · ${state.formattedGameTime}',
                    style: textTheme.bodyMedium),
              ],
            ),
            const Divider(height: 24),
            for (final Player player in state.players)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        player.eliminated
                            ? '${player.name} (éliminé)'
                            : player.name,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          color: player.eliminated
                              ? AppColors.textSecondary
                              : null,
                          decoration: player.eliminated
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Niv. ${player.level} · ${player.xp} XP · '
                      '${player.defeatedBosses.length} boss',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
