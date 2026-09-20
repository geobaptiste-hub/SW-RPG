import io

p = 'lib/screens/board/board_screen.dart'
s = io.open(p, encoding='utf-8').read()

def patch(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

# Dialog carte ennemie : la CARTE de l'allié à gauche du texte
patch(
    """      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(isSpecial
              ? '⚔ Carte Spéciale ennemie !'
              : '⚠ Allié ennemi !'),
          content: Text(
              '${ally.name} (${ally.faction.displayName}) vous attaque : '
              '-$specialDamage PV ! La carte ne rejoint pas votre équipe.'
              '${eliminated ? '\\n\\nVos PV sont tombés à 0 : ${victim.name} est éliminé…' : ''}'),""",
    """      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(isSpecial
              ? '⚔ Carte Spéciale ennemie !'
              : '⚠ Allié ennemi !'),
          content: Row(
            children: <Widget>[
              CardImage(
                category: allyImageCategory(ally.type),
                id: cardImageId(ally.name),
                width: 110,
                height: 170,
                fit: BoxFit.contain,
                fallbackIcon: Icons.warning_amber_rounded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                    '${ally.name} (${ally.faction.displayName}) vous attaque : '
                    '-$specialDamage PV ! La carte ne rejoint pas votre équipe.'
                    '${eliminated ? '\\n\\nVos PV sont tombés à 0 : ${victim.name} est éliminé…' : ''}'),
              ),
            ],
          ),""")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('board_screen OK')

# ---------- combat_screen : photo du joueur et du défenseur JvJ ----------
p = 'lib/screens/combat/combat_screen.dart'
s = io.open(p, encoding='utf-8').read()

def patch2(old, new, count=1):
    global s
    assert old in s, old[:70]
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)

# header photo pour _FighterCard
patch2(
    """  /// Section optionnelle sous les stats (jauge d'XP du joueur — playtest).
  final Widget? footer;""",
    """  /// Section optionnelle sous les stats (jauge d'XP du joueur — playtest).
  final Widget? footer;

  /// Section optionnelle au-dessus des stats : photo du combattant
  /// (Sprint 6 — carte du personnage pendant le combat).
  final Widget? header;""")
patch2(
    """  const _FighterCard({
    required this.title,
    required this.subtitle,
    required this.initials,
    required this.color,
    required this.stats,
    this.footer,
  });""",
    """  const _FighterCard({
    required this.title,
    required this.subtitle,
    required this.initials,
    required this.color,
    required this.stats,
    this.footer,
    this.header,
  });""")
patch2(
    """          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withValues(alpha: 0.3),
              child: Text(initials,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center, style: textTheme.titleMedium),""",
    """          children: [
            if (header != null) header!,
            if (header == null) ...<Widget>[
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withValues(alpha: 0.3),
                child: Text(initials,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              const SizedBox(height: 8),
            ],
            Text(title,
                textAlign: TextAlign.center, style: textTheme.titleMedium),""")

# passer la photo du joueur
patch2(
    """                      footer: _XpGauge(level: active.level, xp: active.xp),
                    )),""",
    """                      footer: _XpGauge(level: active.level, xp: active.xp),
                      header: _FighterPhoto(name: active.name, color: AppColors.playerTokenColor(game.currentPlayerIndex)),
                    )),""")

# passer la photo du défenseur JvJ
patch2(
    """                      CombatKind.player => _FighterCard(
                          title: session.defenderName ?? '',
                          subtitle: 'Défenseur',
                          initials: (session.defenderName ?? '?')
                              .characters
                              .first,
                          color: AppColors.danger,
                          stats: <String, String>{
                            'PV restants': '${session.defenderHpRemaining}',
                          },
                        ),""",
    """                      CombatKind.player => _FighterCard(
                          title: session.defenderName ?? '',
                          subtitle: 'Défenseur',
                          initials: (session.defenderName ?? '?')
                              .characters
                              .first,
                          color: AppColors.danger,
                          stats: <String, String>{
                            'PV restants': '${session.defenderHpRemaining}',
                          },
                          header: _FighterPhoto(
                              name: session.defenderName ?? '',
                              color: AppColors.danger),
                        ),""")

# widget _FighterPhoto (photo sinon avatar initiales)
patch2(
    """/// Jauge de progression vers le niveau suivant (retours playtest v3).""",
    """/// Photo du combattant (carte personnage si l'image est déposée),
/// sinon l'avatar à initiales (Sprint 6).
class _FighterPhoto extends ConsumerWidget {
  final String name;
  final Color color;

  const _FighterPhoto({required this.name, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final File? photo = ref
        .watch(imageServiceProvider)
        .resolveFile('characters', cardImageId(name));
    if (photo == null) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: color.withValues(alpha: 0.3),
        child: Text(name.characters.first,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      );
    }
    return SizedBox(
      width: 96,
      height: 96,
      child: ClipOval(
        child: Image.file(photo,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) =>
                Icon(Icons.person, size: 44, color: color)),
      ),
    );
  }
}

/// Jauge de progression vers le niveau suivant (retours playtest v3).""")

# imports nécessaires (dart:io + image_service + slug)
patch2(
    "import 'package:flutter/material.dart';\nimport 'package:flutter_riverpod/flutter_riverpod.dart';\nimport 'package:go_router/go_router.dart';",
    "import 'dart:io';\n\nimport 'package:flutter/material.dart';\nimport 'package:flutter_riverpod/flutter_riverpod.dart';\nimport 'package:go_router/go_router.dart';")
patch2(
    "import '../../core/utils/slug.dart';\nimport '../../widgets/boss_icon.dart';",
    "import '../../core/utils/slug.dart';\nimport '../../services/image_service.dart';\nimport '../../widgets/boss_icon.dart';")

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('combat_screen OK')
