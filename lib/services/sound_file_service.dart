import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lecture des fichiers audio déposés SANS recompilation (comme les
/// images) : `assets/audio/music/<nom>.mp3` et `assets/audio/sfx/<nom>.mp3`.
/// Mêmes racines candidates que [ImageService] (répertoire courant +
/// parents de l'exécutable).
class SoundFileService {
  final List<String> roots;

  final Map<String, File?> _cache = <String, File?>{};

  SoundFileService({List<String>? roots}) : roots = roots ?? _defaultRoots();

  static List<String> _defaultRoots() {
    final List<String> roots = <String>[Directory.current.path];
    try {
      FileSystemEntity directory = File('').parent;
      for (int i = 0; i < 6; i++) {
        roots.add(directory.path);
        directory = directory.parent;
      }
    } on FileSystemException {
      // Plateforme sans resolvedExecutable : le répertoire courant suffit.
    }
    return roots;
  }

  /// Le fichier audio `assets/audio/<relative>` s'il existe, sinon null.
  /// [relative] exclut l'extension (la première trouvée parmi .mp3/.wav/.ogg
  /// est retournée).
  File? resolveFile(String relative) {
    if (_cache.containsKey(relative)) return _cache[relative];
    File? found;
    const List<String> extensions = <String>['.mp3', '.wav', '.ogg'];
    loop:
    for (final String root in roots) {
      final String base =
          '$root${root.endsWith('/') ? '' : '/'}'
          'assets${'/'}audio${'/'}'
          '$relative';
      for (final String ext in extensions) {
        final File candidate = File(base + ext);
        if (candidate.existsSync()) {
          found = candidate;
          break loop;
        }
      }
    }
    _cache[relative] = found;
    return found;
  }

  void clearCache() => _cache.clear();
}

final soundFileServiceProvider =
    Provider<SoundFileService>((ref) => SoundFileService());
