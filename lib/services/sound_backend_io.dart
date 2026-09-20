import 'package:audioplayers/audioplayers.dart';

/// Backend audio DESKTOP (Windows…) : audioplayers, fichiers sur le
/// disque (chemins absolus résolus par SoundFileService).
class SoundBackend {
  AudioPlayer? _loop;

  /// Musique en boucle : coupe la boucle précédente puis joue [filePath].
  Future<void> playLoop(String filePath) async {
    await stopLoop();
    final AudioPlayer player = _loop = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(DeviceFileSource(filePath));
  }

  /// Reprise après autoplay bloqué : sans objet sur desktop (pas de
  /// politique d'autoplay). Les boucles ne se coupent pas toutes seules.
  Future<void> resumeLoop() async {}

  Future<void> stopLoop() async {
    final AudioPlayer? player = _loop;
    _loop = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {
      // Déjà libéré.
    }
  }

  /// Effet sonore : lecteur éphémère libéré après la lecture.
  Future<void> playOnce(String filePath) async {
    final AudioPlayer player = AudioPlayer();
    try {
      await player.play(DeviceFileSource(filePath));
      player.onPlayerComplete.first.then((_) {
        player.dispose();
      });
    } catch (_) {
      await player.dispose();
    }
  }
}
