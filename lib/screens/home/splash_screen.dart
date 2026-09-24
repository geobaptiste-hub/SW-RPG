import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
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
    return Scaffold(
      body: AppBackground(
        imageId: 'screens/splash',
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'STAR WARS',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'R P G',
                style: TextStyle(
                  color: AppColors.blue,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
