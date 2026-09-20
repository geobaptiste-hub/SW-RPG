import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show AssetImage, FileImage, ImageProvider;
import 'package:flutter/services.dart'
    show AssetManifest, rootBundle;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Résolution des images de cartes (Sprint 6 — convention
/// `SW/MD/images-cartes.md` : `assets/images/<catégorie>/<id>.png`).
///
/// Deux modes (fix web 19/09) :
///  - DESKTOP (Windows…) : les images sont lues depuis le SYSTÈME DE
///    FICHIERS (pas le bundle Flutter) — le game design dépose/ajoute des
///    fichiers dans `assets/images/` et ils apparaissent SANS
///    recompilation ;
///  - WEB (iPad via Flutter Web) : pas de système de fichiers — les
///    images viennent du BUNDLE Flutter (dossiers déclarés dans
///    pubspec.yaml, section `assets:`) et [providerFor] /
///    [backgroundProvider] renvoient une [AssetImage]. Si l'image n'est
///    pas dans le bundle, les `errorBuilder` des widgets affichent le
///    repli habituel (icône/initiale).
class ImageService {
  /// Racines candidates, dans l'ordre : répertoire courant, puis les
  /// parents du répertoire de l'exécutable (l'exe vit dans
  /// `build/windows/x64/runner/Debug`, le projet 4 niveaux plus haut).
  final List<String> roots;

  /// Cache des chemins résolus (évite un existsSync par rebuild).
  final Map<String, File?> _cache = <String, File?>{};

  ImageService({List<String>? roots}) : roots = roots ?? _defaultRoots();

  static List<String> _defaultRoots() {
    // Sur web : pas de système de fichiers, [providerFor] est utilisé.
    if (kIsWeb) return const <String>[];
    final List<String> roots = <String>[Directory.current.path];
    try {
      FileSystemEntity directory = File(Platform.resolvedExecutable).parent;
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
  /// sinon null. Desktop uniquement (null sur web).
  File? resolveFile(String category, String id) {
    if (kIsWeb) return null;
    final String key = '$category/$id';
    if (_cache.containsKey(key)) return _cache[key];
    File? found;
    loop:
    for (final String root in roots) {
      final String base =
          '$root${root.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}'
          'assets${Platform.pathSeparator}images${Platform.pathSeparator}'
          '$category${Platform.pathSeparator}$id';
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
  /// trouvée. Desktop uniquement (null sur web).
  File? resolveImage(String relativePath) {
    if (kIsWeb) return null;
    if (_cache.containsKey(relativePath)) return _cache[relativePath];
    File? found;
    loop:
    for (final String root in roots) {
      final String base =
          '$root${root.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}'
          'assets${Platform.pathSeparator}images${Platform.pathSeparator}'
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

  /// ImageProvider multiplateforme pour `category/id` (fix web 19/09) :
  ///  - desktop : [FileImage] si le fichier est déposé, sinon null (le
  ///    widget affiche son repli) ;
  ///  - web : [AssetImage] sur le chemin du bundle — l'extension est
  ///    choisie via le manifest d'assets (.png/.jpg/.jpeg), et si
  ///    l'image n'y est pas, l'`errorBuilder` du widget prend le relais.
  ImageProvider? providerFor(String category, String id) {
    if (kIsWeb) {
      return AssetImage(_bundledPath('assets/images/$category/$id') ??
          'assets/images/$category/$id.png');
    }
    final File? file = resolveFile(category, id);
    return file == null ? null : FileImage(file);
  }

  /// ImageProvider multiplateforme pour un chemin relatif direct
  /// (`screens/accueil`, `screens/game_over/fin_lumineuse`…).
  ImageProvider? backgroundProvider(String relativePath) {
    if (kIsWeb) {
      return AssetImage(_bundledPath('assets/images/$relativePath') ??
          'assets/images/$relativePath.png');
    }
    final File? file = resolveImage(relativePath);
    return file == null ? null : FileImage(file);
  }

  /// Clés des assets du bundle (web — chargé une fois au démarrage par
  /// [loadBundleManifest]) : permet de choisir l'extension réelle des
  /// images déposées (.png, .jpg ou .jpeg).
  Set<String>? _bundledAssets;

  /// Web uniquement : lit le manifest d'assets du bundle (généré par
  /// `flutter build web`) pour connaître les images réellement embarquées
  /// et leurs extensions. À appeler une fois avant `runApp`.
  Future<void> loadBundleManifest() async {
    if (!kIsWeb) return;
    try {
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      _bundledAssets = manifest.listAssets().toSet();
    } catch (_) {
      _bundledAssets = null;
    }
  }

  /// Le chemin bundlé réel d'une image (sans extension donnée), null si
  /// absent du manifest (manifest pas encore chargé → .png par défaut).
  String? _bundledPath(String base) {
    final Set<String>? keys = _bundledAssets;
    if (keys == null) return null;
    for (final String ext in const <String>['.png', '.jpg', '.jpeg']) {
      final String candidate = '$base$ext';
      if (keys.contains(candidate)) return candidate;
    }
    return null;
  }
}

final imageServiceProvider =
    Provider<ImageService>((ref) => ImageService());
