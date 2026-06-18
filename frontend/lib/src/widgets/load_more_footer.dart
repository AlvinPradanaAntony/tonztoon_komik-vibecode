import 'package:flutter/material.dart';

/// Footer for paginated lists that renders the "all items loaded" message once
/// there is no next page. Returns an empty spacer while more pages remain (or
/// the list is empty), so call sites can always place it at the end of a list.
///
/// Intentionally text-only: the in-flight loading indicator differs per screen
/// (rich shimmer in home sections, a spinner in the catalog) and is rendered as
/// a separate sliver/widget above this footer.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.hasNextPage,
    required this.loadedCount,
    this.completeLabel = 'Semua item sudah dimuat',
  });

  final bool hasNextPage;
  final int loadedCount;
  final String completeLabel;

  @override
  Widget build(BuildContext context) {
    if (hasNextPage || loadedCount == 0) {
      return const SizedBox(height: 20);
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        completeLabel,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
