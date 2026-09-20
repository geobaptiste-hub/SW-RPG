import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Réglages de l'application (Sprint 6 — écran Paramètres) : persistés
/// dans une box Hive distincte de la sauvegarde de partie.
class SettingsService {
  static const String _boxName = 'settings';
  static const String _soundKey = 'sound';
  static const String _musicKey = 'music';
  static const String _fullScreenKey = 'fullscreen';

  /// Effets sonores activés ? (valeur par défaut : vrai ; tout échec de
  /// stockage retombe silencieusement sur la valeur par défaut.)
  Future<bool> loadSoundEnabled() async {
    try {
      final Box<bool> box = await Hive.openBox<bool>(_boxName);
      return box.get(_soundKey, defaultValue: true) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setSoundEnabled(bool value) async {
    try {
      final Box<bool> box = await Hive.openBox<bool>(_boxName);
      await box.put(_soundKey, value);
    } catch (_) {
      // Stockage indisponible : le réglage restera valable pour la session.
    }
  }

  /// Musique activée ? (valeur par défaut : vrai.)
  Future<bool> loadMusicEnabled() async {
    try {
      final Box<bool> box = await Hive.openBox<bool>(_boxName);
      return box.get(_musicKey, defaultValue: true) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setMusicEnabled(bool value) async {
    try {
      final Box<bool> box = await Hive.openBox<bool>(_boxName);
      await box.put(_musicKey, value);
    } catch (_) {
      // Stockage indisponible : le réglage restera valable pour la session.
    }
  }

  /// Plein écran au démarrage (desktop — retours playtest : en plein écran
  /// il n'y a plus de croix de fenêtre, il faut pouvoir le désactiver).
  Future<bool> loadFullScreenEnabled() async {
    try {
      final Box<bool> box = await Hive.openBox<bool>(_boxName);
      return box.get(_fullScreenKey, defaultValue: true) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setFullScreenEnabled(bool value) async {
    try {
      final Box<bool> box = await Hive.openBox<bool>(_boxName);
      await box.put(_fullScreenKey, value);
    } catch (_) {
      // Stockage indisponible : le réglage restera valable pour la session.
    }
  }
}

final settingsServiceProvider =
    Provider<SettingsService>((ref) => SettingsService());

/// État réactif du réglage « Effets sonores » (chargé de façon asynchrone
/// au premier accès, puis persisté à chaque bascule).
final soundEnabledProvider =
    NotifierProvider<SoundEnabledController, bool>(SoundEnabledController.new);

/// État réactif du réglage « Musique » (persisté, appliqué en direct).
final musicEnabledProvider =
    NotifierProvider<MusicEnabledController, bool>(MusicEnabledController.new);

class MusicEnabledController extends Notifier<bool> {
  @override
  bool build() {
    ref.read(settingsServiceProvider).loadMusicEnabled().then((bool value) {
      try {
        if (state != value) state = value;
      } catch (_) {
        // Provider disposé entre-temps.
      }
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsServiceProvider).setMusicEnabled(value);
  }
}

/// État réactif du réglage « Plein écran » (desktop — applique la valeur
/// à la fenêtre en direct, et la persiste pour le prochain démarrage).
final fullScreenProvider =
    NotifierProvider<FullScreenController, bool>(FullScreenController.new);

class FullScreenController extends Notifier<bool> {
  @override
  bool build() {
    ref.read(settingsServiceProvider).loadFullScreenEnabled().then((bool value) {
      try {
        if (state != value) state = value;
      } catch (_) {
        // Provider disposé entre-temps.
      }
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    if (!kIsWeb && (!kIsWeb)) {
      await windowManager.setFullScreen(value);
    }
    await ref.read(settingsServiceProvider).setFullScreenEnabled(value);
  }
}

class SoundEnabledController extends Notifier<bool> {
  @override
  bool build() {
    ref.read(settingsServiceProvider).loadSoundEnabled().then((bool value) {
      try {
        if (state != value) state = value;
      } catch (_) {
        // Le provider a été disposé entre-temps : rien à mettre à jour.
      }
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsServiceProvider).setSoundEnabled(value);
  }
}
