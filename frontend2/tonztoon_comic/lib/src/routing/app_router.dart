import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/catalog/full_catalog_screen.dart';
import '../features/comic/comic_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/section/comic_section_screen.dart';
import '../features/library/library_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import '../models/comic.dart';
import '../repositories/providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = AppShell.rootNavigatorKey;

  return GoRouter(
    initialLocation: '/splash',
    navigatorKey: rootNavigatorKey,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.uri.path;
      final isAuthRoute = path == '/auth' || path == '/auth/forgot-password';
      if (auth.isAuthenticated && isAuthRoute) return '/settings';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/catalog',
                builder: (context, state) =>
                    const FullCatalogScreen(showBackButton: false),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => Consumer(
                  builder: (context, ref, child) {
                    final auth = ref.watch(authControllerProvider);
                    return SettingsScreen(
                      isSignedIn: auth.isAuthenticated,
                      onOpenAuth: () => context.push('/auth'),
                      onLogout: () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .logout();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (context, state) => ForgotPasswordScreen(
          initialEmail: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/comic/:source/:slug',
        builder: (context, state) => ComicDetailScreen(
          sourceName: state.pathParameters['source']!,
          slug: state.pathParameters['slug']!,
          initialComic: state.extra is ComicSummary
              ? state.extra! as ComicSummary
              : null,
        ),
      ),
      GoRoute(
        path: '/comic/:source/:slug/section/:section',
        builder: (context, state) {
          final payload = state.extra is ComicSectionPayload
              ? state.extra! as ComicSectionPayload
              : null;
          if (payload != null) {
            return ComicSectionScreen(
              title: payload.title,
              subtitle: payload.subtitle,
              comics: payload.comics,
              initialSort: payload.initialSort,
            );
          }
          final section = state.pathParameters['section'] ?? 'Katalog';
          return ComicSectionScreen(
            title: section == 'popular' ? 'Populer' : 'Rilis Terbaru',
            subtitle: section == 'popular'
                ? 'Komik yang ramai dibaca minggu ini.'
                : 'Chapter baru dari berbagai sumber favorit.',
            comics: const [],
            initialSort: section == 'popular'
                ? 'Paling populer'
                : 'Update terbaru',
          );
        },
      ),
      GoRoute(
        path: '/reader/:source/:slug/:chapter',
        builder: (context, state) => ReaderScreen(
          sourceName: state.pathParameters['source']!,
          slug: state.pathParameters['slug']!,
          chapterNumber: double.parse(state.pathParameters['chapter']!),
          initialComic: state.extra is ComicSummary
              ? state.extra! as ComicSummary
              : null,
        ),
      ),
    ],
  );
});
