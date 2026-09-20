import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/router/app_router.dart';
import 'services/settings_service.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive (sauvegarde de partie + réglages) — initialisé avant tout accès
  // aux boxes (SaveService, SettingsService).
  await Hive.initFlutter();

  // Plein écran au démarrage sur desktop (retours playtest : l'app visait
  // une fenêtre réduite). Ignoré sur mobile/tablette, où le plein écran
  // est natif. Réglage persisté : désactivable dans les Paramètres.
  if (!kIsWeb && (!kIsWeb)) {
    await windowManager.ensureInitialized();
    final bool fullScreen =
        await SettingsService().loadFullScreenEnabled();
    WindowOptions options = WindowOptions(fullScreen: fullScreen);
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: StarWarsRpgApp()));
}

class StarWarsRpgApp extends StatelessWidget {
  const StarWarsRpgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Star Wars RPG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: appRouter,
    );
  }
}
