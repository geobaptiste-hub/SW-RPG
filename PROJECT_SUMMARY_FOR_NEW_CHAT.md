# PROJECT_SUMMARY — Star Wars RPG (passation de contexte)

**Dernière mise à jour : 08/09/2026 — après Sprints 1→4.3 et démarrage du Sprint 5.**
Lis ce fichier en entier avant de toucher au code : il contient l'état réel, les décisions actées, les pièges de l'environnement et les prochaines étapes.

## 1. Le jeu en une page
- **Star Wars RPG** : jeu de plateau RPG tour par tour, local (hot-seat), 2–8 joueurs sur une tablette (iPad cible ; build Windows = banc de test). Durée 30–45 min.
- **Stack** : Flutter 3.47.2 · Dart 3.13.2 · Riverpod 2.x (Notifier) · GoRouter 14.x · Hive (JSON brut, pas de build_runner) · aucun moteur de jeu (Impeller natif).
- **Boucle** : lancer le dé (1–6 = points de déplacement) → se déplacer case par case sur un plateau procédural 20×20 (300 jouables / 100 bloquées, connecté) en révélant le brouillard → rencontrer monstres/alliés/objets/soins/players/boss → fin de tour (rotation + autosave) → répéter jusqu'à la victoire.
- **Victoire** : chacun pour soi = dernier survivant OU 3 boss de factions adverses vaincus ; équipes = équipe adverse éliminée OU 3 boss différents vaincus par l'équipe.

## 2. Règles principales (implémentées)
- **Plateau** 20×20, 300 jouables / 100 bloquées, connecté ; 8 départs fixes (coins + milieux) ; brouillard 3 états (masqué/découvert/visible), rayon **3** (Chebyshev 7×7), découvertes cumulatives ; pions masqués hors zone découverte.
- **Phases** (début/milieu/fin selon N3/N5 des joueurs) : la table d'événements change — monstre 40/30/25 %, allié 20/25/20 %, objet 10/20/30 %, soin 8/10/5 %, portail —/5/5 %.
- **Contenu des cases tiré à la première découverte** (jamais sur départs ni occupées, une seule fois par case).
- **Dé** : 1–6 = points de déplacement ; le monstre riposte après chaque attaque non létale ; critique sur 6 = dégâts ×2.
- **Équipe** : 10 PP ; allié de faction ennemie = attaque immédiate (nuker : valeur Excel du porteur ; autres : rareté 50/100/200/300/400) ; escouades regroupées à l'écran avec bonus cumulé GDD ((somme) × nombre).
- **Équipement** : 1 arme + 1 tenue équipées, **+ réserve 1 arme + 1 tenue** (échange en un clic) ; rareté limitée par niveau (Commun ≤ N2 … Mythique N6).
- **Soin** : case événement → dé dédié animé → 10/20/50/100/150/300 PV (plafonné), case consommée.
- **Boss** : apparaissent sur les planètes secondaires générées quand un joueur atteint le N5 ; verrou avant N5 (entrée refusée, point perdu) ; riposte 250–500 par attaque (÷2 avec tank) ; victoire = XP de rang 400/300/200/100 + fuite (réapparition en zone non découverte) ; mort définitive quand tous les joueurs actifs l'ont vaincu.
- **Spéciales (Vador, Leia…)** : cartes ennemies = -500 PV directs, jamais recrutables ; alliées = recrutables (5 PP).
- **Fin de tour** : rotation (les éliminés sont sautés, tour++ au retournement), révélation autour du nouveau joueur, déplacement des boss, autosave Hive.
- **Journal de partie** : Sprint 6.

## 3. Architecture technique (réelle)
- **lib/main.dart** : Hive.initFlutter → ProviderScope → MaterialApp.router (thème sombre custom, GoRouter).
- **lib/core/router/app_router.dart** : routes `/`, `/new-game`, `/board`, `/character`, `/team`, `/players`, `/inventory`, `/settings`, `/credits`.
- **lib/services/game_service.dart** : `GameController extends Notifier<GameState?>` (`gameControllerProvider`) — createNewGame, resumeGame, exitGame, rollDice, moveActivePlayerTo (→ MoveResult), validMoveTargets, endTurn (rotation + populate + boss move + autosave), tickGameTime, applyXpGain, applyMonsterVictory, applyBossVictory, applyPlayerCombatResult, applyPlayerDefeat, applyPlayerCombatHp, recruitPendingAlly/declinePendingAlly, equipPending*/storePending*/equipStored*, discardAlly, _applySurvivorCheck, _checkVictoryConditions (réel), _maybeSpawnBosses.
- **lib/services/map_service.dart** : generateStartPlanet (20×20 procédural connecté, seed), generateSecondaryPlanet (8×7, 50 jouables), revealFogAround (rayon 3, Chebyshev), populateNewlyDiscoveredTiles (→ record `planet` + `newPortals`), validMoveTargets, moveBossesAtTurnEnd (réel, 50 %).
- **lib/services/combat_service.dart** : CombatService (RNG injectable, rollAttackDice, rollBossAttack, critique ×2) + CombatSession (kind monster/player/boss) + CombatController (startMonsterCombat, startPlayerCombat, attack, flee, leave).
- **lib/services/save_service.dart** : box Hive `star_wars_rpg` / clé `current_game`, JSON brut, tolérant aux corruptions.
- **lib/widgets/** : board_widget (InteractiveViewer + caméra + BoardWidgetController pour Recentrer), board_camera (math pure, testée), tile/fog/player_token/dice.
- **lib/core/constants/** : toutes les valeurs de règles et de données (deck Excel, probabilités par phase, tables de progression).
- **Sauvegarde** : GameState complet en JSON dans Hive (box `star_wars_rpg`, clé `current_game`) ; compat ascendante par champs optionnels (schemaVersion = 1).

## 4. Décisions de game design actées (chronologie)
- 07/09 : rayon 3 (7×7) ; soin au dé 10→300 ; allié ennemi = dégâts selon rareté ; stockage 1 arme + 1 tenue ; healers Dark Sion/Mère Talzin → Sith ; nuker Scout Trooper ajouté ; L'empereur = 3000 XP N6 (typo Excel) ; factions Excel (Luke Jedi, Padmé Rebel, Vador Sith, L'empereur Empire) ; nukers = effet selon porteur.
- 08/09 : monstre = riposte par attaque ; fuite en combat ; carte 20×20 ; allié ennemi = dégâts directs (pas de recrutement) ; spéciale ennemie = -500 PV directs, non recrutable ; escouades = formule GDD littérale ((somme) × nombre) et regroupement à l'écran ; soin plus rare (8/5/5 %) ; victoire par boss = 3 factions adverses.

## 5. État actuel du développement (au 08/09/2026)
- **Compilé et fonctionnel** : `flutter analyze` = 0 problème · **77/77 tests verts** · `flutter build windows --debug` OK · app exécutable (`build/windows/x64/runner/Debug/star_wars_rpg.exe`).
- **Sprints terminés** : 1 (base+combat monstre), 2 (brouillard/galaxie/navigation), 3 (monstres/combat/XP/niveaux), 4 (objets/alliés/inventaire), 4.1 (équilibrage 20×20, malus, rareté), 4.2 (rencontre auto, soin rare, dialog recrutement avec défausse), 4.3 (spéciales ennemies -500, escouades formule GDD + regroupement, boutons retour).
- **Sprint 5 : EN COURS (~60 %)** — ce qui EST en place :
  - Constantes et deck boss (`monster_constants.bossNames`, GameConstants boss*), `PlanetConstants` : grille secondaire 8×7/50/6, portail central (3,3), `bossFactionByType`, `secondaryPortalPosition`.
  - `CombatService.rollBossAttack()` (250–500 pas de 10), `CombatKind.boss`, `CombatSession.bossType`.
  - `GameService` : `_maybeSpawnBosses()` (apparition au N5, position la plus éloignée du portail), `applyBossVictory()` (XP de rang + fuite/mort définitive + marque defeatedByPlayerIds), `_applySurvivorCheck` (réel), `_checkVictoryConditions` (réel : 3 boss factions adverses / équipe union).
  - Carte 20×20 → planète secondaire générée à la découverte du portail.
- **Sprint 5 : RESTE À FAIRE (dans l'ordre)** :
  1. **CombatController.startBossCombat(Boss)** + branche boss dans `attack()` (riposte 250–500 par pas de 10, mort du joueur, XP de rang) + `flee()` autorisé en combat de boss.
  2. **BoardScreen._handleMoveTap** : branches `bossEncounter` (→ startBossCombat + `/combat`), `bossBlocked` (dialog « trop puissant »), `portalTravel` (dialog « 🌌 Vous voyagez vers … »).
  3. **BoardWidget** : rendre les portails (state.portals découverts, icône dorée) et les boss (icône par type) ; masquer les pions des autres planètes.
  4. **HUD** : ajouter le nom de la planète courante (chip).
  5. **Notifications** : snackbars « 🌌 X se dévoile ! » et « ⚡ Un boss s'éveille sur X ! » (transients `lastPortalDiscoveries` / `bossAwakeningPlanets` déjà dans GameController).
  6. **Écran Game Over** : route `/game-over` + `game_over_screen.dart` (gagnant, stats, boutons) — le dialog provisoire du board est à remplacer.
  7. **Tests Sprint 5** (voir « à écrire » ci-dessous) puis full green + build.

## 6. Pièges de l'environnement (IMPORTANT pour le prochain chat)
- **Ne jamais écrire de longues commandes Bash** (> ~150 lignes) : elles sont TRONQUÉES silencieusement → fichiers corrompus. Écrire les fichiers par morceaux de ≤ 120 lignes (cat > puis cat >>).
- Le contrôle de permissions peut **repasser en mode plan de façon fantôme** et refuser toute écriture (« Plan mode only allows read-only… ») : appeler ExitPlanMode à nouveau avec un plan court pour rouvrir la fenêtre d'écriture (a fonctionné à chaque fois).
- **Flutter n'est pas dans le PATH Git Bash** : toujours `export PATH="/c/flutter-sdk/3.47.2/bin:$PATH"` avant flutter/dart.
- **python3 n'existe pas** (Windows) : utiliser `python`. Les heredocs Python doivent éviter les apostrophes typographiques dans les ancres.
- `GDD.docx`/`CDC.docx` peuvent être **verrouillés par Word** (PermissionError) : réessayer après fermeture.
- Les **clics par coordonnées** de computer-use sont cassés dans cette session (erreur de binding de frame) : utiliser les **éléments AX** (accessibilité) ou le clavier (Tab/Entrée), ou PowerShell SetCursorPos+mouse_event pour un clic réel.
- Après modification du code : `flutter analyze` puis `flutter test` PUIS `flutter build windows --debug`, puis relancer l'exe pour le test manuel.

## 7. Commandes utiles
```bash
export PATH="/c/flutter-sdk/3.47.2/bin:$PATH"
cd "/c/Users/stone/Documents/Jeux perso/SW/Code"
flutter analyze && flutter test
flutter build windows --debug
./build/windows/x64/runner/Debug/star_wars_rpg.exe
```
- VM service (debug) affiché au lancement — dump widget tree : `ext.flutter.debugDumpApp` via HTTP sur l'URI du VM service.

## 8. Prochaines étapes recommandées (ordre)
1. **Finir le Sprint 5** (voir §5) : combat de boss, câblage plateau, game over, tests.
2. **Sprint 6 — Polish** : images des cartes (convention : `Code/assets/images/<catégorie>/<id>.png`, liste complète dans `SW/MD/images-cartes.md` — ajouter le dossier assets au pubspec), journal de partie (GDD §14), pause du chrono hors app, écran Paramètres réel (son, reset), écran de victoire complet, dépréciations Radio éventuelles.
3. **Équilibrage** : les valeurs ajustables sont dans `game_constants.dart` (probabilités par phase, soin, XP) et `card_constants.dart` (deck).
4. **Releases** : `flutter build windows --release`, puis signer/build Android/iPad quand le gameplay est validé.

## 9. Rappel des sources de vérité
- **Règles** : `SW/MD/GDD_vFinal.md` (design réel) + addenda dans GDD/CDC (.txt/.docx).
- **Spec d'implémentation** : `SW/MD/Architecture_Flutter_vFinal.md` + `SW/MD/Cahier_des_Charges_vFinal.md`.
- **Données de cartes** : `SW/Données/Données cartes.xlsx` (référence ; healers corrigés en Sith par le code — mettre à jour l'Excel).
- **Tests** = garde-fou : toute règle modifiée doit passer par les tests existants.
