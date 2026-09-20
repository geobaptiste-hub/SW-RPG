import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/character_constants.dart';
import '../../core/constants/enums.dart';
import '../../core/constants/planet_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/card_image.dart';
import '../../models/planet.dart';
import '../../services/game_service.dart';
import '../../widgets/app_background.dart';
import '../../widgets/screen_music.dart';

/// Assistant de création de partie (CDC §4) :
///  - Étape 1 : mode (chacun pour soi / équipes) ;
///  - Étape 2 : nombre de joueurs (2 à 8) ou formation d'équipes
///    (2v2, 3v3, 4v4) ;
///  - Étape 3 : choix de la planète de départ, avec aperçu ;
///  - Étape 4 : choix des personnages, sélection à tour de rôle.
class NewGameScreen extends ConsumerStatefulWidget {
  const NewGameScreen({super.key});

  @override
  ConsumerState<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  // Big Four : 3 étapes (Mode → Planète → Créer, équipes imposées).
  int get totalSteps => _mode == GameMode.bigFour ? 3 : 4;

  int _step = 1;
  GameMode? _mode;
  int? _playerCount;
  int? _teamSize; // 0 en chacun pour soi ; 2, 3 ou 4 en mode équipes.
  PlanetType? _planetType;
  final List<CharacterDefinition?> _picks = <CharacterDefinition?>[];
  int _draftIndex = 0;
  bool _creating = false;

  int get _totalPlayers => _playerCount ?? 0;

  bool get _stepValid {
    switch (_step) {
      case 1:
        return _mode != null;
      case 2:
        return _playerCount != null;
      case 3:
        return _planetType != null;
      case 4:
        return _picks.length == _totalPlayers &&
            _picks.every((CharacterDefinition? pick) => pick != null);
      default:
        return false;
    }
  }

  void _goToStep(int step) => setState(() {
        _step = step.clamp(1, totalSteps);
      });

  void _chooseMode(GameMode mode) => setState(() {
        _mode = mode;
        // Le changement de mode réinitialise les étapes suivantes.
        _playerCount = null;
        _teamSize = null;
        _picks.clear();
        _draftIndex = 0;
        if (mode == GameMode.bigFour) {
          // Équipes imposées par faction (retours playtest) : Leia+Padmé,
          // Luke+Yoda, Vador+Nihilus, Empereur+Tarkin — 8 joueurs, pas de
          // choix de personnage.
          _playerCount = 8;
          _teamSize = 2;
          const List<String> order = <String>[
            'princesse_leia', 'padme_amidala', // Équipe Rebel
            'luke_skywalker', 'yoda', // Équipe Jedi
            'dark_vador', 'darth_nihilus', // Équipe Sith
            'empereur_palpatine', 'grand_moff_tarkin', // Équipe Empire
          ];
          _picks.addAll(<CharacterDefinition?>[
            for (final String id in order)
              CharacterConstants.characters
                  .firstWhere((CharacterDefinition c) => c.id == id),
          ]);
          _draftIndex = 8;
        }
      });

  void _choosePlayerCount(int playerCount, int teamSize) => setState(() {
        _playerCount = playerCount;
        _teamSize = teamSize;
        _picks.clear();
        _draftIndex = 0;
      });

  void _choosePlanet(PlanetType planet) => setState(() => _planetType = planet);

  /// Touche un personnage : s'il est déjà pris, on ANNULE son choix (et
  /// les choix suivants — retours playtest) ; sinon on le sélectionne.
  void _onCharacterTap(CharacterDefinition character) {
    final int slot =
        _picks.indexWhere((CharacterDefinition? p) => p?.id == character.id);
    if (slot >= 0) {
      _unpickFrom(slot);
      return;
    }
    if (!_stepValid) {
      _pickCharacter(character);
    }
  }

  /// Revient au joueur [slot] : les choix effectués à partir de lui sont
  /// annulés (draft linéaire — le choix de l'Équipe A ne fige rien).
  void _unpickFrom(int slot) {
    setState(() {
      if (slot < _picks.length) {
        _picks.removeRange(slot, _picks.length);
      }
      _draftIndex = slot;
    });
  }

  void _pickCharacter(CharacterDefinition character) {
    if (_picks.any((CharacterDefinition? p) => p?.id == character.id)) {
      // Retours playtest v3 : un clic sans effet ressemblait à un blocage.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${character.name} est déjà choisi : chaque '
              'personnage ne peut être pris qu’une seule fois.'),
        ),
      );
      return;
    }
    setState(() {
      if (_picks.length == _draftIndex) {
        _picks.add(character);
      } else {
        _picks[_draftIndex] = character;
      }
      if (_draftIndex < _totalPlayers) _draftIndex++;
    });
  }

  Future<void> _createGame() async {
    if (!_stepValid || _creating) return;
    setState(() => _creating = true);

    final NewGameConfig config = NewGameConfig(
      mode: _mode!,
      playerCount: _totalPlayers,
      teamSize: _teamSize ?? 0,
      planetType: _planetType!,
      characters: _picks.cast<CharacterDefinition>(),
    );

    try {
      await ref.read(gameControllerProvider.notifier).createNewGame(config);
      if (!mounted) return;
      context.go('/board');
    } catch (error) {
      // Sans ça, une erreur laissait _creating à true : écran bloqué.
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la création : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Nouvelle Partie \u2014 \u00c9tape $_step/$totalSteps'),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/'),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                // Big Four : l'étape 2 (nombre de joueurs) n'existe pas.
                onPressed: () =>
                    _goToStep(_step == 3 && _mode == GameMode.bigFour
                        ? 1
                        : _step - 1),
              ),
      ),
      body: ScreenMusic(
        track: 'preparation',
        child: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              LinearProgressIndicator(
                value: _step / totalSteps,
                minHeight: 4,
                color: AppColors.gold,
                backgroundColor: Colors.white10,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: switch (_step) {
                          1 => _buildStepMode(textTheme),
                          2 => _buildStepPlayerCount(textTheme),
                          3 => _buildStepPlanet(textTheme),
                          _ => _buildStepCharacters(textTheme),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Étape 1 — Mode
  // ---------------------------------------------------------------------------

  Widget _buildStepMode(TextTheme textTheme) {
    return Column(
      key: const ValueKey<int>(1),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mode de jeu', style: textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Choisissez comment la partie sera jouée.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _ModeCard(
          title: 'Chacun pour soi',
          subtitle: '2 à 8 joueurs, chacun joue pour soi (GDD §1).',
          icon: Icons.person,
          selected: _mode == GameMode.chacunPourSoi,
          onTap: () => _chooseMode(GameMode.chacunPourSoi),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          title: 'Équipes',
          subtitle: '2 vs 2, 3 vs 3 ou 4 vs 4 (GDD §1).',
          icon: Icons.groups,
          selected: _mode == GameMode.equipes,
          onTap: () => _chooseMode(GameMode.equipes),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          title: 'Big Four',
          subtitle: '4 équipes de 2 par faction : Rebel, Jedi, Sith et '
              'Empire (8 joueurs, équipes imposées).',
          icon: Icons.workspace_premium,
          selected: _mode == GameMode.bigFour,
          onTap: () => _chooseMode(GameMode.bigFour),
        ),
        const SizedBox(height: 24),
        FilledButton(
          // Big Four : l'étape « nombre de joueurs » n'existe pas.
          onPressed: _stepValid
              ? () => _goToStep(_mode == GameMode.bigFour ? 3 : 2)
              : null,
          child: const Text('Continuer'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Étape 2 — Nombre de joueurs
  // ---------------------------------------------------------------------------

  Widget _buildStepPlayerCount(TextTheme textTheme) {
    final bool isTeams = _mode == GameMode.equipes;
    return Column(
      key: const ValueKey<int>(2),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isTeams ? 'Formation des équipes' : 'Nombre de joueurs',
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          isTeams
              ? 'Choisissez la taille des équipes.'
              : 'De 2 à 8 joueurs (CDC §4).',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (!isTeams)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (int n = 2; n <= 8; n++)
                _CountChip(
                  label: '$n joueurs',
                  selected: _playerCount == n,
                  onTap: () => _choosePlayerCount(n, 0),
                ),
            ],
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final int size in const [2, 3, 4])
                _CountChip(
                  label: '$size vs $size',
                  selected: _teamSize == size,
                  onTap: () => _choosePlayerCount(size * 2, size),
                ),
            ],
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _stepValid ? () => _goToStep(3) : null,
          child: const Text('Continuer'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Étape 3 — Planète (avec aperçu graphique, CDC §4)
  // ---------------------------------------------------------------------------

  Widget _buildStepPlanet(TextTheme textTheme) {
    return Column(
      key: const ValueKey<int>(3),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Planète de départ', style: textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Les joueurs choisissent ensemble la planète de départ (GDD addendum).',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        for (final PlanetType planet in PlanetConstants.startPlanets) ...[
          _PlanetCard(
            planet: planet,
            selected: _planetType == planet,
            onTap: () => _choosePlanet(planet),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        if (_mode == GameMode.bigFour) ...<Widget>[
          Text(
            'Les 4 équipes sont imposées : Équipe Rebel (Princesse Leia, '
            'Padmé Amidala), Équipe Jedi (Luke Skywalker, Yoda), Équipe '
            'Sith (Dark Vador, Dark Nihilus) et Équipe Empire (L’empereur, '
            'Grand Moff Tarkin).',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _stepValid && !_creating ? _createGame : null,
            child: _creating
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Créer la partie'),
          ),
        ] else ...<Widget>[
          FilledButton(
            onPressed: _stepValid ? () => _goToStep(4) : null,
            child: const Text('Continuer'),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Étape 4 — Personnages (sélection à tour de rôle, CDC §4)
  // ---------------------------------------------------------------------------

  Widget _buildStepCharacters(TextTheme textTheme) {
    final bool draftDone = _stepValid;
    final bool isTeams = _mode == GameMode.equipes;

    return Column(
      key: const ValueKey<int>(4),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Personnages', style: textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          draftDone
              ? 'Tous les personnages sont choisis.'
              : 'Sélection à tour de rôle — c\u2019est au ${_playerLabel(_draftIndex, isTeams)} '
                  'de choisir. Touchez un personnage déjà pris (ou sa '
                  'pastille) pour annuler ce choix.',
          style: textTheme.bodyMedium,
        ),
        // Retours playtest v3 : la bascule entre les deux équipes doit être
        // ÉVIDENTE (l'ancien en-tête discret donnait l'impression d'un blocage).
        if (isTeams && !draftDone) ...[
          const SizedBox(height: 12),
          _TeamDraftBanner(
            side: TeamSide.values[(_draftIndex ~/ (_teamSize ?? 1))
                .clamp(0, TeamSide.values.length - 1)],
            previousSide: _draftIndex > 0
                ? TeamSide.values[((_draftIndex - 1) ~/ (_teamSize ?? 1))
                    .clamp(0, TeamSide.values.length - 1)]
                : null,
            justSwitched:
                _draftIndex > 0 && _draftIndex % (_teamSize ?? 1) == 0,
          ),
        ],
        const SizedBox(height: 20),
        // Récapitulatif des choix déjà faits.
        if (_picks.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _picks.length; i++)
                Tooltip(
                  message: 'Annuler ce choix (et les choix suivants)',
                  child: ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: AppColors.playerTokenColor(i),
                      radius: 8,
                    ),
                    label: Text(
                      '${_playerLabel(i, isTeams)} : ${_picks[i]?.name ?? '…'}',
                    ),
                    onPressed: () => _unpickFrom(i),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Grille des 8 personnages.
        for (final CharacterDefinition character
            in CharacterConstants.characters) ...[
          _CharacterCard(
            character: character,
            taken:
                _picks.any((CharacterDefinition? p) => p?.id == character.id),
            disabled: draftDone,
            onTap: () => _onCharacterTap(character),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: draftDone && !_creating ? _createGame : null,
          child: _creating
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Créer la partie'),
        ),
      ],
    );
  }

  String _playerLabel(int index, bool isTeams) {
    if (!isTeams) return 'Joueur ${index + 1}';
    // Blocs de _teamSize joueurs par équipe (Big Four : Rebel, Jedi,
    // Sith, Empire).
    final TeamSide side = TeamSide.values[(index ~/ (_teamSize ?? 1))
        .clamp(0, TeamSide.values.length - 1)];
    return '${side.displayName} — Joueur ${index + 1}';
  }
}

// ---------------------------------------------------------------------------
// Composants de l'assistant
// ---------------------------------------------------------------------------

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? AppColors.card : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon,
                  size: 34,
                  color: selected ? AppColors.gold : AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.gold : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? Colors.black87 : AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

/// Carte de planète avec aperçu graphique : dégradé aux couleurs de la
/// planète (GDD §4 : « sa propre ambiance visuelle, ses couleurs »).
// TODO(Polish) : remplacer l'aperçu dégradé par de vraies illustrations
// d'ambiance (GDD §4) au sprint Polish.
class _PlanetCard extends StatelessWidget {
  final PlanetType planet;
  final bool selected;
  final VoidCallback onTap;

  const _PlanetCard({
    required this.planet,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final PlanetVisual visual = PlanetConstants.visualFor(planet);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Row(
          children: [
            // Visuel de la planète : image si déposée
            // (assets/images/planets/), sinon dégradé d'ambiance (Sprint 6).
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CardImage(
                    category: 'planets',
                    id: planetImageId(planet),
                    width: 96,
                    height: 72,
                    fit: BoxFit.cover,
                    fallback: Container(
                      width: 96,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(visual.primaryColor),
                            Color(visual.accentColor),
                          ],
                        ),
                      ),
                      child:
                          const Icon(Icons.public, color: Colors.black38),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PlanetConstants.displayNames[planet] ?? planet.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text('Planète de départ',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.gold : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Bannière d'état du draft en mode Équipes : équipe en train de choisir,
/// avec une mise en évidence forte au passage de l'Équipe A à l'Équipe B.
class _TeamDraftBanner extends StatelessWidget {
  final TeamSide side;

  /// Équipe qui vient d'être complétée (bannière de bascule).
  final TeamSide? previousSide;

  /// Vrai quand le draft bascule vers l'équipe suivante.
  final bool justSwitched;

  const _TeamDraftBanner({
    required this.side,
    required this.justSwitched,
    this.previousSide,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.teamColor(side);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(justSwitched ? Icons.celebration : Icons.groups, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              justSwitched
                  ? '✅ ${previousSide?.displayName ?? 'L\'équipe précédente'} '
                      'complète — à ${side.displayName} de choisir !'
                  : 'Sélection en cours : ${side.displayName}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final CharacterDefinition character;
  final bool taken;
  final bool disabled;
  final VoidCallback onTap;

  const _CharacterCard({
    required this.character,
    required this.taken,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color factionColor = AppColors.factionColor(character.faction);
    final bool interactive = !taken && !disabled;
    // Une carte déjà prise reste tappable : le tap DÉSÉLECTIONNE (retours
    // playtest — pouvoir changer d'avis après une erreur).

    return Opacity(
      opacity: taken ? 0.45 : 1,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: (taken || interactive) ? onTap : null,
          child: Row(
            children: [
              Container(
                width: 6,
                height: 56,
                decoration: BoxDecoration(
                  color: factionColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              CardImage(
                category: 'characters',
                id: cardImageId(character.name),
                size: 44,
                fallback: CircleAvatar(
                  radius: 20,
                  backgroundColor: factionColor.withValues(alpha: 0.25),
                  child: Text(
                    character.name.characters.first,
                    style: TextStyle(
                        color: factionColor, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(character.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(character.faction.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: factionColor)),
                  ],
                ),
              ),
              if (taken)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Tooltip(
                    message: 'Annuler ce choix',
                    child: Icon(Icons.undo, size: 18,
                        color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
