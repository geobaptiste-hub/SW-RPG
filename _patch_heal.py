import io

# ---------- ally.dart : copyWith (charge de soin consommable) ----------
p = 'lib/models/ally.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

patch(
    """  /// La carte est-elle « amie » pour le porteur [ownerFaction] ?""",
    """  /// Copie avec remplacement de champs (limité aux champs mutables en
  /// jeu : la charge de soin des healers se consomme à l'usage).
  Ally copyWith({int? healInstant, bool clearHealInstant = false}) {
    return Ally(
      name: name,
      type: type,
      rarity: rarity,
      faction: faction,
      teamCost: teamCost,
      healAfterCombat: healAfterCombat,
      healInstant: clearHealInstant ? null : (healInstant ?? this.healInstant),
      hpBonus: hpBonus,
      dividesDamage: dividesDamage,
      squadBonusOwn: squadBonusOwn,
      squadBonusAllied: squadBonusAllied,
      bonusAtkIfFriendly: bonusAtkIfFriendly,
      bonusHpIfFriendly: bonusHpIfFriendly,
      instantDamageJedi: instantDamageJedi,
      instantDamageRebel: instantDamageRebel,
      bonusIfSithOwner: bonusIfSithOwner,
      bonusIfEmpireOwner: bonusIfEmpireOwner,
      ability: ability,
      effectText: effectText,
    );
  }

  /// La carte est-elle « amie » pour le porteur [ownerFaction] ?""")

# effectSummary des healers : le soin immédiat est une charge activable
patch(
    """      case AllyType.healer:
        return 'Soin après combat : +$healAfterCombat PV · '
            'Recrutement : +$healInstant PV';""",
    """      case AllyType.healer:
        return 'Soin après combat : +$healAfterCombat PV · '
            'Charge de soin : +$healInstant PV (à activer depuis '
            'l\\'équipe)';""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('ally OK')

# ---------- game_service : heal en charge ----------
p = 'lib/services/game_service.dart'
s = io.open(p, encoding='utf-8').read()

# 1) plus de soin automatique au recrutement (la charge est activable
#    depuis l'écran Équipe)
patch(
    """    Player updated = active.copyWith(allies: <Ally>[...active.allies, ally]);
    if (ally.healInstant != null) {
      final int hp = min(updated.hp + ally.healInstant!, updated.totalMaxHp);
      updated = updated.copyWith(hp: hp);
    }
    if (ally.faction != active.faction &&""",
    """    // Soin instantané du healer : plus d'application automatique au
    // recrutement (retours playtest) — c'est désormais une CHARGE que le
    // joueur active quand il veut depuis l'écran Équipe
    // (GameController.useHealerHeal).
    Player updated = active.copyWith(allies: <Ally>[...active.allies, ally]);
    if (ally.faction != active.faction &&""")

# 2) useHealerHeal : activer la charge
patch(
    """  /// Consomme la carte soutien « attaque ×dé » du joueur actif (usage
  /// unique).
  void consumeAttackTimesDice() {""",
    """  /// Active la charge de soin immédiat d'un healer de l'équipe
  /// (retours playtest : le joueur soigne QUAND IL VEUT depuis l'écran
  /// Équipe). La charge est consommée après usage. Renvoie false si
  /// l'allié n'a pas de charge, si le joueur est full PV ou si l'index
  /// est invalide.
  bool useHealerHeal(int allyIndex) {
    final GameState? current = state;
    if (current == null) return false;
    final Player active = current.activePlayer;
    if (allyIndex < 0 || allyIndex >= active.allies.length) return false;
    final Ally healer = active.allies[allyIndex];
    final int? amount = healer.healInstant;
    if (amount == null || amount <= 0) return false;
    if (active.hp >= active.totalMaxHp) return false;

    final int healed = min(amount, active.totalMaxHp - active.hp);
    final List<Ally> allies = List<Ally>.of(active.allies);
    allies[allyIndex] = healer.copyWith(clearHealInstant: true);
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      hp: active.hp + healed,
      allies: allies,
    );
    state = current.copyWith(players: players);
    log('💚 ${active.name} est soigné de $healed PV par ${healer.name}.');
    return true;
  }

  /// Consomme la carte soutien « attaque ×dé » du joueur actif (usage
  /// unique).
  void consumeAttackTimesDice() {""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('game_service OK')

# ---------- team_screen : bouton Soigner sur la carte du healer ----------
p = 'lib/screens/team/team_screen.dart'
s = io.open(p, encoding='utf-8').read()

patch(
    """                              Expanded(
                                child: _AllyColumnCard(
                                  ally: active.allies[index],
                                  onStore: () => controller.storeTeamAlly(index),
                                  onDiscard: () =>
                                      _confirmDiscard(context, controller, index),
                                ),
                              ),""",
    """                              Expanded(
                                child: _AllyColumnCard(
                                  ally: active.allies[index],
                                  onHeal: active.allies[index].healInstant !=
                                              null &&
                                          active.hp < active.totalMaxHp
                                      ? () =>
                                          controller.useHealerHeal(index)
                                      : null,
                                  healAmount:
                                      active.allies[index].healInstant,
                                  onStore: () => controller.storeTeamAlly(index),
                                  onDiscard: () =>
                                      _confirmDiscard(context, controller, index),
                                ),
                              ),""")

patch(
    """class _AllyColumnCard extends StatelessWidget {
  final Ally ally;
  final VoidCallback onDiscard;

  /// Mise en réserve (échange avec l'allié stocké s'il y en a un).
  final VoidCallback onStore;

  /// Nombre de copies pour les escouades regroupées (« ×2 »).
  final String? countLabel;

  const _AllyColumnCard({
    required this.ally,
    required this.onDiscard,
    required this.onStore,
    this.countLabel,
  });""",
    """class _AllyColumnCard extends StatelessWidget {
  final Ally ally;
  final VoidCallback onDiscard;

  /// Mise en réserve (échange avec l'allié stocké s'il y en a un).
  final VoidCallback onStore;

  /// Charge de soin du healer : bouton actif si non null (retours
  /// playtest — soigner quand on veut depuis l'équipe).
  final VoidCallback? onHeal;
  final int? healAmount;

  /// Nombre de copies pour les escouades regroupées (« ×2 »).
  final String? countLabel;

  const _AllyColumnCard({
    required this.ally,
    required this.onDiscard,
    required this.onStore,
    this.onHeal,
    this.healAmount,
    this.countLabel,
  });""")

patch(
    """            Text(
              '${ally.teamCost} place${ally.teamCost > 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: 'Mettre en réserve (échange avec l’allié stocké)',
                  icon: const Icon(Icons.archive_outlined,
                      size: 20, color: Colors.white70),
                  onPressed: onStore,
                ),
                IconButton(
                  tooltip: 'Défausser',
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.white38),
                  onPressed: onDiscard,
                ),
              ],
            ),""",
    """            Text(
              '${ally.teamCost} place${ally.teamCost > 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            if (onHeal != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.icon(
                  icon: const Icon(Icons.healing, size: 18),
                  label: Text('Soigner +$healAmount PV',
                      overflow: TextOverflow.ellipsis),
                  onPressed: onHeal,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: 'Mettre en réserve (échange avec l’allié stocké)',
                  icon: const Icon(Icons.archive_outlined,
                      size: 20, color: Colors.white70),
                  onPressed: onStore,
                ),
                IconButton(
                  tooltip: 'Défausser',
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.white38),
                  onPressed: onDiscard,
                ),
              ],
            ),""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('team_screen OK')
