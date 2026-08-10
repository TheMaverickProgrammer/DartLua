import 'dart:math' as math;

/// Calculates the number of edits needed to match both strings.
/// Edits include insertions, deletions, substitutions, and transpositions.
/// Extension of Levenshtein Distance.
/// Returns the number of edits for a == b.
int editDistance(String a, String b) {
  final int n = a.length;
  final int m = b.length;

  if (n == 0) return m;
  if (m == 0) return n;

  // The matrix size is (n+2)x(m+2) b/c we need to
  // store an additional entry for:
  // 1. The base case (0,0) plus entries up to (n,m),
  // 2. The traditional algorithm allows for (-1,-1) but this is not normal array indexing.
  // https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance
  final List<List<int>> d = List.generate(n + 2, (i) => List.filled(m + 2, 0));

  final int cap = n + m;
  d[0][0] = cap;

  for (int i = 0; i <= n; i++) {
    d[i + 1][1] = i;
    d[i + 1][0] = cap;
  }

  for (int j = 0; j <= m; j++) {
    d[1][j + 1] = j;
    d[0][j + 1] = cap;
  }

  final Map<int, int> da = {};

  for (int i = 1; i <= n; i++) {
    int db = 0;
    final int ca = a.codeUnitAt(i - 1);

    for (int j = 1; j <= m; j++) {
      final int cb = b.codeUnitAt(j - 1);

      // Previous locations:
      final int pi = da[cb] ?? 0;
      final int pj = db;

      // Substitution cost.
      final int scost = (ca == cb) ? 0 : 1;

      // Store the last known row of this character.
      if (scost == 0) db = j;

      // Cost is always 1.
      d[i + 1][j + 1] = [
        d[i][j] + scost,
        d[i + 1][j] + 1,
        d[i][j + 1] + 1,
        d[pi][pj] + (i - pi - 1) + (j - pj - 1) + 1,
      ].reduce(math.min);
    }
    // Store the last known column location of this character.
    da[ca] = i;
  }

  return d[n + 1][m + 1];
}
