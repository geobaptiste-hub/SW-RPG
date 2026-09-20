// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Ce fichier n'est chargé QUE sur web (import conditionnel depuis
// sound_backend.dart) — dart:html y est donc légitime.
import 'dart:html' as html;

/// Backend audio WEB (iPad/navigateurs) : éléments <audio> simples.
///
/// On ne passe PAS par audioplayers sur le web : sa implémentation 4.x
/// route le son via un AudioContext WebAudio créé hors geste utilisateur,
/// qui reste suspendu (politique autoplay) et jamais repris → silence.
/// Un élément <audio> direct joue normalement dès qu'un geste utilisateur
/// a déclenché son premier play().
class SoundBackend {
  html.AudioElement? _loop;

  /// Musique en boucle : coupe la boucle précédente puis joue [url]
  /// (chemin relatif à la page, ex. `assets/assets/audio/music/…`).
  Future<void> playLoop(String url) async {
    await stopLoop();
    final html.AudioElement element = html.AudioElement(url)
      ..loop = true
      ..volume = 1;
    _loop = element;
    try {
      await element.play();
    } catch (_) {
      // Autoplay bloqué avant geste : resumeLoop() reprendra au premier
      // toucher de l'utilisateur.
    }
  }

  /// Reprise de la boucle courante (appelée au premier toucher — les
  /// navigateurs exigent un geste utilisateur pour autoriser le son).
  Future<void> resumeLoop() async {
    final html.AudioElement? loop = _loop;
    if (loop == null) return;
    try {
      if (loop.paused) {
        await loop.play();
      }
    } catch (_) {
      // Toujours bloqué : l'utilisateur retouchera l'écran.
    }
  }

  Future<void> stopLoop() async {
    final html.AudioElement? loop = _loop;
    _loop = null;
    if (loop == null) return;
    try {
      loop.pause();
      loop.remove();
    } catch (_) {
      // Déjà retiré.
    }
  }

  /// Effet sonore : élément éphémère retiré après la lecture.
  Future<void> playOnce(String url) async {
    final html.AudioElement element = html.AudioElement(url);
    try {
      await element.play();
    } catch (_) {
      element.remove();
      return;
    }
    element.onEnded.first.whenComplete(() {
      element.remove();
    });
  }
}
