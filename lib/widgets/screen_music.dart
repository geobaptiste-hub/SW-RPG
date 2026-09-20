import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sound_service.dart';

/// Lance la musique d'un écran au montage et gère son arrêt au démontage.
/// Wraps [track] name — le fichier attendu est
/// `assets/audio/music/<track>.mp3` (déposable sans recompilation).
class ScreenMusic extends ConsumerStatefulWidget {
  final String track;
  final Widget child;

  const ScreenMusic({super.key, required this.track, required this.child});

  @override
  ConsumerState<ScreenMusic> createState() => _ScreenMusicState();
}

class _ScreenMusicState extends ConsumerState<ScreenMusic> {
  @override
  void initState() {
    super.initState();
    ref.read(soundControllerProvider).playScreenMusic(widget.track);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
