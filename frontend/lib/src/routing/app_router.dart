import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_navigation.dart';
import '../features/auth/auth_screen.dart';
import '../features/catalog/full_catalog_screen.dart';
import '../features/comic/comic_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/section/comic_section_screen.dart';
import '../features/home/section/continue_reading_section_screen.dart';
import '../features/library/library_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import '../models/auth.dart';
import '../models/comic.dart';
import '../repositories/providers.dart';
import 'library_routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = AppShell.rootNavigatorKey;

  final router = GoRouter(
    initialLocation: '/splash',
    navigatorKey: rootNavigatorKey,
    redirect: (context, state) {
      final normalizedAuthCallback = _normalizedAuthCallbackLocation(state.uri);
      if (normalizedAuthCallback != null) return normalizedAuthCallback;

      final auth = ref.read(authControllerProvider);
      final path = state.uri.path;
      if (auth.status == AuthStatus.booting &&
          path != '/splash' &&
          !_isAuthCallbackRoute(path)) {
        deferNotificationLocation(state.uri.toString());
        return '/splash';
      }

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
                  final tabIndex = libraryTabIndexFromName(
                    state.uri.queryParameters['tab'],
                  );
                  return LibraryScreen(initialTabIndex: tabIndex);
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
        pageBuilder: (context, state) =>
            _instantPage(state, const AuthScreen()),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        pageBuilder: (context, state) => _instantPage(
          state,
          ForgotPasswordScreen(
            initialEmail: state.uri.queryParameters['email'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (context, state) =>
            _instantPage(state, _buildAuthCallbackScreen(state.uri)),
      ),
      GoRoute(
        path: '/callback',
        pageBuilder: (context, state) =>
            _instantPage(state, _buildAuthCallbackScreen(state.uri)),
      ),
      GoRoute(
        path: '/auth/reset-password',
        pageBuilder: (context, state) =>
            _instantPage(state, _buildResetPasswordScreen(state.uri)),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) =>
            _instantPage(state, _buildResetPasswordScreen(state.uri)),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/library/continue-reading',
        builder: (context, state) {
          final payload = state.extra is ContinueReadingSectionPayload
              ? state.extra! as ContinueReadingSectionPayload
              : null;
          return ContinueReadingSectionScreen(
            initialItems: payload?.items ?? const [],
          );
        },
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
              sourceName: payload.sourceName,
              comics: payload.comics,
              initialSort: payload.initialSort,
            );
          }
          final section = state.pathParameters['section'] ?? 'Katalog';
          final source = state.pathParameters['source'];
          return ComicSectionScreen(
            title: section == 'popular' ? 'Populer' : 'Rilis Terbaru',
            subtitle: section == 'popular'
                ? 'Komik yang ramai dibaca minggu ini.'
                : 'Chapter baru dari berbagai sumber favorit.',
            sourceName: source == 'home' ? null : source,
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
  ref.onDispose(router.dispose);
  return router;
});

bool _isAuthCallbackRoute(String path) {
  return path == '/auth/callback' ||
      path == '/callback' ||
      path == '/auth/reset-password' ||
      path == '/reset-password';
}

String? _normalizedAuthCallbackLocation(Uri uri) {
  final path = switch (uri.path) {
    '/auth/callback/' => '/auth/callback',
    '/callback/' => '/callback',
    _ => null,
  };
  if (path == null) return null;

  return Uri(
    path: path,
    queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    fragment: uri.fragment.isEmpty ? null : uri.fragment,
  ).toString();
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
    callbackType: params['type'],
    email: params['email'],
    callbackError: params['error_description'] ?? params['error'],
    tokenHash: params['token_hash'],
    accessToken: params['access_token'],
    refreshToken: params['refresh_token'],
    expiresAt: int.tryParse(params['expires_at'] ?? ''),
  );
}

Page<void> _instantPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}
