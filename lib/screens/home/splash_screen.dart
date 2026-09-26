import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/app_background.dart';

/// Splash de démarrage (retours playtest 20/09) : affiché 1 seconde au
/// lancement du jeu puis bascule sur l'accueil.
///
/// Image attendue : `assets/images/screens/splash.jpg` (ou .png) — sans
/// image déposée : fond sombre + logo texte doré.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 1), () {
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Retours playtest 20/09 : l'image seule (pas de texte superposé —
    // l'image déposée fait déjà office de logo).
    return Scaffold(
      body: AppBackground(
        imageId: 'screens/splash',
        child: const SizedBox.expand(),
      ),
    );
  }
}
