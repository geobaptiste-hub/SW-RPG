import io

screens = [
    ('lib/screens/inventory/inventory_screen.dart', '/inventory', 'Inventaire', 'Inventaire'),
    ('lib/screens/players/players_screen.dart', '/players', 'Joueurs', 'Joueurs'),
    ('lib/screens/journal/journal_screen.dart', '/journal', 'Journal de partie', 'Journal de partie'),
]

for path, route, title, appbar_text in screens:
    s = io.open(path, encoding='utf-8').read()
    # Retirer le bloc AppBar complet
    start = s.index("      appBar: AppBar(")
    end = s.index("      ),", start) + len("      ),\n")
    s = s[:start] + s[end:]
    # Scaffold -> SubScreenShell
    old_open = "    return Scaffold(\n      body:"
    assert old_open in s, (path, 'scaffold')
    s = s.replace(old_open, f"    return SubScreenShell(\n      route: '{route}',\n      title: '{title}',\n      body:")
    marker = "import '../../services/game_service.dart';"
    assert marker in s, (path, 'import')
    s = s.replace(marker, marker + "\nimport '../../widgets/sub_screen_shell.dart';")
    io.open(path, 'w', encoding='utf-8', newline='').write(s)
    print('OK', path)
