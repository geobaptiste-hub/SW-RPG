import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart'
    show AllyType, GameStatus, Rarity;
import '../../core/constants/game_constants.dart';
import '../../core/constants/planet_constants.dart' show PlanetConstants;
import '../../core/theme/app_theme.dart';
import '../../models/ally.dart';
import '../../models/armor.dart';
import '../../models/boss.dart';
import '../../models/weapon.dart';
import '../../models/game_state.dart';
import '../../models/planet.dart' show PlanetType;
import '../../models/tile.dart';
import '../../models/player.dart';
import '../../services/combat_service.dart';
import '../../services/sound_service.dart';
import '../../services/game_service.dart';
import '../../widgets/board_widget.dart';
import '../../widgets/card_image.dart';
import '../../widgets/dice_widget.dart';

/// Écran principal de jeu (CDC §10) :
///  - haut   : Tour X, joueur actif, déplacements restants, temps de jeu,
///    bouton « Quitter la partie » ;
///  - centre : plateau avec caméra suivant le joueur actif ;
///  - bas    : dé / points de déplacement, puis boutons Personnage, Équipe,
///    Inventaire, Joueurs, Vue Galaxie.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen>
    with WidgetsBindingObserver {
  Timer? _gameClock;
  BoardWidgetController? _boardController;
  bool _galaxyView = false;
  bool _gameOverShown = false;
  bool _eliminationShown = false;

  /// Carte allié/carte Spéciale ENNEMIE affichée : l'élimination (si la
  /// carte a tué) ne doit être montrée qu'APRÈS la fermeture de ce dialog
  /// (retours playtest : l'écran « Éliminé » passait devant l'explication).
  bool _enemyCardDialogOpen = false;
  bool _rolling = false;
  int? _rollingFace;
  final DiceRollAnimation _diceAnimation = DiceRollAnimation();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boardController = BoardWidgetController();
    // Entrée en partie : la musique de l'accueil cède la place à
    // l'AMBIANCE SONORE de la planète courante (ou de la cantina si le
    // joueur reprend une partie dedans) — boucle (retours playtest 19/09 ;
    // les écrans hors partie reprennent leur musique en la remplaçant).
    ref.read(soundControllerProvider).stopMusic();
    final GameState? initial = ref.read(gameControllerProvider);
    if (initial != null) _updateAmbience(initial);
    // Temps de jeu mm:ss (CDC §10) : un tick par seconde tant que l'écran
    // de jeu est ouvert — en PAUSE lorsque l'app est en arrière-plan
    // (Sprint 6, retours playtest).
    _startClock();
  }

  /// Piste d'ambiance courante (garde anti-redémarrage à chaque rebuild).
  String? _currentAmbienceTrack;

  /// Piste d'ambiance du plateau : la MUSIQUE DE LA CANTINA quand le
  /// joueur actif s'y trouve (mini-planète 3x3), sinon l'ambiance de la
  /// planète courante (retours playtest 19/09).
  String _ambienceTrackFor(GameState state) {
    if (state.planetType == PlanetType.cantina) return 'lieux/cantina';
    return 'planetes/${planetAmbienceTrack(state.planetType)}';
  }

  void _updateAmbience(GameState state) {
    final String track = _ambienceTrackFor(state);
    if (track == _currentAmbienceTrack) return;
    _currentAmbienceTrack = track;
    ref.read(soundControllerProvider).playScreenMusic(track);
  }

  void _startClock() {
    _gameClock ??= Timer.periodic(const Duration(seconds: 1),
        (_) => ref.read(gameControllerProvider.notifier).tickGameTime());
  }

  void _stopClock() {
    _gameClock?.cancel();
    _gameClock = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hot-seat : le chrono ne compte que le temps réellement joué.
    if (state == AppLifecycleState.resumed) {
      _startClock();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopClock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopClock();
    _boardController?.dispose();
    super.dispose();
  }

  Future<void> _rollDice() async {
    if (_rolling) return;
    setState(() => _rolling = true);
    // Effet sonore du lancer (fix 19/09 — sfx/de).
    ref.read(soundControllerProvider).playSfx('de');
    await _diceAnimation.roll(
        onTick: (int face) => setState(() => _rollingFace = face));
    if (!mounted) return;
    // La valeur réelle est tirée par le contrôleur de jeu (GDD §6).
    ref.read(gameControllerProvider.notifier).rollDice();
    setState(() {
      _rolling = false;
      _rollingFace = null;
    });
  }

  Future<void> _endTurn() async {
    await ref.read(gameControllerProvider.notifier).endTurn();
    // L'annulation de la sauvegarde / d'éventuelles conditions de victoire
    // seront gérées ici à partir du Sprint 3/5.
  }

  /// Confirmation puis sortie vers l'accueil. La partie est sauvegardée
  /// DANS SON ÉTAT ACTUEL avant de sortir (fix 19/09 : l'autosave ne
  /// s'appliquait qu'à la fin du tour — les déplacements/combats du tour
  /// en cours étaient perdus) : elle peut être reprise via « Reprendre
  /// Partie » (GDD §15).
  Future<void> _confirmQuit() async {
    final bool? quit = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sauvegarder et quitter ?'),
        content: const Text(
          'La partie sera sauvegardée dans son état actuel, y compris le '
          'tour en cours. Elle pourra être reprise depuis l’accueil.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sauver et quitter'),
          ),
        ],
      ),
    );
    if (quit != true) return;
    await ref.read(gameControllerProvider.notifier).saveGame();
    ref.read(gameControllerProvider.notifier).exitGame();
    if (mounted) context.go('/');
  }

  void _toggleGalaxyView() => setState(() => _galaxyView = !_galaxyView);

  /// Déplacement vers une case cible + résolution des rencontres
  /// (Sprint 3 : monstre → Combattre / Fuir ; joueur → combat JvJ ;
  /// Sprint 5 : boss, blocage boss, voyage par portail).
  void _handleMoveTap(Position target, GameController controller) {
    final MoveResult result = controller.moveActivePlayerTo(target.x, target.y);
    if (result == MoveResult.monsterEncounter) {
      // Rencontre sonore avant l'écran de combat (sfx/monstre).
      ref.read(soundControllerProvider).playSfx('monstre');
      // Sprint 4.2 : entrée automatique en combat (la fuite se fait
      // depuis l'écran de combat).
      ref.read(combatControllerProvider.notifier).startMonsterCombat(target);
      context.go('/combat');
    } else if (result == MoveResult.bossEncounter) {
      // Sprint 5 : entrée automatique en combat de boss.
      final GameState game = ref.read(gameControllerProvider)!;
      final Boss? boss = game.bosses
          .where((Boss b) =>
              b.planet == game.planetType && !b.isGone && b.position == target)
          .firstOrNull;
      if (boss != null) {
        ref.read(combatControllerProvider.notifier).startBossCombat(boss);
        context.go('/combat');
      }
    } else if (result == MoveResult.bossBlocked) {
      _showBossBlockedDialog();
    } else if (result == MoveResult.portalTravel) {
      ref.read(soundControllerProvider).playSfx('portail');
      _showPortalTravelDialog();
    } else if (result == MoveResult.cantinaTravel) {
      // Entrée dans la cantina par la case-portail (retours playtest
      // 19/09 v2) : la musique bascule via _updateAmbience (listen).
      _showCantinaEnterDialog();
    } else if (result == MoveResult.cantinaDrink) {
      // Consommation à la cantina (retours playtest 19/09) : PV au max.
      ref.read(soundControllerProvider).playSfx('carte_positive');
      _showCantinaDrinkDialog();
    } else if (result == MoveResult.allyEncounter) {
      _showAllyDialog();
    } else if (result == MoveResult.itemEncounter) {
      _showItemDialog();
    } else if (result == MoveResult.healEncounter) {
      _showHealDialog();
    } else if (result == MoveResult.playerEncounter) {
      final GameState state = ref.read(gameControllerProvider)!;
      final int defenderIndex = state.players.indexWhere((Player p) =>
          !p.eliminated &&
          p.position == target &&
          state.players.indexOf(p) != state.currentPlayerIndex);
      ref
          .read(combatControllerProvider.notifier)
          .startPlayerCombat(defenderIndex);
      if (mounted) context.go('/combat');
    } else if (result == MoveResult.moved) {
      // Simple pas d'une case (sfx/pas) — les rencontres ont leur propre
      // son, le voyage par portail aussi.
      ref.read(soundControllerProvider).playSfx('pas');
    }
  }

  /// Boss présent mais verrouillé (aucun joueur N5 — Sprint 5) : l'entrée
  /// est refusée, le point de déplacement est perdu.
  void _showBossBlockedDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('⚡ Boss trop puissant !'),
        content: const Text(
            'Un boss garde l’accès à cette case : atteignez le niveau 5 '
            'pour pouvoir l’affronter.\n\n'
            '(Entrée refusée — 1 point de déplacement est perdu.)'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  /// Entrée dans la CANTINA (retours playtest 19/09) : la case-portail a
  /// téléporté le joueur dans la mini-zone 3x3 — zone sanctuarisée (pas
  /// de combat JvJ, pas de monstre), le comptoir du milieu remet les PV
  /// au maximum.
  void _showCantinaEnterDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('🍺 Vous entrez dans la cantina !'),
        content: const Text(
            'Un havre de paix au cœur de la galaxie : aucun combat entre '
            'joueurs ici.\n\n'
            'Marchez sur le comptoir (ligne du milieu) pour vous '
            'désaltérer et regagner tous vos PV. Repassez par la case '
            'd\'entrée pour ressortir.'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  /// Consommation au comptoir : PV remis au maximum.
  void _showCantinaDrinkDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('🍺 Pause à la cantina !'),
        content: const Text(
            'Vous vous désaltérez et regagnez tous vos PV !\n\n'
            '(En pleine cantina, aucun combat entre joueurs : détente '
            'forcée.)'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  /// Voyage par portail accompli (Sprint 5) : le joueur arrive sur la
  /// planète liée (ou revient sur sa planète d'origine).
  void _showPortalTravelDialog() {
    final GameState state = ref.read(gameControllerProvider)!;
    final String planetName =
        PlanetConstants.displayNames[state.planetType] ?? state.planetType.name;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('🌌 Voyage interstellaire !'),
        content: Text(
            'Vous voyagez vers $planetName. '
            'Le portail central de la planète permet de revenir '
            'à votre point de départ.'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  /// Le joueur actif a été éliminé pendant son tour : fin de tour auto.
  void _showEliminationDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Éliminé !'),
        content: const Text('Vos PV sont tombés à 0 — votre tour se termine '
            '(les autres joueurs continuent).'),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(gameControllerProvider.notifier).endTurn();
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  /// Rencontre allié (Sprint 4) : dialog de recrutement avec défausse
  /// intégrée quand l'équipe n'a plus de place (Sprint 4.2).
  void _showAllyDialog() {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final Ally? ally = controller.pendingAllyOffer;
    if (ally == null) return;

    // Allié / carte Spéciale de faction ennemie (Sprint 4.3) : il frappe
    // directement, aucun recrutement possible (les dégâts — tempérés par
    // le niveau et plafonnés — sont déjà appliqués au déplacement).
    final int? specialDamage = controller.pendingSpecialDamage;
    // Son distinct : carte négative (elle attaque) vs trouvaille positive.
    ref.read(soundControllerProvider).playSfx(
        specialDamage != null ? 'carte_negative' : 'carte_positive');
    if (specialDamage != null) {
      controller.pendingSpecialDamage = null;
      final Player victim = ref.read(gameControllerProvider)!.activePlayer;
      final bool eliminated = victim.eliminated;
      _enemyCardDialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('⚔ Un ennemi vous attaque !'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // La carte de l'ennemi, en portrait (retours playtest).
                Center(
                  child: CardImage(
                    category: allyImageCategory(ally.type),
                    id: cardImageId(ally.name),
                    width: 210,
                    height: 324,
                    fit: BoxFit.contain,
                    fallbackIcon: Icons.warning_amber_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text:
                            '${ally.name} (${ally.faction.displayName}) vous attaque : ',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                      // Seuls les dégâts sont en rouge (retours playtest).
                      TextSpan(
                        text: '-$specialDamage PV !',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: ' La carte ne rejoint pas votre équipe.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                      if (eliminated)
                        TextSpan(
                          text:
                              '\n\nVos PV sont tombés à 0 : ${victim.name} est éliminé…',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: AppColors.danger),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continuer'),
            ),
          ],
        ),
      ).then((_) {
        _enemyCardDialogOpen = false;
        // La carte vue, on montre ENFIN l'écran d'élimination (séquence
        // demandée par le playtest) — sinon rien si le joueur survit.
        if (eliminated && mounted && !_eliminationShown) {
          _eliminationShown = true;
          _showEliminationDialog();
        }
      });
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _AllyRecruitDialog(ally: ally),
    );
  }

  /// Trouvaille objet (Sprint 4) : refuser (carte détruite), mettre en
  /// réserve (1 arme + 1 tenue) ou équiper (si rareté autorisée).
  void _showItemDialog() {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    final Weapon? weapon = controller.pendingWeaponOffer;
    final Armor? armor = controller.pendingArmorOffer;
    final GameState state = ref.read(gameControllerProvider)!;
    final Player active = state.activePlayer;

    if (weapon != null) {
      _showItemDialogImpl(
        active: active,
        imageId: weapon.id,
        name: weapon.name,
        rarity: weapon.rarity,
        bonus: weapon.attackBonus,
        unit: 'ATK',
        isWeapon: true,
      );
    } else if (armor != null) {
      _showItemDialogImpl(
        active: active,
        imageId: armor.id,
        name: armor.name,
        rarity: armor.rarity,
        bonus: armor.hpBonus,
        unit: 'PV',
        isWeapon: false,
      );
    }
  }

  void _showItemDialogImpl({
    required Player active,
    required String imageId,
    required String name,
    required Rarity rarity,
    required int bonus,
    required String unit,
    required bool isWeapon,
  }) {
    // Trouvaille positive (sfx/carte_positive).
    ref.read(soundControllerProvider).playSfx('carte_positive');
    // Dialog public (ItemFoundDialog) : testable directement.
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => ItemFoundDialog(
        active: active,
        imageId: imageId,
        name: name,
        rarity: rarity,
        bonus: bonus,
        unit: unit,
        isWeapon: isWeapon,
      ),
    );
  }

  /// Case Soin (Sprint 4) : dé de soin animé, distinct du dé de déplacement.
  void _showHealDialog() {
    final GameController controller = ref.read(gameControllerProvider.notifier);
    // Trouvaille positive (sfx/carte_positive).
    ref.read(soundControllerProvider).playSfx('carte_positive');
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _HealDialog(
        roll: controller.lastHealRoll ?? 1,
        healed: controller.lastHealAmount ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GameState? state = ref.watch(gameControllerProvider);
    if (state == null) {
      // Garde-fou : aucune partie en cours → retour à l'accueil.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Fin de partie (Sprint 5) : écran Game Over dédié.
    if (state.status == GameStatus.finished && !_gameOverShown) {
      _gameOverShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/game-over');
      });
    }

    // Notifications Sprint 5 : planètes dévoilées par un portail découvert,
    // boss éveillés (transients non sauvegardés du GameController).
    ref.listen<GameState?>(gameControllerProvider,
        (GameState? previous, GameState? next) {
      if (next == null || !mounted) return;
      // Ambiance sonore : suit la planète courante ET la cantina (retours
      // playtest 19/09) — porte → musique de la cantina, sortie → retour
      // à l'ambiance de la planète.
      _updateAmbience(next);
      final GameController controller =
          ref.read(gameControllerProvider.notifier);
      if (controller.lastPortalDiscoveries.isNotEmpty) {
        final String names = controller.lastPortalDiscoveries
            .map((PlanetType type) =>
                PlanetConstants.displayNames[type] ?? type.name)
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🌌 $names se dévoile !')),
        );
        controller.lastPortalDiscoveries.clear();
      }
      if (controller.bossAwakeningPlanets.isNotEmpty) {
        final String names = controller.bossAwakeningPlanets
            .map((PlanetType type) =>
                PlanetConstants.displayNames[type] ?? type.name)
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚡ Un boss s’éveille sur $names !')),
        );
        controller.bossAwakeningPlanets.clear();
      }
      if (controller.doubleMonstersPending) {
        controller.doubleMonstersPending = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('👥 Des doubles monstres apparaissent !')),
        );
      }
    });

    // Le joueur actif éliminé pendant son tour : fin de tour automatique.
    // En attente si une carte ennemie est affichée : elle s'explique
    // d'abord (retours playtest), l'élimination suit à sa fermeture.
    if (state.status == GameStatus.inProgress &&
        state.activePlayer.eliminated &&
        !_eliminationShown &&
        !_enemyCardDialogOpen) {
      _eliminationShown = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showEliminationDialog());
    }

    final GameController controller = ref.read(gameControllerProvider.notifier);
    final bool moving = state.movementPointsRemaining > 0;
    final Set<Position> targets =
        moving ? controller.validMoveTargets().toSet() : const <Position>{};
    final bool stuck = controller.isMovementBlocked();
    // Le tour peut être terminé : tous les points utilisés (ou joueur bloqué).
    final bool canEndTurn =
        (!moving && state.lastDiceRoll != null) || (moving && stuck);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopHud(state: state, onQuit: _confirmQuit),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: BoardWidget(
                        planet: state.currentPlanet,
                        players: state.players,
                        activePlayerIndex: state.currentPlayerIndex,
                        bosses: state.bosses,
                        portals: state.portals,
                        cantina: state.cantina,
                        controller: _boardController,
                        moveTargets: targets,
                        onMoveTargetTap: (Position target) =>
                            _handleMoveTap(target, controller),
                        galaxyView: _galaxyView,
                      ),
                    ),
                    // Bouton « Recentrer » : visible uniquement lorsque la
                    // caméra a été écartée du joueur actif (Sprint 2).
                    ValueListenableBuilder<bool>(
                      valueListenable: _boardController!.canRecenter,
                      builder: (BuildContext context, bool canRecenter, _) {
                        // L'etat masque reste un enfant Positioned : un
                        // enfant non positionne (SizedBox.shrink) ferait
                        // s'effondrer la largeur du Stack.
                        if (!canRecenter) {
                          return const Positioned(
                            right: 12,
                            bottom: 12,
                            child: SizedBox.shrink(),
                          );
                        }
                        return Positioned(
                          right: 12,
                          bottom: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'board_recenter',
                            tooltip: 'Recentrer sur le joueur actif',
                            onPressed: _boardController!.recenter,
                            child: const Icon(Icons.my_location),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            _DiceBar(
              state: state,
              rolling: _rolling,
              rollingFace: _rollingFace,
              canEndTurn: canEndTurn,
              onRoll: _rollDice,
              onEndTurn: _endTurn,
            ),
            _BottomBar(
              galaxyView: _galaxyView,
              onToggleGalaxy: _toggleGalaxyView,
              onQuit: _confirmQuit,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HUD haut : Tour X / Joueur actif / Déplacements restants / Temps de jeu /
// Quitter la partie (CDC §10)
// ---------------------------------------------------------------------------

class _TopHud extends StatelessWidget {
  final GameState state;
  final VoidCallback onQuit;

  const _TopHud({required this.state, required this.onQuit});

  /// Faction d'une planète secondaire (celle de son boss) ; null pour
  /// les planètes de départ (retours playtest).
  static Faction? _planetFaction(PlanetType type) {
    if (!PlanetConstants.secondaryPlanets.contains(type)) return null;
    final BossType? boss = PlanetConstants.bossBySecondaryPlanet[type];
    return boss == null ? null : PlanetConstants.bossFactionByType[boss];
  }

  /// Couleur d'ambiance de chaque faction (chips du HUD et de l'équipe).
  static Color factionColor(Faction faction) => switch (faction) {
        Faction.jedi => const Color(0xFF4FC3F7),
        Faction.sith => AppColors.danger,
        Faction.rebel => const Color(0xFFFFB74D),
        Faction.empire => const Color(0xFF81C784),
      };

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Player active = state.activePlayer;
    final Color tokenColor =
        AppColors.playerTokenColor(state.currentPlayerIndex);
    final Color factionColor = _TopHud.factionColor(active.faction);

    // Jauge d'XP : progression entre le palier atteint et le suivant
    // (pleine au niveau maximum).
    final int? nextXp = GameConstants.xpRequiredForNextLevel(active.level);
    final int prevXp = GameConstants.xpRequiredPerLevel[active.level - 1];
    final double xpProgress = nextXp == null
        ? 1.0
        : ((active.xp - prevXp) / (nextXp - prevXp)).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ligne 1 : Tour / planète / joueur actif / déplacements / temps.
          Row(
            children: [
              Text('Tour ${state.turn}',
                  style: textTheme.titleMedium?.copyWith(
                      color: AppColors.gold, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              // Planète courante (Sprint 5 — multi-planètes).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.public, size: 13, color: AppColors.gold),
                    const SizedBox(width: 4),
                    Text(
                      PlanetConstants.displayNames[state.planetType] ??
                          state.planetType.name,
                      style:
                          textTheme.labelMedium?.copyWith(color: AppColors.gold),
                    ),
                    // Faction de la planète (secondaires — retours playtest).
                    if (_planetFaction(state.planetType) != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        _planetFaction(state.planetType)!.displayName,
                        style: textTheme.labelMedium?.copyWith(
                            color: _TopHud.factionColor(
                                _planetFaction(state.planetType)!)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(radius: 8, backgroundColor: tokenColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(active.name,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium),
              ),
              const SizedBox(width: 6),
              // Faction du joueur actif (retours playtest 10/09/2026).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: factionColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: factionColor.withValues(alpha: 0.5)),
                ),
                child: Text(active.faction.displayName,
                    style:
                        textTheme.labelSmall?.copyWith(color: factionColor)),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Déplacements restants : ${state.movementPointsRemaining}',
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: state.movementPointsRemaining > 0
                        ? FontWeight.w700
                        : null,
                    color: state.movementPointsRemaining > 0
                        ? AppColors.moveHighlight
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(state.formattedGameTime, style: textTheme.bodyLarge),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.exit_to_app, size: 20),
                color: AppColors.gold,
                tooltip: 'Sauvegarder et quitter la partie',
                onPressed: onQuit,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Ligne 2 : niveau + jauge d'XP / ATK / PV (pleine largeur —
          // retours playtest 10/09/2026).
          Row(
            children: <Widget>[
              Text('Niv. ${active.level}',
                  style: textTheme.labelMedium?.copyWith(
                      color: AppColors.gold, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: xpProgress,
                    minHeight: 5,
                    color: AppColors.moveHighlight,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                nextXp == null ? 'MAX' : '${active.xp}/$nextXp XP',
                style: textTheme.labelSmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.flash_on, size: 14, color: AppColors.gold),
              Text(' ${active.totalAttack}',
                  style: textTheme.labelMedium?.copyWith(
                      color: AppColors.gold, fontWeight: FontWeight.w700)),
              const SizedBox(width: 16),
              const Icon(Icons.favorite, size: 14, color: AppColors.danger),
              Text(' ${active.hp}/${active.totalMaxHp}',
                  style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre du dé et fin de tour
// ---------------------------------------------------------------------------

class _DiceBar extends StatelessWidget {
  final GameState state;
  final bool rolling;
  final int? rollingFace;
  final bool canEndTurn;
  final VoidCallback onRoll;
  final VoidCallback onEndTurn;

  const _DiceBar({
    required this.state,
    required this.rolling,
    required this.rollingFace,
    required this.canEndTurn,
    required this.onRoll,
    required this.onEndTurn,
  });

  @override
  Widget build(BuildContext context) {
    final bool mustRoll =
        state.lastDiceRoll == null && state.movementPointsRemaining == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          DiceWidget(
            value: rolling ? rollingFace : (state.lastDiceRoll ?? 1),
            rolling: rolling,
            size: 56,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              rolling
                  ? 'Lancer en cours…'
                  : mustRoll
                      ? 'Lancez le dé pour obtenir vos points de déplacement.'
                      : 'Points de déplacement : ${state.movementPointsRemaining}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (mustRoll)
            FilledButton.icon(
              icon: const Icon(Icons.casino),
              label: const Text('Lancer le dé'),
              onPressed: rolling ? null : onRoll,
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Terminer le tour'),
              onPressed: canEndTurn && !rolling ? onEndTurn : null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre bas : Personnage / Équipe / Inventaire / Joueurs / Vue Galaxie
// (CDC §10)
// ---------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  final bool galaxyView;
  final VoidCallback onToggleGalaxy;

  /// Sortie avec sauvegarde (fix 19/09 : bouton libellé dans la barre
  /// basse — l'unique icône du HUD haut passait inaperçue).
  final VoidCallback onQuit;

  const _BottomBar({
    required this.galaxyView,
    required this.onToggleGalaxy,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          _BarButton(
              icon: Icons.person_outline,
              label: 'Personnage',
              onTap: () => context.go('/character')),
          _BarButton(
              icon: Icons.group,
              label: 'Équipe',
              onTap: () => context.go('/team')),
          _BarButton(
              icon: Icons.inventory_2_outlined,
              label: 'Inventaire',
              onTap: () => context.go('/inventory')),
          _BarButton(
              icon: Icons.list_alt,
              label: 'Joueurs',
              onTap: () => context.go('/players')),
          _BarButton(
              icon: Icons.receipt_long,
              label: 'Journal',
              onTap: () => context.go('/journal')),
          _BarButton(
            icon: galaxyView ? Icons.center_focus_strong : Icons.public,
            label: galaxyView ? 'Vue Joueur' : 'Vue Galaxie',
            onTap: onToggleGalaxy,
          ),
          _BarButton(
            icon: Icons.logout,
            label: 'Quitter',
            onTap: onQuit,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: AppColors.gold),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog de soin avec son propre dé animé (règle du game design :
/// un lancer dédié au soin — Sprint 4.1).
class _HealDialog extends StatefulWidget {
  final int roll;
  final int healed;

  const _HealDialog({required this.roll, required this.healed});

  @override
  State<_HealDialog> createState() => _HealDialogState();
}

class _HealDialogState extends State<_HealDialog> {
  int? _face;
  bool _revealed = false;
  final DiceRollAnimation _animation = DiceRollAnimation();

  @override
  void initState() {
    super.initState();
    _animation.roll(onTick: (int face) {
      if (mounted) setState(() => _face = face);
    }).then((_) {
      if (mounted) {
        setState(() {
          _face = widget.roll;
          _revealed = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Case de Soin'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DiceWidget(
            value: _face ?? widget.roll,
            rolling: !_revealed,
            size: 64,
          ),
          const SizedBox(height: 12),
          if (_revealed)
            Text(
              'Dé : ${widget.roll} → +${widget.healed} PV récupérés !',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.moveHighlight),
            ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: _revealed ? () => Navigator.of(context).pop() : null,
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}

/// Dialog de recrutement d'un allié (Sprint 4.2) : carte proposée, jauge de
/// places en temps réel et défausse intégrée pour libérer de la place.
class _AllyRecruitDialog extends ConsumerWidget {
  final Ally ally;

  const _AllyRecruitDialog({required this.ally});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameState? state = ref.watch(gameControllerProvider);
    if (state == null) return const SizedBox.shrink();
    final Player active = state.activePlayer;
    // Rareté autorisée par le niveau (retours playtest : même table que
    // l'équipement) + places d'équipe suffisantes + pas de doublon
    // (hors escouades, qui se cumulent par design).
    final bool rarityAllowed =
        GameController.rarityAllowedForLevel(ally.rarity, active.level);
    final bool hasSlots = active.canRecruit(ally.teamCost);
    final bool duplicate =
        ally.type != AllyType.escouade && active.hasAllyNamed(ally.name);
    final bool canRecruit = rarityAllowed && hasSlots && !duplicate;
    final bool enemy = ally.faction != active.faction &&
        ally.faction != active.faction.alliedFaction;
    final int malus = GameController.enemyRecruitMalus(ally, active.faction);
    final Ally? storedAlly = active.storedAlly;

    return AlertDialog(
      title: const Text('Allié à recruter !'),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: CardImage(
                  category: allyImageCategory(ally.type),
                  id: cardImageId(ally.name),
                  width: 240,
                  height: 370,
                  fit: BoxFit.contain,
                  fallbackIcon: Icons.person_outline,
                ),
              ),
              const SizedBox(height: 10),
              Text(ally.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.rarityColor(ally.rarity))),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Chip(
                    label: Text(
                      ally.rarity.displayName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: AppColors.rarityColor(ally.rarity),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${ally.type.displayName} · ${ally.teamCost} PP · '
                      '${ally.faction.displayName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(ally.effectSummary),
            if (enemy)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ Faction ennemie : -$malus PV au recrutement',
                    style: TextStyle(color: AppColors.danger)),
              ),
            if (!rarityAllowed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '⛔ Niveau '
                    '${GameConstants.minLevelForRarity(ally.rarity.index)} '
                    'requis (${ally.rarity.displayName}) : mettez-la en '
                    'réserve pour la recruter plus tard.',
                    style: TextStyle(color: AppColors.danger)),
              )
            else if (duplicate)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '⛔ ${ally.name} fait déjà partie de votre équipe '
                    '(les escouades peuvent se multiplier, pas les autres '
                    'cartes).',
                    style: TextStyle(color: AppColors.danger)),
              )
            else if (!hasSlots)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Pas assez de places d\u2019équipe (${active.usedTeamSlots} / '
                    '${active.teamCapacity} utilisées).',
                    style: TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 10),
            Text(
                'Équipe : ${active.usedTeamSlots} / '
                '${active.teamCapacity} places · '
                'Réserve : ${storedAlly?.name ?? 'vide'}',
                style: Theme.of(context).textTheme.bodyMedium),
            // Carte en réserve : fiche complète (retours playtest 19/09 —
            // savoir EXACTEMENT ce qu'on remplacerait avant de choisir).
            if (storedAlly != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.archive,
                            size: 15, color: AppColors.gold),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('En réserve : ${storedAlly.name}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${storedAlly.type.displayName} · '
                      '${storedAlly.faction.displayName} · '
                      '${storedAlly.teamCost} PP',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color:
                                  AppColors.rarityColor(storedAlly.rarity),
                              fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      storedAlly.effectSummary,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choisir « Réserve » remplacera ${storedAlly.name} : '
                      'sa carte sera définitivement perdue.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
            if (!canRecruit && active.allies.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                  'Défaussez un ou plusieurs alliés pour libérer '
                  '${ally.teamCost} place(s) :',
                  style: Theme.of(context).textTheme.bodyMedium),
              for (int index = 0; index < active.allies.length; index++)
                Row(
                  children: <Widget>[
                    // Nom + type/faction/rareté (retours playtest : savoir
                    // QUI on défausse).
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(active.allies[index].name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          Text(
                            '${active.allies[index].type.displayName} · '
                            '${active.allies[index].faction.displayName} · '
                            '${active.allies[index].rarity.displayName} · '
                            '${active.allies[index].teamCost} PP',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.rarityColor(
                                        active.allies[index].rarity)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Défausser ${active.allies[index].name}',
                      onPressed: () => ref
                          .read(gameControllerProvider.notifier)
                          .discardAlly(index),
                    ),
                  ],
                ),
            ],
          ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            ref.read(gameControllerProvider.notifier).declinePendingAlly();
            Navigator.of(context).pop();
          },
          child: const Text('Refuser'),
        ),
        TextButton(
          onPressed: () {
            ref.read(gameControllerProvider.notifier).storePendingAlly();
            Navigator.of(context).pop();
          },
          child: Text(storedAlly == null
              ? 'Réserve'
              : 'Réserve (remplace ${storedAlly.name})'),
        ),
        FilledButton(
          onPressed: canRecruit
              ? () {
                  ref
                      .read(gameControllerProvider.notifier)
                      .recruitPendingAlly();
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Recruter'),
        ),
      ]
          .map<Widget>((Widget child) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: child,
              ))
          .toList(),
    );
  }
}

/// Dialog de trouvaille d'objet (Sprint 4, enrichi retours playtest) :
/// rareté colorée, équipement actuel, comparaison de bonus, et choix
/// Refuser / Réserve / Équiper. Public pour être testable.
class ItemFoundDialog extends ConsumerWidget {
  final Player active;

  /// Identifiant d'image de la carte (`weapon.id` / `armor.id`) — affichée
  /// en grand au-dessus du texte (retours playtest : voir la carte trouvée).
  final String imageId;
  final String name;
  final Rarity rarity;
  final int bonus;
  final String unit;
  final bool isWeapon;

  const ItemFoundDialog({
    super.key,
    required this.active,
    required this.imageId,
    required this.name,
    required this.rarity,
    required this.bonus,
    required this.unit,
    required this.isWeapon,
  });

  /// Équipe la trouvaille. Si équipée ET réserve sont occupées (3 objets
  /// pour 2 emplacements — retours playtest), demande quoi faire de
  /// l'ancienne équipée : DÉFAUSSÉE (réserve préservée) ou mise en
  /// réserve (remplace la réserve actuelle).
  Future<void> _equipWithChoice(BuildContext context, WidgetRef ref) async {
    final GameController controller =
        ref.read(gameControllerProvider.notifier);
    final String? equippedName =
        isWeapon ? active.weapon?.name : active.armor?.name;
    final String? storedName =
        isWeapon ? active.storedWeapon?.name : active.storedArmor?.name;
    final bool bothFull = equippedName != null && storedName != null;

    if (!bothFull) {
      final bool ok = isWeapon
          ? controller.equipPendingWeapon()
          : controller.equipPendingArmor();
      if (ok && context.mounted) Navigator.of(context).pop();
      return;
    }

    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Que faire de « $equippedName » ?'),
        content: Text(
            'Vos deux emplacements sont occupés : équiper « $name » libère '
            'votre objet équipé.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('Défausser l’équipée'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('store'),
            child: Text('En réserve (remplace « $storedName »)'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (isWeapon) {
      controller.equipPendingWeapon(discardReplaced: choice == 'discard');
    } else {
      controller.equipPendingArmor(discardReplaced: choice == 'discard');
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool allowed =
        GameController.rarityAllowedForLevel(rarity, active.level);
    final Color rarityColor = AppColors.rarityColor(rarity);
    final String? equippedName =
        isWeapon ? active.weapon?.name : active.armor?.name;
    final int? equippedBonus =
        isWeapon ? active.weapon?.attackBonus : active.armor?.hpBonus;
    final String? storedName =
        isWeapon ? active.storedWeapon?.name : active.storedArmor?.name;
    final int? storedBonus = isWeapon
        ? active.storedWeapon?.attackBonus
        : active.storedArmor?.hpBonus;
    final bool ownsAny = equippedName != null || storedName != null;

    return AlertDialog(
      title: Text(isWeapon ? 'Arme trouvée !' : 'Tenue trouvée !'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // La carte trouvée, en grand (retours playtest : format portrait
            // 650x1004, contain — aucune déformation).
            Center(
              child: CardImage(
                category: isWeapon ? 'weapons' : 'armors',
                id: imageId,
                width: 220,
                height: 340,
                fit: BoxFit.contain,
                fallbackIcon: isWeapon ? Icons.flash_on : Icons.shield_outlined,
                fallbackIconColor: rarityColor,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Chip(
                  label: Text(
                    rarity.displayName,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w700),
                  ),
                  backgroundColor: rarityColor,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: rarityColor)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Bonus : +$bonus $unit',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.moveHighlight)),
            if (equippedBonus != null && bonus <= equippedBonus)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Bonus ${bonus == equippedBonus ? 'identique' : 'inférieur'} '
                    'à votre objet équipé (+$equippedBonus $unit).',
                    style: TextStyle(color: AppColors.danger)),
              ),
            if (!allowed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Niveau ${GameConstants.minLevelForRarity(rarity.index)} '
                    'requis (${rarity.displayName}) : à mettre en réserve '
                    'pour l’équiper plus tard.',
                    style: TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 10),
            Text('Votre équipement',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Équipé : ${equippedName ?? '— aucune'}'
                '${equippedBonus != null ? ' (+$equippedBonus $unit)' : ''}'),
            Text(
                'Réserve : ${storedName ?? '— vide'}'
                '${storedName != null && storedBonus != null ? ' (+$storedBonus $unit)' : ''}'
                '${storedName != null ? ' (sera remplacée)' : ''}'),
            if (!ownsAny)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Vous ne possédez encore aucun objet de ce type : '
                    'garder celui-ci est recommandé.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          // Refuser n'a de sens que si l'on possède déjà mieux
          // (retours playtest) : l'objet est détruit.
          onPressed: ownsAny
              ? () {
                  if (isWeapon) {
                    ref
                        .read(gameControllerProvider.notifier)
                        .declinePendingWeapon();
                  } else {
                    ref
                        .read(gameControllerProvider.notifier)
                        .declinePendingArmor();
                  }
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Refuser'),
        ),
        TextButton(
          onPressed: () {
            if (isWeapon) {
              ref.read(gameControllerProvider.notifier).storePendingWeapon();
            } else {
              ref.read(gameControllerProvider.notifier).storePendingArmor();
            }
            Navigator.of(context).pop();
          },
          child: const Text('Réserve'),
        ),
        FilledButton(
          onPressed: allowed ? () => _equipWithChoice(context, ref) : null,
          child: const Text('Équiper'),
        ),
      ],
    );
  }
}
