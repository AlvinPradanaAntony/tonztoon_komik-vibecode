part of '../notifications_screen.dart';

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 2.6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          children: [
            Icon(TonztoonIcons.bell, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              filter == 'Semua'
                  ? 'Belum ada notifikasi'
                  : 'Belum ada notifikasi $filter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Aktivitas nyata seperti status download akan muncul di sini.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsLoading extends StatelessWidget {
  const _NotificationsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
      children: const [
        _LoadingCard(height: 96),
        SizedBox(height: 18),
        Row(
          children: [
            _LoadingCard(width: 78, height: 34),
            SizedBox(width: 8),
            _LoadingCard(width: 78, height: 34),
            SizedBox(width: 8),
            _LoadingCard(width: 92, height: 34),
          ],
        ),
        SizedBox(height: 20),
        _LoadingCard(width: 170, height: 24),
        SizedBox(height: 10),
        _LoadingCard(height: 92),
        SizedBox(height: 12),
        _LoadingCard(height: 92),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({this.width = double.infinity, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class _NotificationsError extends StatelessWidget {
  const _NotificationsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppErrorState(
          message: message,
          onRetry: onRetry,
          icon: TonztoonIcons.warning,
          iconSize: 34,
        ),
      ),
    );
  }
}
