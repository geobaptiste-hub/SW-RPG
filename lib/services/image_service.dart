import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImageService {
  final List<String> roots;
  final Map<String, File?> _cache = <String, File?>{};

  ImageService({List<String>? roots}) : roots = roots ?? _defaultRoots();

  static List<String> _defaultRoots() {
    if (kIsWeb) return [];
    
    final List<String> roots = <String>[Directory.current.path];
    try {
      FileSystemEntity directory = File('').parent;
      for (int i = 0; i < 6; i++) {
        roots.add(directory.path);
        directory = directory.parent;
      }
    } on FileSystemException {
      // Plateforme sans resolvedExecutable
    }
    return roots;
  }

  File? resolveFile(String category, String id) {
    if (kIsWeb) return null;
    
    final String key = '$category/$id';
    if (_cache.containsKey(key)) return _cache[key];
    
    for (final String root in roots) {
      final String base = '$root${root.endsWith('/') ? '' : '/'}'
          'assets/images/$category/$id';
      for (final String ext in <String>['.png', '.jpg', '.jpeg']) {
        final File f = File('$base$ext');
        if (f.existsSync()) {
          _cache[key] = f;
          return f;
        }
      }
    }
    _cache[key] = null;
    return null;
  }
}