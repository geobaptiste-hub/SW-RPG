import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/board/board_screen.dart';
import '../../screens/combat/combat_screen.dart';
import '../../screens/character/character_screen.dart';
import '../../screens/game_over/game_over_screen.dart';
import '../../screens/home/credits_screen.dart';
import '../../screens/journal/journal_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/home/settings_screen.dart';
import '../../screens/home/splash_screen.dart';
import '../../screens/inventory/inventory_screen.dart';
import '../../screens/new_game/new_game_screen.dart';
import '../../screens/players/players_screen.dart';
import '../../screens/team/team_screen.dart';

/// Configuration GoRouter (Architecture v1.0 — Navigation) :
/// Splash (1 s) → Accueil → Nouvelle Partie → Plateau → (Combat — Sprint 3) →
/// Fin de partie (Sprint 5).
///
/// Les écrans Personnage / Équipe / Inventaire / Joueurs sont des routes de
/// premier niveau : ils sont ouverts depuis la barre bas du plateau (CDC §10)
/// et reviennent au plateau via /board.
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      builder: (BuildContext context, GoRouterState state) =>
          const SplashScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const HomeScreen(),
    ),
    GoRoute(
      path: '/new-game',
      builder: (BuildContext context, GoRouterState state) =>
          const NewGameScreen(),
    ),
    GoRoute(
      path: '/board',
      builder: (BuildContext context, GoRouterState state) =>
          const BoardScreen(),
    ),
    GoRoute(
      path: '/character',
      builder: (BuildContext context, GoRouterState state) =>
          const CharacterScreen(),
    ),
    GoRoute(
      path: '/combat',
      builder: (BuildContext context, GoRouterState state) =>
          const CombatScreen(),
    ),
    GoRoute(
      path: '/game-over',
      builder: (BuildContext context, GoRouterState state) =>
          const GameOverScreen(),
    ),
    GoRoute(
      path: '/team',
      builder: (BuildContext context, GoRouterState state) =>
          const TeamScreen(),
    ),
    GoRoute(
      path: '/inventory',
      builder: (BuildContext context, GoRouterState state) =>
          const InventoryScreen(),
    ),
    GoRoute(
      path: '/players',
      builder: (BuildContext context, GoRouterState state) =>
          const PlayersScreen(),
    ),
    GoRoute(
      path: '/journal',
      builder: (BuildContext context, GoRouterState state) =>
          const JournalScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
    ),
    GoRoute(
      path: '/credits',
      builder: (BuildContext context, GoRouterState state) =>
          const CreditsScreen(),
    ),
  ],
);
