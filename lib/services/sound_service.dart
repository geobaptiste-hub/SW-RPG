import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_service.dart';
import 'sound_file_service.dart';

/// Lecture de la MUSIQUE (une piste en boucle par écran) et des EFFETS
/// sonores.
///
/// Deux modes (fix web 19/09) :
///  - DESKTOP : fichiers résolus sur le disque par [SoundFileService] —
///    déposer `assets/audio/music/<écran>/<piste>.mp3` suffit, sans
///    recompilation ;
///  - WEB : les fichiers viennent du BUNDLE Flutter (déclarés dans
///    pubspec.yaml) via [AssetSource] — les .mp3 doivent être présents
///    au build (pas de dépôt à chaud possible sur le web).
///
/// Rien n'est joué si le fichier est absent ou si le réglage
/// correspondant est désactivé ; à chaque changement de piste,
/// l'ancienne musique est coupée.
class SoundController {
  final Ref ref;

  AudioPlayer? _musicPlayer;
  String? _currentTrack;

  SoundController(this.ref);

  bool get _hiveReady => Hive.isBoxOpen('settings');

  /// Source multiplateforme pour une piste musique `music/<nom>` :
  /// fichier disque sur desktop, asset du bundle sur web. Note : sur web,
  /// [AssetSource] préfixe déjà `assets/` — il faut donc passer le chemin
  /// COMPLET (`assets/audio/...`).
  Source? _musicSource(String name) {
    if (kIsWeb) {
      return AssetSource('assets/audio/music/$name.mp3');
    }
    final SoundFileService files = ref.read(soundFileServiceProvider);
    final File? file = files.resolveFile('music/$name/$name') ??
        files.resolveFile('music/$name');
    return file == null ? null : DeviceFileSource(file.path);
  }

  /// Source multiplateforme pour un effet `sfx/<nom>`.
  Source? _sfxSource(String name) {
    if (kIsWeb) {
      return AssetSource('assets/audio/sfx/$name.mp3');
    }
    final File? file = ref.read(soundFileServiceProvider).resolveFile('sfx/$name');
    return file == null ? null : DeviceFileSource(file.path);
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
      if (_currentTrack == name && _musicPlayer != null) return;
      if (!_hiveReady) return;
      final bool music =
          await ref.read(settingsServiceProvider).loadMusicEnabled();
      final bool sound =
          await ref.read(settingsServiceProvider).loadSoundEnabled();
      if (!music || !sound) {
        _currentTrack = null;
        await _musicPlayer?.stop();
        return;
      }
      // Deux emplacements acceptés : music/<écran>/<écran>.mp3 (un
      // dossier par écran) ou music/<écran>.mp3 (à plat).
      final Source? source = _musicSource(name);
      // La piste demandée est enregistrée MÊME si son fichier manque :
      // le prochain changement de piste coupera donc bien celle-ci.
      final bool wasPlaying = _currentTrack != null;
      _currentTrack = name;
      if (source == null) {
        await _musicPlayer?.stop();
        return;
      }

      _musicPlayer ??= AudioPlayer();
      await _musicPlayer!.setReleaseMode(ReleaseMode.loop);
      if (wasPlaying) {
        await _musicPlayer!.stop();
      }
      await _musicPlayer!.play(source);
    } catch (_) {
      // Silencieux : le son est optionnel (Hive indisponible en tests, pas
      // de périphérique audio, fichier illisible…).
    }
  }

  /// Coupe la musique (entrée en partie, réglage désactivé…).
  Future<void> stopMusic() async {
    _currentTrack = null;
    try {
      await _musicPlayer?.stop();
    } catch (_) {
      // Silencieux.
    }
  }

  /// Joue un effet sonore `assets/audio/sfx/<name>` (si activé et si le
  /// fichier existe). Le player est libéré après la lecture.
  Future<void> playSfx(String name) async {
    if (!_hiveReady) return;
    try {
      final bool sound =
          await ref.read(settingsServiceProvider).loadSoundEnabled();
      if (!sound) return;
      final Source? source = _sfxSource(name);
      if (source == null) return;
      final AudioPlayer player = AudioPlayer();
      await player.play(source);
      player.onPlayerComplete.first.then((_) {
        player.dispose();
      });
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
