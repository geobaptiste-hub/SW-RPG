import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_service.dart';
import 'sound_file_service.dart';

/// Lecture de la MUSIQUE (une piste en boucle par écran) et des EFFETS
/// sonores.
///
/// Les fichiers sont résolus sur le disque par [SoundFileService] :
/// déposer `assets/audio/music/<écran>/<piste>.mp3` suffit, sans
/// recompilation. Rien n'est joué si le fichier est absent ou si le
/// réglage correspondant est désactivé.
class SoundController {
  final Ref ref;

  AudioPlayer? _musicPlayer;
  String? _currentTrack;

  SoundController(this.ref);

  bool get _hiveReady => Hive.isBoxOpen('settings');

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
      final File? file = ref
              .read(soundFileServiceProvider)
              .resolveFile('music/$name/$name') ??
          ref.read(soundFileServiceProvider).resolveFile('music/$name');
      // La piste demandée est enregistrée MÊME si son fichier manque :
      // le prochain changement de piste coupera donc bien celle-ci.
      final bool wasPlaying = _currentTrack != null;
      _currentTrack = name;
      if (file == null) {
        await _musicPlayer?.stop();
        return;
      }

      _musicPlayer ??= AudioPlayer();
      await _musicPlayer!.setReleaseMode(ReleaseMode.loop);
      if (wasPlaying) {
        await _musicPlayer!.stop();
      }
      await _musicPlayer!.play(DeviceFileSource(file.path));
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
      final File? file =
          ref.read(soundFileServiceProvider).resolveFile('sfx/$name');
      if (file == null) return;
      final AudioPlayer player = AudioPlayer();
      await player.play(DeviceFileSource(file.path));
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
