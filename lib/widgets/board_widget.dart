import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/board_constants.dart';
import '../core/constants/planet_constants.dart' show PlanetConstants;
import '../core/theme/app_theme.dart';
import '../models/boss.dart';
import '../models/cantina_zone.dart';
import '../models/planet.dart';
import '../models/player.dart';
import '../models/portal.dart';
import '../models/tile.dart';
import 'board_camera.dart';
import 'boss_icon.dart';
import 'card_image.dart';
import 'player_token.dart';
import '../services/image_service.dart';
import 'tile_widget.dart';

/// Contrôleur de navigation du plateau, partagé entre l'écran et le
/// [BoardWidget] (Sprint 2 — amélioration de la navigation).
class BoardWidgetController {
  final ValueNotifier<bool> canRecenter = ValueNotifier<bool>(false);

  VoidCallback? _recenterHandler;

  /// Recentre la caméra sur le joueur actif (transition animée).
  void recenter() => _recenterHandler?.call();

  void _attach(VoidCallback handler) => _recenterHandler = handler;

  void _detach() => _recenterHandler = null;

  void dispose() => canRecenter.dispose();
}

/// Canvas du plateau : grille 15x15, pions, surbrillance des déplacements
/// et caméra.
///
/// Caméra (CDC §5) :
///  - vue centrée sur le joueur actif, avec suivi automatique ;
///  - bouton « Vue Galaxie » ([galaxyView]) dézoome pour cadrer tout le
///    plateau ; le renvoyer à `false` recentre sur le joueur ;
///  - les transitions sont animées (Sprint 2), seul le premier cadrage est
///    immédiat.
///
/// Brouillard de guerre (GDD §3) : les pions des joueurs ne sont rendus que
/// si leur case est découverte — le pion du joueur actif est toujours rendu.
/// Le contenu futur des cases (monstres, objets, portails, boss — Sprint 3+)
/// suivra la même règle : masqué tant que la case n'est pas découverte.
class BoardWidget extends StatefulWidget {
  final Planet planet;
  final List<Player> players;
  final int activePlayerIndex;

  /// Boss de la partie (Sprint 5) : seuls ceux de la planète affichée,
  /// présents et non fugqués sont rendus.
  final List<Boss> bosses;

  /// Portails découverts (Sprint 5) : rendus uniquement sur la planète
  /// principale ; les planètes secondaires affichent leur portail central
  /// de retour.
  final List<Portal> portals;

  /// La CANTINA (retours playtest 19/09) : logo jaune sur la case centrale
  /// tant que la zone n'a jamais été franchie, médaillon + image du bar
  /// ensuite — masqués par le brouillard comme le reste.
  final CantinaZone? cantina;

  /// Cibles de déplacement surlignées (vide si aucune phase de déplacement).
  final Set<Position> moveTargets;
  final void Function(Position target)? onMoveTargetTap;

  final bool galaxyView;

  /// Contrôleur optionnel de navigation (recentrage).
  final BoardWidgetController? controller;

  const BoardWidget({
    super.key,
    required this.planet,
    required this.players,
    required this.activePlayerIndex,
    this.bosses = const [],
    this.portals = const [],
    this.cantina,
    this.moveTargets = const {},
    this.onMoveTargetTap,
    this.galaxyView = false,
    this.controller,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _cameraAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  Animation<Matrix4>? _cameraAnim;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_recenter);
    // L'état « caméra recentrée ? » suit chaque changement de transformation
    // (pan/zoom manuels, animations de caméra).
    _transform.addListener(_updateCanRecenter);
    // Premier cadrage après le premier layout (la taille du viewport est
    // nécessaire au calcul de la matrice caméra).
    _scheduleCameraInit();
  }

  void _scheduleCameraInit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Size? viewport = context.size;
      if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
        _scheduleCameraInit();
        return;
      }
      _updateCamera(true);
    });
  }

  @override
  void didUpdateWidget(covariant BoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_recenter);
    }
    final bool playerMoved =
        widget.players[widget.activePlayerIndex].position !=
            oldWidget.players[oldWidget.activePlayerIndex].position;
    final bool activeChanged =
        widget.activePlayerIndex != oldWidget.activePlayerIndex;
    final bool galaxyChanged = widget.galaxyView != oldWidget.galaxyView;
    if (playerMoved || activeChanged || galaxyChanged) {
      // Transitions animées dans tous les cas (Sprint 2) ; seul le premier
      // cadrage (initState) est immédiat.
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateCamera(false));
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _transform.removeListener(_updateCanRecenter);
    _cameraAnimController.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// Recentre la caméra sur le joueur actif (appelé par le contrôleur).
  void _recenter() => _updateCamera(false);

  void _updateCamera(bool immediate) {
    final Size? viewport = context.size;
    // Viewport invalide : on ne touche pas a la camera (une matrice calculee
    // sur un viewport vide serait aberrante).
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      return;
    }

    final Matrix4 target = BoardCamera.matrixFor(
      viewport: viewport,
      galaxyView: widget.galaxyView,
      planet: widget.planet,
      players: widget.players,
      activePlayerIndex: widget.activePlayerIndex,
    );
    if (immediate) {
      _cameraAnimController.stop();
      _transform.value = target;
      return;
    }
    _cameraAnim = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _cameraAnimController,
      curve: Curves.easeOutCubic,
    ))
      ..addListener(() {
        _transform.value = _cameraAnim!.value;
      });
    _cameraAnimController
      ..reset()
      ..forward();
  }

  /// Met à jour l'état « caméra écartée du joueur actif » : le bouton
  /// Recentrer n'apparaît que dans ce cas — et jamais en Vue Galaxie, où le
  /// bouton « Vue Joueur » assure déjà le retour au cadrage joueur.
  void _updateCanRecenter() {
    final BoardWidgetController? controller = widget.controller;
    if (controller == null) return;
    if (widget.galaxyView) {
      controller.canRecenter.value = false;
      return;
    }
    final Size? viewport = context.size;
    final bool centered = viewport == null || viewport.isEmpty
        ? true
        : BoardCamera.almostEquals(
            _transform.value,
            BoardCamera.matrixFor(
              viewport: viewport,
              galaxyView: false,
              planet: widget.planet,
              players: widget.players,
              activePlayerIndex: widget.activePlayerIndex,
            ),
          );
    controller.canRecenter.value = !centered;
  }

  /// Un pion n'est rendu que si sa case est découverte ET si son porteur se
  /// trouve sur la planète affichée ; le pion du joueur actif est toujours
  /// rendu (GDD §3 — brouillard de guerre ; multi-planètes — Sprint 5).
  bool _isTokenVisible(int playerIndex) {
    // Un joueur éliminé disparaît du plateau (Sprint 3).
    if (widget.players[playerIndex].eliminated) return false;
    // Multi-planètes (Sprint 5) : les pions des autres planètes sont masqués.
    if (widget.players[playerIndex].planet != widget.planet.type) return false;
    if (playerIndex == widget.activePlayerIndex) return true;
    final Position position = widget.players[playerIndex].position;
    return widget.planet.tileAtOrNull(position.x, position.y)?.discovered ??
        false;
  }

  /// Portails à afficher (Sprint 5) : ceux de l'état sur la planète
  /// principale, un portail central « synthétique » de retour sur une
  /// planète secondaire (toujours marqué visité : on y est arrivé par un
  /// portail — retours playtest). Fix 19/09 : sur la planète principale,
  /// le marqueur ne s'affiche que sur une case ACTUELLEMENT VISIBLE (dans
  /// le rayon de vue du joueur actif) — plus jamais sous le brouillard,
  /// même partiellement découvert (filtre repris plus bas dans le build).
  List<Portal> _visiblePortals() {
    if (!PlanetConstants.startPlanets.contains(widget.planet.type)) {
      final PlanetType back = widget
              .players[widget.activePlayerIndex].returnPlanet ??
          PlanetConstants.startPlanets.first;
      return <Portal>[
        Portal(
          destination: back,
          position: PlanetConstants.secondaryPortalPosition,
          discovered: true,
          visited: true,
        ),
      ];
    }
    return <Portal>[
      for (final Portal portal in widget.portals)
        if (portal.discovered &&
            portal.position.x < widget.planet.width &&
            portal.position.y < widget.planet.height)
          portal,
    ];
  }

  /// Boss visibles (Sprint 5) : ceux de la planète affichée, présents
  /// (non fugqués, non définitivement morts) et sur une case ACTUELLEMENT
  /// VISIBLE — dans le rayon de vue du joueur actif (retours playtest : le
  /// boss ne doit pas se voir à travers le brouillard, même sur une case
  /// déjà découverte).
  List<Boss> _visibleBosses() {
    final int aliveCount =
        widget.players.where((Player p) => !p.eliminated).length;
    return <Boss>[
      for (final Boss boss in widget.bosses)
        if (boss.planet == widget.planet.type &&
            !boss.isGone &&
            !boss.isDefinitivelyDead(aliveCount) &&
            (widget.planet
                    .tileAtOrNull(boss.position.x, boss.position.y)
                    ?.visible ??
                false))
          boss,
    ];
  }

  /// Marqueur superposé à une case (portail, boss) — non interactif.
  Widget _marker(Position position, Widget child) {
    const double size = BoardConstants.tileExtent * 0.6;
    return Positioned(
      left: position.x * BoardConstants.tileExtent +
          (BoardConstants.tileExtent - size) / 2,
      top: position.y * BoardConstants.tileExtent +
          (BoardConstants.tileExtent - size) / 2,
      width: size,
      height: size,
      child: IgnorePointer(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double boardWidth = widget.planet.width * BoardConstants.tileExtent;
    final double boardHeight = widget.planet.height * BoardConstants.tileExtent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        panEnabled: true,
        scaleEnabled: true,
        minScale: BoardConstants.minZoom,
        maxScale: BoardConstants.maxZoom,
        boundaryMargin:
            const EdgeInsets.all(BoardConstants.cameraBoundaryMargin),
        child: SizedBox(
          width: boardWidth,
          height: boardHeight,
          child: Stack(
            children: [
              // Fond « espace » sous la grille.
              Container(color: AppColors.background),
              // Cases. Règle brouillard de guerre (GDD §3) : rien n'est
              // révélé sur une case non découverte ; les événements futurs
              // (monstres, objets, portails, boss) suivront la même règle à
              // partir du Sprint 3.
              for (final Tile tile in widget.planet.tiles)
                Positioned(
                  left: tile.x * BoardConstants.tileExtent,
                  top: tile.y * BoardConstants.tileExtent,
                  width: BoardConstants.tileExtent,
                  height: BoardConstants.tileExtent,
                  child: TileWidget(
                    tile: tile,
                    planet: widget.planet,
                    isMoveTarget:
                        widget.moveTargets.contains(Position(tile.x, tile.y)),
                    onTap: widget.moveTargets.contains(Position(tile.x, tile.y))
                        ? () => widget.onMoveTargetTap
                            ?.call(Position(tile.x, tile.y))
                        : null,
                  ),
                ),
              // Portails (Sprint 5) : icône dorée, uniquement sur une case
              // ACTUELLEMENT VISIBLE du joueur (rayon de vue) — jamais sous
              // le brouillard de guerre, même sur une case déjà découverte
              // (fix playtest 19/09 : les portails garantis du N3 restent
              // invisibles tant qu'aucun joueur ne s'en approche).
              for (final Portal portal in _visiblePortals())
                if (widget.planet
                        .tileAtOrNull(portal.position.x, portal.position.y)
                        ?.visible ??
                    false)
                  _marker(
                    portal.position,
                    // Portail visité + image de planète déposée : le
                    // médaillon montre la DESTINATION (retours playtest).
                    Consumer(builder:
                        (BuildContext context, WidgetRef ref, Widget? _) {
                      final File? planetImage = portal.visited
                          ? ref
                              .watch(imageServiceProvider)
                              .resolveFile('planets',
                                  planetImageId(portal.destination))
                          : null;
                      if (planetImage != null) {
                        return Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.background,
                            border: Border.all(
                                color: AppColors.gold, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black45, blurRadius: 4),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.file(planetImage,
                                fit: BoxFit.cover,
                                errorBuilder: (BuildContext context,
                                        Object error,
                                        StackTrace? stackTrace) =>
                                    const Icon(Icons.flare,
                                        size: 20,
                                        color: AppColors.gold)),
                          ),
                        );
                      }
                      return const Icon(Icons.flare,
                          size: 26,
                          color: AppColors.gold,
                          shadows: <Shadow>[
                            Shadow(
                                color: AppColors.gold,
                                blurRadius: 10),
                          ]);
                    }),
                  ),
              // CANTINA v2 (retours playtest 19/09) : sur la planète qui
              // porte la case-portail — logo jaune (identique portails)
              // tant que la zone n'a jamais été franchie, puis médaillon
              // avec l'image déposée (`assets/images/cantina/cantina.png`).
              // Masqué hors de la zone visible, comme les portails.
              if (widget.cantina != null &&
                  widget.cantina!.planet == widget.planet.type &&
                  (widget.planet
                          .tileAtOrNull(widget.cantina!.anchor.x,
                              widget.cantina!.anchor.y)
                          ?.visible ??
                      false))
                _marker(
                  widget.cantina!.anchor,
                  Consumer(builder:
                      (BuildContext context, WidgetRef ref, Widget? _) {
                    final File? logo = widget.cantina!.visited
                        ? ref
                            .watch(imageServiceProvider)
                            .resolveFile('cantina', 'cantina')
                        : null;
                    if (widget.cantina!.visited) {
                      return Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.background,
                          border: Border.all(
                              color: AppColors.gold, width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                        child: ClipOval(
                          child: logo == null
                              ? const Icon(Icons.local_bar,
                                  size: 20, color: AppColors.gold)
                              : Image.file(logo,
                                  fit: BoxFit.cover,
                                  errorBuilder: (BuildContext context,
                                          Object error,
                                          StackTrace? stackTrace) =>
                                      const Icon(Icons.local_bar,
                                          size: 20,
                                          color: AppColors.gold)),
                        ),
                      );
                    }
                    return const Icon(Icons.flare,
                        size: 26,
                        color: AppColors.gold,
                        shadows: <Shadow>[
                          Shadow(color: AppColors.gold, blurRadius: 10),
                        ]);
                  }),
                ),
              // INTÉRIEUR de la cantina (mini-planète 3x3) : l'image du
              // bar déposée (`assets/images/cantina/bar.png`) couvre la
              // rangée du haut bloquée, case par case une fois découverte.
              if (widget.planet.type == PlanetType.cantina)
                for (int dx = 0; dx < 3; dx++)
                  if (widget.planet.tileAtOrNull(dx, 0)?.discovered ?? false)
                    Positioned(
                      left: dx * BoardConstants.tileExtent,
                      top: 0,
                      width: BoardConstants.tileExtent,
                      height: BoardConstants.tileExtent,
                      child: IgnorePointer(
                        child: Consumer(builder:
                            (BuildContext context, WidgetRef ref,
                                Widget? _) {
                          final File? bar = ref
                              .watch(imageServiceProvider)
                              .resolveFile('cantina', 'bar');
                          if (bar == null) return const SizedBox.shrink();
                          return Image.file(bar,
                              fit: BoxFit.cover,
                              errorBuilder: (BuildContext context,
                                      Object error,
                                      StackTrace? stackTrace) =>
                                  const SizedBox.shrink());
                        }),
                      ),
                    ),
              // Boss (Sprint 5) : médaillon rond avec l'image du boss
              // si déposée (`assets/images/bosses/` — Sprint 6), sinon
              // icône par type. Caché hors du rayon de vue.
              for (final Boss boss in _visibleBosses())
                _marker(
                  boss.position,
                  Consumer(builder: (BuildContext context, WidgetRef ref, Widget? _) {
                    final File? photo = ref
                        .watch(imageServiceProvider)
                        .resolveFile('bosses', bossImageId(boss.type));
                    return Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.danger.withValues(alpha: 0.9),
                        border: Border.all(
                            color: Colors.black87, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                      child: ClipOval(
                        child: photo == null
                            ? Icon(bossIcon(boss.type),
                                size: 20, color: Colors.white)
                            : Image.file(photo,
                                fit: BoxFit.cover,
                                errorBuilder: (BuildContext context,
                                        Object error,
                                        StackTrace? stackTrace) =>
                                    Icon(bossIcon(boss.type),
                                        size: 20, color: Colors.white)),
                      ),
                    );
                  }),
                ),
              // Pions des joueurs, masqués sur cases non découvertes.
              for (int i = 0; i < widget.players.length; i++)
                if (_isTokenVisible(i))
                  Positioned(
                    left: widget.players[i].position.x *
                            BoardConstants.tileExtent +
                        (BoardConstants.tileExtent -
                                BoardConstants.tileExtent * 0.72) /
                            2,
                    top: widget.players[i].position.y *
                            BoardConstants.tileExtent +
                        (BoardConstants.tileExtent -
                                BoardConstants.tileExtent * 0.72) /
                            2,
                    width: BoardConstants.tileExtent * 0.72,
                    height: BoardConstants.tileExtent * 0.72,
                    child: IgnorePointer(
                      child: PlayerToken(
                        player: widget.players[i],
                        playerIndex: i,
                        isActive: i == widget.activePlayerIndex,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
