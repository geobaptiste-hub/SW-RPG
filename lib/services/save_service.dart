import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/game_state.dart';

/// Service de sauvegarde / chargement Hive (Architecture v1.0).
///
/// La sauvegarde contient le GameState complet (joueurs, boss, portails,
/// brouillard, temps, inventaires) : « Reprendre Partie » restaure
/// instantanément la partie (Architecture — Sauvegarde Hive).
///
/// Choix technique : les modèles sérialisent eux-mêmes en Map JSON
/// (`toJson` / `fromJson`) et la map est stockée dans une box Hive, ce qui
/// évite la génération de code (build_runner) tout en restant robuste.
class SaveService {
  static const String boxName = 'star_wars_rpg';
  static const String saveKey = 'current_game';

  Box? _box;

  /// Ouvre (une seule fois) la box de sauvegarde.
  Future<Box> _openBox() async {
    await Hive.initFlutter();
    return _box ??= await Hive.openBox(boxName);
  }

  /// Une sauvegarde existe-t-elle ?
  Future<bool> hasSave() async {
    final Box box = await _openBox();
    return box.get(saveKey) != null;
  }

  /// Sauvegarde le GameState complet (appelée automatiquement à la fin de
  /// chaque tour — GDD §15 / CDC §18).
  Future<void> save(GameState state) async {
    final Box box = await _openBox();
    await box.put(saveKey, state.toJson());
  }

  /// Charge la dernière sauvegarde, ou `null` s'il n'y en a pas.
  /// Une sauvegarde illisible (corrompue / version inconnue) est ignorée
  /// plutôt que de faire planter l'application.
  Future<GameState?> load() async {
    final Box box = await _openBox();
    final dynamic raw = box.get(saveKey);
    if (raw == null) return null;
    try {
      return GameState.fromJson(raw);
    } catch (error) {
      // Une sauvegarde illisible (corrompue / version inconnue) est ignorée
      // en release ; en debug, on trace la cause.
      debugPrint('SaveService: sauvegarde illisible — $error');
      return null;
    }
  }

  /// Supprime la sauvegarde (nouvelle partie écrasant l'ancienne, ou
  /// fonction « effacer » future des Paramètres).
  Future<void> deleteSave() async {
    final Box box = await _openBox();
    await box.delete(saveKey);
  }
}
