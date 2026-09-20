# Sprint 5 — Boss, Portails, Planètes secondaires, Victoire

## Décisions actées (08/09/2026)
- **Portails aller-retour miroir** : portail du plateau → portail central de la secondaire ; portail central → retour à la position du portail d'origine.
- **Victoire par boss : 3 boss de factions adverses** (ex. Rebel → Krayt Dragon, AT-AT, Exogorth ; son boss propre ne compte pas). En équipe : l'union des boss vaincus par l'équipe doit couvrir 3 boss différents (documenté — règle ajustable).
- **Boss apparition au N5** : la planète secondaire se génère à la découverte de son portail (N3, sans boss) ; le boss apparaît sur elle dès qu'un joueur atteint le N5.
- **Journal de partie** : Sprint 6.

## 1. Modèles et état (multi-planètes)
- `Player` : + `planet` (PlanetType, défaut = planète de départ, sérialisé, compat anciennes sauvegardes) et + `returnPlanet`/`returnPosition` (retour de portail, transit).
- `GameState` : + `planets` (Map<PlanetType, Planet> — la principale y entre aussi) ; `currentPlanet` = planète du joueur actif (dénormalisée, conservée) ; sérialisation liste `[{type, planet}]`, tolérante aux anciennes sauvegardes (défaut : la planète principale).
- `Tile` : inchangé (le portail de retour est implicite : case centrale des planètes secondaires).
- Constantes : `GameConstants.specialEnemyDamage` existe ; + `GameConstants.bossFactionByType` (exogorth→Sith, kraytDragon→Rebel, atAt→Empire, rancor→Jedi — table GDD) ; `PlanetConstants.secondaryPlanetGrid = 8×7` (56 cases → 50 jouables / 6 bloquées, TODO du fichier résolu).

## 2. Planètes secondaires (MapService)
- `generateSecondaryPlanet(type, {seed})` : réutilisation de l'algorithme existant paramétré (8×7, 50 jouables / 6 bloquées, connectivité garantie, **case centrale protégée** — portail de retour). Nettoyage du doc-comment périmé de `generateStartPlanet` (20×20/300/100).
- Génération **à la découverte du portail** (pas avant) ; une seule fois par type.
- Population des événements : mêmes tables que la principale (phase courante).

## 3. Portails
- **Apparition** (à la découverte, dans `populateNewlyDiscoveredTiles`) : événement « portail » (5 % milieu, 5 % fin) → si la case est sur le **bord** du plateau et que moins de 4 portails existent → la case devient un portail vers une planète secondaire **non encore liée** (aléatoire) ; la planète secondaire liée est **générée immédiatement** + notification « 🌌 {planète} se dévoile ! » (transient `lastPortalDiscovery` sur le controller, dialog à l'écran).
- **Voyage** (GameService.moveActivePlayerTo) : entrer sur une case portail → téléportation au **portail central de la planète secondaire** (centre de la grille), révélation autour du point d'arrivée, `Player.planet`/`returnPlanet`/`returnPosition` mis à jour, `state.currentPlanet` basculée. Entrer sur le portail central d'une secondaire → retour à `returnPosition`.
- BoardScreen : dialog/snackbar « 🌌 {planète} se dévoile ! » à la découverte ; HUD : **nom de la planète courante** ajouté.

## 4. Boss
- **Apparition au N5** : dans `endTurn`/montée de niveau — quand un joueur atteint le N5, chaque planète secondaire existante reçoit son boss (position : case jouable libre la plus éloignée du portail central, hors vue). Une seule fois par planète (flag dérivé : un boss de ce type existe).
- **Verrou N5** : entrer sur la case du boss avant le déverrouillage → dialog « trop puissant » et entrée refusée (le point est consommé) — `MoveResult.bossBlocked`.
- **Combat (CombatKind.boss)** : `startBossCombat(Boss)` ; riposte par attaque de 250 à 500 par pas de 10 (÷2 tank) ; mort du joueur en combat → éliminé, boss reste ; **Fuir** = dégâts conservés, boss reste, pas d'XP ; **victoire** = XP par rang (`defeatedByPlayerIds.length` → 400/300/200/100), boss marqué vaincu (`defeatedByPlayerIds` + id joueur), puis fuite (`isGone: true`) ou **mort définitive** si tous les joueurs actifs l'ont vaincu.
- **Déplacement** (`moveBossesAtTurnEnd` réel) : par fin de tour, chaque boss actif (non fugué, non définitivement mort) bouge à 50 % vers une case jouable libre adjacente de sa planète. **Réapparition** : boss fugué (`isGone`) → replacé en case non découverte libre de sa planète.
- `Player.defeatedBosses` : + BossType à la victoire (affiché écran Personnage, utilisé par la victoire).

## 5. Conditions de victoire (_checkVictoryConditions réel)
- **Chacun pour soi** : dernier survivant (déjà) **ou** un joueur a vaincu les 3 boss des factions adverses à sa faction (boss propre exclu) → gagnant = ce joueur.
- **Équipes** : équipe adverse éliminée (déjà) **ou** l'union des boss vaincus par les membres couvre 3 boss différents → gagnant = l'équipe.
- Status `finished` + champ dérivé gagnant (l'écran le calcule) ; le check provisoire `_applySurvivorCheck` reste pour l'élimination.
- **Écran Game Over (nouveau, CDC)** : `lib/screens/game_over/game_over_screen.dart` + route `/game-over` — titre Victoire !/Partie terminée, gagnant (joueur ou équipe), stats (tours, temps, boss vaincus au total, éliminés), boutons Nouvelle Partie / Accueil. `BoardScreen` : status finished → navigation auto vers `/game-over` (remplace le dialog provisoire) ; le dialog d'élimination en cours de partie reste.

## 6. Écrans/HUD
- HUD plateau : **nom de la planète courante** (chip doré).
- Notifications : « 🌌 {planète} se dévoile ! » (découverte portail), « ⚡ Un boss s'éveille sur {planète} ! » (N5), dialog « Carte Spéciale/boss » existant réutilisé pour le verrou N5.
- Combat : carte Boss (icône par type, PV restants, plage ATK, XP de rang).

## 7. Tests (objectif ≥ 95 au total)
- Génération secondaire : 50 jouables / 6 bloquées / connectée / portail central libre et protégé.
- Portails : spawn en bord uniquement, max 4, destinations uniques, génération de la planète liée, voyage aller-retour (positions exactes), notification.
- Boss : verrou N5, riposte 250-500 par pas de 10 (seedé), mort du joueur, victoire → XP par rang + fuite, réapparition en zone non visible, mort définitive, déplacement 50 % (seedé).
- Victoire : 3 boss factions adverses (joueur Rebel : Krayt+AT-AT+Exogorth), exclusion du boss propre, équipe via union, dernier survivant.
- Sérialisation : `Player.planet`, `GameState.planets` (aller-retour), compat ancienne sauvegarde.
- Widget : écran game over.

## 8. Vérification finale
`flutter analyze` 0 · `flutter test` verts · build Windows · parcours écran (portail → voyage → boss N5 → combat de boss → victoire/élimination → game over).

## Docs
Addendum Sprint 5 dans GDD/CDC (.txt/.docx) : règles portails (voyage miroir, apparition en bord à la découverte), boss (apparition N5, verrou, riposte par pas de 10, XP par rang, fuite/réapparition/mort définitive), victoire (3 boss factions adverses ; équipe = 3 différents via union), 20×20 déjà tracé.

## Hors périmètre
Journal de partie (S6), images (convention livrée), pause chrono/son (S6).