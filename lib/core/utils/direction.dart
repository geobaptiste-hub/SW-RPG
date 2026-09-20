/// Directions de déplacement sur la grille.
///
/// TODO(Design) : le GDD/CDC parlent de « cases voisines » sans préciser
/// si le déplacement est orthogonal (4 directions) ou diagonal inclus
/// (8 directions). Choix actuel : 4 directions orthogonales, standard des
/// jeux de plateau sur grille. À confirmer avec le game design.
enum Direction {
  up(0, -1),
  right(1, 0),
  down(0, 1),
  left(-1, 0);

  final int dx;
  final int dy;

  const Direction(this.dx, this.dy);

  /// Les 4 directions orthogonales, dans un ordre stable.
  static const List<Direction> orthogonal = [up, right, down, left];
}
