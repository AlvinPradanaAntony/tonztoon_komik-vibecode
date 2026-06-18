/// Fuzzy title-matching used to suggest cross-source bookmark links.
///
/// Returns a confidence score in 0..1 combining token overlap (Jaccard) and
/// character-bigram similarity (Dice). Pure functions with no I/O — kept out of
/// the repository so the algorithm stays testable and reusable.
double titleSimilarity(String left, String right) {
  final a = _normalizeTitle(left);
  final b = _normalizeTitle(right);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.contains(b) || b.contains(a)) return 0.88;

  final aTokens = a.split(' ').toSet();
  final bTokens = b.split(' ').toSet();
  final union = aTokens.union(bTokens).length;
  final tokenScore = union == 0
      ? 0.0
      : aTokens.intersection(bTokens).length / union;
  final aPairs = _characterPairs(a);
  final bPairs = _characterPairs(b);
  final pairUnion = aPairs.length + bPairs.length;
  final pairScore = pairUnion == 0
      ? 0.0
      : (2 * aPairs.intersection(bPairs).length) / pairUnion;
  return (tokenScore * 0.55 + pairScore * 0.45).clamp(0, 1);
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

Set<String> _characterPairs(String value) {
  final compact = value.replaceAll(' ', '');
  if (compact.length < 2) return {compact};
  return {
    for (var index = 0; index < compact.length - 1; index++)
      compact.substring(index, index + 2),
  };
}
