import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/comic/comic_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/shell/main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            MainShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: '/search',
            builder: (context, state) => const PlaceholderScreen(
              title: 'Search',
              message:
                  'Search will use the backend multi-source endpoint next.',
            ),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) => const PlaceholderScreen(
              title: 'Library',
              message:
                  'Bookmarks, collections, favorite scenes, history, and downloads are scaffolded for the next slice.',
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const PlaceholderScreen(
              title: 'Settings',
              message: 'Reader preferences and cache controls will live here.',
            ),
          ),
        ],
      ),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/comic/:source/:slug',
        builder: (context, state) => ComicDetailScreen(
          sourceName: state.pathParameters['source']!,
          slug: state.pathParameters['slug']!,
        ),
      ),
      GoRoute(
        path: '/reader/:source/:slug/:chapter',
        builder: (context, state) => ReaderScreen(
          sourceName: state.pathParameters['source']!,
          slug: state.pathParameters['slug']!,
          chapterNumber: double.parse(state.pathParameters['chapter']!),
        ),
      ),
    ],
  );
});
