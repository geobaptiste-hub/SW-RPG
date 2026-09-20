import io

# ---------- game_service : paramètre discardReplaced ----------
p = 'lib/services/game_service.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

patch(
    """  /// Équipe l'arme trouvée si la rareté est autorisée par le niveau ;
  /// l'arme équipée part en réserve (remplace l'éventuelle réserve).
  bool equipPendingWeapon() {
    final Weapon? found = pendingWeaponOffer;
    final GameState? current = state;
    if (found == null || current == null) return false;
    final Player active = current.activePlayer;
    if (!rarityAllowedForLevel(found.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      weapon: found,
      storedWeapon: active.weapon ?? active.storedWeapon,
      clearStoredWeapon: active.weapon == null,
    );
    state = current.copyWith(players: players);
    return true;
  }

  /// Équipe la tenue trouvée (même logique que l'arme).
  bool equipPendingArmor() {
    final Armor? found = pendingArmorOffer;
    final GameState? current = state;
    if (found == null || current == null) return false;
    final Player active = current.activePlayer;
    if (!rarityAllowedForLevel(found.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      armor: found,
      storedArmor: active.armor ?? active.storedArmor,
      clearStoredArmor: active.armor == null,
    );
    state = current.copyWith(players: players);
    return true;
  }""",
    """  /// Équipe l'arme trouvée si la rareté est autorisée par le niveau.
  /// Cas « équipée + réserve occupées » (retours playtest) :
  ///  - [discardReplaced] vrai  → l'ancienne équipée est DÉFAUSSÉE et la
  ///    réserve est PRÉSERVÉE ;
  ///  - [discardReplaced] faux  → l'ancienne équipée part en réserve et
  ///    remplace l'éventuelle réserve (comportement historique).
  bool equipPendingWeapon({bool discardReplaced = false}) {
    final Weapon? found = pendingWeaponOffer;
    final GameState? current = state;
    if (found == null || current == null) return false;
    final Player active = current.activePlayer;
    if (!rarityAllowedForLevel(found.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      weapon: found,
      storedWeapon: discardReplaced
          ? active.storedWeapon
          : (active.weapon ?? active.storedWeapon),
      clearStoredWeapon:
          discardReplaced ? false : active.weapon == null,
    );
    state = current.copyWith(players: players);
    pendingWeaponOffer = null;
    return true;
  }

  /// Équipe la tenue trouvée (même logique que l'arme).
  bool equipPendingArmor({bool discardReplaced = false}) {
    final Armor? found = pendingArmorOffer;
    final GameState? current = state;
    if (found == null || current == null) return false;
    final Player active = current.activePlayer;
    if (!rarityAllowedForLevel(found.rarity, active.level)) return false;
    final List<Player> players = List<Player>.of(current.players);
    players[current.currentPlayerIndex] = active.copyWith(
      armor: found,
      storedArmor: discardReplaced
          ? active.storedArmor
          : (active.armor ?? active.storedArmor),
      clearStoredArmor: discardReplaced ? false : active.armor == null,
    );
    state = current.copyWith(players: players);
    pendingArmorOffer = null;
    return true;
  }""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('game_service OK')

# ---------- ItemFoundDialog : sous-dialog de choix ----------
p = 'lib/screens/board/board_screen.dart'
s = io.open(p, encoding='utf-8').read()

patch(
    """        FilledButton(
          onPressed: allowed
              ? () {
                  if (isWeapon) {
                    ref
                        .read(gameControllerProvider.notifier)
                        .equipPendingWeapon();
                  } else {
                    ref
                        .read(gameControllerProvider.notifier)
                        .equipPendingArmor();
                  }
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Équiper'),
        ),""",
    """        FilledButton(
          onPressed: allowed
              ? () => _equipWithChoice(context, ref)
              : null,
          child: const Text('Équiper'),
        ),""")

patch(
    """  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool allowed =
        GameController.rarityAllowedForLevel(rarity, active.level);""",
    """  /// Équipe la trouvaille. Si équipée ET réserve sont occupées (3 objets
  /// pour 2 emplacements — retours playtest), demande quoi faire de
  /// l'ancienne équipée : DÉFAUSSÉE (réserve préservée) ou mise en
  /// réserve (remplace la réserve actuelle).
  Future<void> _equipWithChoice(BuildContext context, WidgetRef ref) async {
    final GameController controller =
        ref.read(gameControllerProvider.notifier);
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
            child: const Text('Défausser l\\'équipée'),
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
        GameController.rarityAllowedForLevel(rarity, active.level);""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('board_screen OK')
