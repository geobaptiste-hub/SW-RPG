import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Ordre de navigation des sous-écrans du plateau (flèches ‹ › / swipe).
const List<String> kSubScreenRoutes = <String>[
  '/character',
  '/team',
  '/inventory',
  '/players',
  '/journal',
];

/// Scaffold des sous-écrans du plateau (retours playtest — pensé
/// tablette) : AppBar avec retour au plateau et flèches ‹ › pour passer
/// d'un écran à l'autre, et swipe horizontal sur le contenu.
class SubScreenShell extends StatelessWidget {
  final String route;
  final String title;
  final Widget body;

  const SubScreenShell({
    super.key,
    required this.route,
    required this.title,
    required this.body,
  });

  void _go(BuildContext context, int delta) {
    final int index = kSubScreenRoutes.indexOf(route);
    final int next = index + delta;
    if (next < 0 || next >= kSubScreenRoutes.length) return;
    context.go(kSubScreenRoutes[next]);
  }

  @override
  Widget build(BuildContext context) {
    final int index = kSubScreenRoutes.indexOf(route);
    final bool hasPrev = index > 0;
    final bool hasNext = index < kSubScreenRoutes.length - 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour au plateau',
          onPressed: () => context.go('/board'),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Écran précédent',
              onPressed: hasPrev ? () => _go(context, -1) : null,
            ),
            Text(title),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Écran suivant',
              onPressed: hasNext ? () => _go(context, 1) : null,
            ),
          ],
        ),
      ),
      // Swipe horizontal : glisser à gauche = écran suivant, à droite =
      // écran précédent. Les scrollables internes (ex. l'écran Équipe)
      // gardent la priorité sur leur zone.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (DragEndDetails details) {
          final double velocity = details.primaryVelocity ?? 0;
          if (velocity < -160) {
            _go(context, 1);
          } else if (velocity > 160) {
            _go(context, -1);
          }
        },
        child: body,
      ),
    );
  }
}
