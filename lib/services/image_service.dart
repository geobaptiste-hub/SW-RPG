import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Résolution des images de cartes (Sprint 6 — convention
/// `SW/MD/images-cartes.md` : `assets/images/<catégorie>/<id>.png`).
///
/// Les images sont lues depuis le SYSTÈME DE FICHIERS (pas le bundle
/// Flutter) : le game design peut déposer/ajouter des PNG dans le dossier
/// `assets/images/` du projet et ils apparaissent SANS recompilation.
/// [roots] est injectable pour les tests.
class ImageService {
  /// Racines candidates, dans l'ordre : répertoire courant, puis les
  /// parents du répertoire de l'exécutable (l'exe vit dans
  /// `build/windows/x64/runner/Debug`, le projet 4 niveaux plus haut).
  final List<String> roots;

  /// Cache des chemins résolus (évite un existsSync par rebuild).
  final Map<String, File?> _cache = <String, File?>{};

  ImageService({List<String>? roots}) : roots = roots ?? _defaultRoots();

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

  /// Le fichier image `category/id` s'il existe (première extension
  /// trouvée parmi .png/.jpg/.jpeg — les JPEG déposés sont acceptés),
  /// sinon null.
  File? resolveFile(String category, String id) {
    final String key = '$category/$id';
    if (_cache.containsKey(key)) return _cache[key];
    File? found;
    loop:
    for (final String root in roots) {
      final String base =
          '$root${root.endsWith('/') ? '' : '/'}'
          'assets${'/'}images${'/'}'
          '$category${'/'}$id';
      for (final String ext in const <String>['.png', '.jpg', '.jpeg']) {
        final File candidate = File(base + ext);
        if (candidate.existsSync()) {
          found = candidate;
          break loop;
        }
      }
    }
    _cache[key] = found;
    return found;
  }

  /// Invalide le cache (utile si des images sont déposées en cours de jeu).
  void clearCache() => _cache.clear();

  /// Résout une image par chemin relatif direct sous `assets/images/`
  /// (ex. `screens/accueil`), en essayant .png/.jpg/.jpeg. Null si aucune
  /// trouvée. Résultat mis en cache comme [resolveFile].
  File? resolveImage(String relativePath) {
    if (_cache.containsKey(relativePath)) return _cache[relativePath];
    File? found;
    loop:
    for (final String root in roots) {
      final String base =
          '$root${root.endsWith('/') ? '' : '/'}'
          'assets${'/'}images${'/'}'
          '$relativePath';
      for (final String ext in const <String>['.png', '.jpg', '.jpeg']) {
        final File candidate = File(base + ext);
        if (candidate.existsSync()) {
          found = candidate;
          break loop;
        }
      }
    }
    _cache[relativePath] = found;
    return found;
  }
}

final imageServiceProvider =
    Provider<ImageService>((ref) => ImageService());
