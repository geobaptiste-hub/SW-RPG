import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart'
    show AssetManifest, rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_service.dart';
import 'sound_backend.dart';
import 'sound_file_service.dart';

/// Lecture de la MUSIQUE (une piste en boucle par écran) et des EFFETS
/// sonores.
///
/// Deux modes (fix web 20/09 — voir [SoundBackend]) :
///  - DESKTOP : fichiers résolus sur le disque par [SoundFileService] —
///    déposer `assets/audio/music/<écran>/<piste>.mp3` suffit, sans
///    recompilation ;
///  - WEB : les fichiers viennent du BUNDLE Flutter (déclarés dans
///    pubspec.yaml), joués par des éléments <audio> directs.
///
/// Rien n'est joué si le fichier est absent ou si le réglage
/// correspondant est désactivé ; à chaque changement de piste,
/// l'ancienne musique est coupée.
class SoundController {
  final Ref ref;

  final SoundBackend _backend = SoundBackend();
  String? _currentTrack;
  String? _currentLoopUrl;

  SoundController(this.ref);

  bool get _hiveReady => Hive.isBoxOpen('settings');

  /// Clés des assets du bundle (web — chargées une fois) : permet de
  /// choisir entre les deux conventions de dépôt possibles.
  Set<String>? _bundledAssets;

  Future<void> _ensureBundleManifest() async {
    if (!kIsWeb || _bundledAssets != null) return;
    try {
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      _bundledAssets = manifest.listAssets().toSet();
    } catch (_) {
      _bundledAssets = null;
    }
  }

  /// Web : première clé candidate réellement présente dans le bundle.
  /// Les clés du manifest incluent le préfixe `assets/` (ce sont les
  /// chemins déclarés dans pubspec) ; l'URL servie vaut `assets/` + clé.
  String? _bundledAudioUrl(List<String> candidateKeys) {
    final Set<String>? keys = _bundledAssets;
    if (keys == null) return 'assets/${candidateKeys.first}';
    for (final String key in candidateKeys) {
      if (keys.contains(key)) return 'assets/$key';
    }
    return null;
  }

  /// URL/chemin d'une piste musique `music/<nom>` : chemin absolu du
  /// fichier (desktop, null si absent) ou URL relative du bundle (web).
  /// Deux conventions de dépôt acceptées : `music/<nom>/<nom>.mp3`
  /// (dossier dédié — écrans) ou `music/<nom>.mp3` (à plat — planètes).
  Future<String?> _musicUrl(String name) async {
    if (kIsWeb) {
      await _ensureBundleManifest();
      return _bundledAudioUrl(<String>[
        'assets/audio/music/$name/$name.mp3',
        'assets/audio/music/$name.mp3',
      ]);
    }
    final SoundFileService files = ref.read(soundFileServiceProvider);
    final File? file = files.resolveFile('music/$name/$name') ??
        files.resolveFile('music/$name');
    return file?.path;
  }

  /// URL/chemin d'un effet `sfx/<nom>`.
  Future<String?> _sfxUrl(String name) async {
    if (kIsWeb) {
      await _ensureBundleManifest();
      return _bundledAudioUrl(<String>['assets/audio/sfx/$name.mp3']);
    }
    final File? file =
        ref.read(soundFileServiceProvider).resolveFile('sfx/$name');
    return file?.path;
  }

  /// Joue en boucle la musique d'un écran : `accueil`, `credits`,
  /// `parametres`, `preparation`, `planetes/hoth`, `lieux/cantina`…
  /// Sans effet si la piste est déjà en cours (évite de la redémarrer à
  /// chaque rebuild). FIX 19/09 : si le fichier de la nouvelle piste
  /// manque (ou si le réglage est coupé), la musique PRÉCÉDENTE est
  /// coupée — sans ça, elle continuait indéfiniment (ex. la musique de
  /// la cantina qui jouait encore après la sortie).
  Future<void> playScreenMusic(String name) async {
    try {
      if (_currentTrack == name && _currentLoopUrl != null) return;
      if (!_hiveReady) return;
      final bool music =
          await ref.read(settingsServiceProvider).loadMusicEnabled();
      final bool sound =
          await ref.read(settingsServiceProvider).loadSoundEnabled();
      if (!music || !sound) {
        _currentTrack = null;
        _currentLoopUrl = null;
        await _backend.stopLoop();
        return;
      }
      // Deux emplacements acceptés : music/<écran>/<écran>.mp3 (un
      // dossier par écran) ou music/<écran>.mp3 (à plat).
      final String? url = await _musicUrl(name);
      // La piste demandée est enregistrée MÊME si son fichier manque :
      // le prochain changement de piste coupera donc bien celle-ci.
      _currentTrack = name;
      _currentLoopUrl = url;
      if (url == null) {
        await _backend.stopLoop();
        return;
      }
      await _backend.playLoop(url);
    } catch (_) {
      // Silencieux : le son est optionnel (Hive indisponible en tests, pas
      // de périphérique audio, fichier illisible…).
    }
  }

  /// WEB uniquement : l'autoplay est bloqué avant la première interaction
  /// — la musique lancée au chargement reste muette. Appelé au premier
  /// toucher de l'utilisateur (écran Accueil) : reprend la boucle
  /// courante. No-op sur desktop.
  Future<void> resumeWebAudio() async {
    await _backend.resumeLoop();
  }

  /// Coupe la musique (entrée en partie, réglage désactivé…).
  Future<void> stopMusic() async {
    _currentTrack = null;
    _currentLoopUrl = null;
    await _backend.stopLoop();
  }

  /// Joue un effet sonore `assets/audio/sfx/<name>` (si activé et si le
  /// fichier existe).
  Future<void> playSfx(String name) async {
    if (!_hiveReady) return;
    try {
      final bool sound =
          await ref.read(settingsServiceProvider).loadSoundEnabled();
      if (!sound) return;
      final String? url = await _sfxUrl(name);
      if (url == null) return;
      await _backend.playOnce(url);
    } catch (_) {
      // Silencieux : le son est optionnel (Hive indisponible en tests, pas
      // de périphérique audio, fichier illisible…).
    }
  }
}

/// Contrôleur audio unique (la musique d'accueil et les SFX partagent les
/// réglages — voir [soundEnabledProvider] et [musicEnabledProvider]).
final soundControllerProvider =
    Provider<SoundController>((ref) => SoundController(ref));
