import 'package:flutter/widgets.dart';
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
                builder: (context, state) {
                  final tabIndex = _libraryTabIndex(
                    state.uri.queryParameters['tab'],
                  );
                  return LibraryScreen(
                    key: ValueKey('library-tab-$tabIndex'),
                    initialTabIndex: tabIndex,
                  );
                },
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
      GoRoute(
        path: '/auth',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _instantPage(state, const AuthScreen()),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _instantPage(
          state,
          ForgotPasswordScreen(
            initialEmail: state.uri.queryParameters['email'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/auth/callback',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _instantPage(state, _buildAuthCallbackScreen(state.uri)),
      ),
      GoRoute(
        path: '/auth/reset-password',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _instantPage(state, _buildResetPasswordScreen(state.uri)),
      ),
      GoRoute(
        path: '/reset-password',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _instantPage(state, _buildResetPasswordScreen(state.uri)),
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

int _libraryTabIndex(String? tab) {
  return switch (tab) {
    'collections' || 'koleksi' => 1,
    'scenes' || 'scene' => 2,
    'history' || 'riwayat' => 3,
    'downloads' || 'unduhan' => 4,
    _ => 0,
  };
}

Map<String, String> _authCallbackParams(Uri uri) {
  final params = <String, String>{...uri.queryParameters};
  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) return params;

  if (fragment.startsWith('/')) {
    final fragmentUri = Uri.tryParse(fragment);
    if (fragmentUri != null) {
      params.addAll(fragmentUri.queryParameters);
    }
    return params;
  }

  final queryStart = fragment.indexOf('?');
  final fragmentQuery = queryStart >= 0
      ? fragment.substring(queryStart + 1)
      : fragment;
  params.addAll(Uri.splitQueryString(fragmentQuery));
  return params;
}

ResetPasswordScreen _buildResetPasswordScreen(Uri uri) {
  final params = _authCallbackParams(uri);
  return ResetPasswordScreen(
    initialEmail: params['email'] ?? '',
    tokenHash: params['token_hash'],
    accessToken: params['access_token'],
    refreshToken: params['refresh_token'],
    expiresAt: int.tryParse(params['expires_at'] ?? ''),
  );
}

Widget _buildAuthCallbackScreen(Uri uri) {
  final params = _authCallbackParams(uri);
  if (params['type'] == 'recovery') {
    return _buildResetPasswordScreen(uri);
  }

  return AuthCallbackScreen(
    accessToken: params['access_token'],
    refreshToken: params['refresh_token'],
    expiresAt: int.tryParse(params['expires_at'] ?? ''),
  );
}

Page<void> _instantPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}
