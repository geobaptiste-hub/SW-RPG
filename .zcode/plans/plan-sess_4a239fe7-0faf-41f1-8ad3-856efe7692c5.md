## Fins lumineuse/sombre (image + musique) — plan final

### 1. Détermination du côté gagnant
- Lumineux = factions Rebel/Jedi ; Sombre = Empire/Sith.
- `resolveWinner` (game_over_screen) : le record `WinnerResolution` gagne un champ `lightSide` (bool) + un `Faction? winnerFaction` / liste des factions gagnantes quand pertinent :
  - chacun pour soi : faction du joueur vainqueur (objectifs ou dernier survivant) ;
  - équipes : faction majoritaire des membres vivants de l'équipe gagnante ; égalité parfaite → lumineux.
- Le champ alimente : image de fond + musique de fin.

### 2. Game Over : image + musique selon le côté
- Fonds attendus (dépôt sans recompilation) : `assets/images/screens/game_over/fin_lumineuse.png|jpg` et `fin_sombre.png|jpg` (1920×1080, cover).
- Musiques attendues : `assets/audio/music/fin_lumineuse/fin_lumineuse.mp3` et `fin_sombre/fin_sombre.mp3` (boucle).
- `game_over_screen.dart` : `AppBackground(imageId: 'screens/game_over/fin_lumineuse'|'fin_sombre', ...)` selon le côté + `ScreenMusic(track: ...)` équivalent. Repli : accueil.png si l'image du côté manque.
- L'entête affiche en plus « ✨ Côté Lumineux » / « ☾ Côté Obscur » (couleur or ou gris-bleu).

### 3. Dossiers de dépôt + LISEZ-MOI
- `assets/images/screens/game_over/` (LISEZ-MOI : les 2 noms, 1920×1080, cover)
- `assets/audio/music/fin_lumineuse/` et `fin_sombre/` (LISEZ-MOI : fin_lumineuse.mp3 / fin_sombre.mp3)

### 4. Validation
- Tests : côté gagnant (victoire objectives Rebel → lumineux ; Empire → sombre) via resolveWinner.
- `flutter analyze` → tests full green → build → smoke → maj passation (§ fins lumineuse/sombre + emplacements de dépôt).