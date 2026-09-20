import io

p = 'lib/screens/new_game/new_game_screen.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

# 1) totalSteps dynamique
patch(
    "class _NewGameScreenState extends ConsumerState<NewGameScreen> {\n  static const int totalSteps = 4;",
    """class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  // Big Four : 3 étapes (Mode → Planète → Créer, équipes imposées).
  int get totalSteps => _mode == GameMode.bigFour ? 3 : 4;""")

# 2) _chooseMode : préremplir Big Four
patch(
    """  void _chooseMode(GameMode mode) => setState(() {
        _mode = mode;
        // Le changement de mode réinitialise les étapes suivantes.
        _playerCount = null;
        _teamSize = null;
        _picks.clear();
        _draftIndex = 0;
      });""",
    """  void _chooseMode(GameMode mode) => setState(() {
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
      });""")

# 3) étape 1 : carte mode Big Four + Continuer qui saute l'étape 2
patch(
    """        _ModeCard(
          title: 'Équipes',
          subtitle: '2 vs 2, 3 vs 3 ou 4 vs 4 (GDD §1).',
          icon: Icons.groups,
          selected: _mode == GameMode.equipes,
          onTap: () => _chooseMode(GameMode.equipes),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _stepValid ? () => _goToStep(2) : null,
          child: const Text('Continuer'),
        ),""",
    """        _ModeCard(
          title: 'Équipes',
          subtitle: '2 vs 2, 3 vs 3 ou 4 vs 4 (GDD §1).',
          icon: Icons.groups,
          selected: _mode == GameMode.equipes,
          onTap: () => _chooseMode(GameMode.equipes),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          title: 'Big Four',
          subtitle:
              '4 équipes de 2 par faction : Rebel, Jedi, Sith et Empire '
              '(8 joueurs, équipes imposées).',
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
        ),""")

# 4) étape planète : bouton Créer en Big Four + retour vers l'étape 1
patch(
    """        const SizedBox(height: 12),
        FilledButton(
          onPressed: _stepValid ? () => _goToStep(4) : null,
          child: const Text('Continuer'),
        ),
      ],
    );
  }

  String _playerLabel(int index, bool isTeams) {
    if (!isTeams) return 'Joueur ${index + 1}';
    final TeamSide side =
        index < (_teamSize ?? 0) ? TeamSide.teamA : TeamSide.teamB;
    return '${side.displayName} — Joueur ${index + 1}';
  }""",
    """        const SizedBox(height: 12),
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

  String _playerLabel(int index, bool isTeams) {
    if (!isTeams) return 'Joueur ${index + 1}';
    // Blocs de _teamSize joueurs par équipe (Big Four : Rebel, Jedi, Sith,
    // Empire).
    final TeamSide side = TeamSide.values[(index ~/ (_teamSize ?? 1))
        .clamp(0, TeamSide.values.length - 1)];
    return '${side.displayName} — Joueur ${index + 1}';
  }""")

# 5) bannière : côté courant générique
patch(
    """          _TeamDraftBanner(
            side: _draftIndex < (_teamSize ?? 0)
                ? TeamSide.teamA
                : TeamSide.teamB,
            justSwitched: _draftIndex == (_teamSize ?? 0),
          ),""",
    """          _TeamDraftBanner(
            side: TeamSide.values[(_draftIndex ~/ (_teamSize ?? 1))
                .clamp(0, TeamSide.values.length - 1)],
            justSwitched: _draftIndex > 0 &&
                _draftIndex % (_teamSize ?? 1) == 0,
          ),""")

# 6) _TeamDraftBanner : previousSide
patch(
    """class _TeamDraftBanner extends StatelessWidget {
  final TeamSide side;

  /// Vrai au premier choix de l'Équipe B (l'Équipe A vient de compléter).
  final bool justSwitched;

  const _TeamDraftBanner({required this.side, required this.justSwitched});""",
    """class _TeamDraftBanner extends StatelessWidget {
  final TeamSide side;

  /// Équipe qui vient d'être complétée (bannière de bascule).
  final TeamSide? previousSide;

  /// Vrai quand le draft bascule vers l'équipe suivante.
  final bool justSwitched;

  const _TeamDraftBanner({
    required this.side,
    required this.justSwitched,
    this.previousSide,
  });""")

patch(
    """              justSwitched
                  ? '✅ Équipe A complète — à l’Équipe B de choisir !'
                  : 'Sélection en cours : ${side.displayName}',""",
    """              justSwitched
                  ? '✅ ${previousSide?.displayName ?? 'L’équipe précédente'} '
                      'complète — à ${side.displayName} de choisir !'
                  : 'Sélection en cours : ${side.displayName}',""")

# 7) bannière : previousSide calculé (l'équipe précédente = celle de
#    _draftIndex - 1)
patch(
    """          _TeamDraftBanner(
            side: TeamSide.values[(_draftIndex ~/ (_teamSize ?? 1))
                .clamp(0, TeamSide.values.length - 1)],
            justSwitched: _draftIndex > 0 &&
                _draftIndex % (_teamSize ?? 1) == 0,
          ),""",
    """          _TeamDraftBanner(
            side: TeamSide.values[(_draftIndex ~/ (_teamSize ?? 1))
                .clamp(0, TeamSide.values.length - 1)],
            previousSide: _draftIndex > 0
                ? TeamSide.values[((_draftIndex - 1) ~/ (_teamSize ?? 1))
                    .clamp(0, TeamSide.values.length - 1)]
                : null,
            justSwitched: _draftIndex > 0 &&
                _draftIndex % (_teamSize ?? 1) == 0,
          ),""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('new_game OK')
