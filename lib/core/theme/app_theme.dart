import 'package:flutter/material.dart';

import '../constants/enums.dart';
import '../../models/player.dart';

/// Palette et thème global de l'application (ambiance « espace Star Wars »).
class AppColors {
  AppColors._();

  // Couleurs de base de l'interface.
  static const Color background = Color(0xFF0A0D18);
  static const Color surface = Color(0xFF121828);
  static const Color card = Color(0xFF1A2138);
  static const Color gold = Color(0xFFFFD54F);
  static const Color blue = Color(0xFF4FC3F7);
  static const Color textPrimary = Color(0xFFE8ECF4);
  static const Color textSecondary = Color(0xFF9AA5B8);
  static const Color danger = Color(0xFFEF5350);

  /// Couleurs des 8 pions joueurs (indexés par position dans la liste des
  /// joueurs ; l'ordre est stable car conservé dans la sauvegarde).
  static const List<Color> playerTokens = [
    Color(0xFFEF5350), // rouge
    Color(0xFF42A5F5), // bleu
    Color(0xFF66BB6A), // vert
    Color(0xFFFFEE58), // jaune
    Color(0xFFAB47BC), // violet
    Color(0xFFFF7043), // orange
    Color(0xFF26C6DA), // cyan
    Color(0xFFEC407A), // rose
  ];

  static Color playerTokenColor(int playerIndex) =>
      playerTokens[playerIndex % playerTokens.length];

  /// Couleurs des factions (Empire, Sith, Rebel, Jedi — GDD addendum).
  static const Map<Faction, Color> factions = {
    Faction.empire: Color(0xFF90A4AE),
    Faction.sith: Color(0xFFE53935),
    Faction.rebel: Color(0xFFFB8C00),
    Faction.jedi: Color(0xFF42A5F5),
  };

  static Color factionColor(Faction faction) => factions[faction]!;

  /// Couleurs des équipes des modes à équipes (Équipes, Big Four).
  static const Map<TeamSide, Color> teams = {
    TeamSide.teamA: Color(0xFF42A5F5), // bleu
    TeamSide.teamB: Color(0xFFEF5350), // rouge
    TeamSide.teamC: Color(0xFF66BB6A), // vert
    TeamSide.teamD: Color(0xFFAB47BC), // violet
  };

  static Color teamColor(TeamSide side) => teams[side]!;

  /// Couleurs standard de rareté (choix d'interface, non spécifié par le GDD).
  static const Map<Rarity, Color> rarities = {
    Rarity.commun: Color(0xFF9E9E9E),
    Rarity.rare: Color(0xFF42A5F5),
    Rarity.epique: Color(0xFFAB47BC),
    Rarity.legendaire: Color(0xFFFFD54F),
    Rarity.mythique: Color(0xFFEF5350),
  };

  static Color rarityColor(Rarity rarity) => rarities[rarity]!;

  /// Couleur de surbrillance des cases de déplacement valides.
  static const Color moveHighlight = Color(0xFF69F0AE);
}

/// Thème Material sombre de l'application.
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      brightness: Brightness.dark,
      primary: AppColors.gold,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.card,
      dividerColor: Colors.white12,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.gold,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
        ),
        headlineSmall: TextStyle(color: AppColors.textPrimary),
        titleLarge: TextStyle(color: AppColors.textPrimary),
        titleMedium: TextStyle(color: AppColors.textPrimary),
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textSecondary),
        labelLarge: TextStyle(color: AppColors.textPrimary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: Colors.white10),
        ),
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black87,
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Colors.white24),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.card,
        selectedColor: AppColors.gold,
        labelStyle: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }
}
