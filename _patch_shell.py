import io
import re

screens = [
    ('lib/screens/character/character_screen.dart', '/character', 'Personnage',
     """      appBar: AppBar(
        title: const Text('Personnage'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/board'),
        ),
      ),
""", "ListView("),
    ('lib/screens/team/team_screen.dart', '/team', 'Équipe',
     """      appBar: AppBar(
        title: const Text('Équipe'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/board'),
        ),
      ),
""", None),
    ('lib/screens/inventory/inventory_screen.dart', '/inventory', 'Inventaire',
     """      appBar: AppBar(
        title: const Text('Inventaire'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/board'),
        ),
      ),
""", None),
    ('lib/screens/players/players_screen.dart', '/players', 'Joueurs',
     """      appBar: AppBar(
        title: const Text('Joueurs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/board'),
        ),
      ),
""", None),
    ('lib/screens/journal/journal_screen.dart', '/journal', 'Journal de partie',
     """      appBar: AppBar(
        title: const Text('Journal de partie'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/board'),
        ),
      ),
""", None),
]

for path, route, title, appbar, _ in screens:
    s = io.open(path, encoding='utf-8').read()
    assert appbar in s, (path, 'appbar')
    s = s.replace(appbar, '')
    # Remplacer le Scaffold ouvert par SubScreenShell
    old_open = "    return Scaffold(\n      body:"
    assert old_open in s, (path, 'scaffold')
    s = s.replace(old_open, f"    return SubScreenShell(\n      route: '{route}',\n      title: '{title}',\n      body:")
    # Import du shell
    marker = "import '../../services/game_service.dart';"
    assert marker in s, (path, 'import')
    s = s.replace(marker, marker + "\nimport '../../widgets/sub_screen_shell.dart';")
    io.open(path, 'w', encoding='utf-8', newline='').write(s)
    print('OK', path)
