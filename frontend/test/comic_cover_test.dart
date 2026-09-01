import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/widgets/comic_cover.dart';

void main() {
  const proxiedCover =
      'https://api.example.com/api/v1/images/proxy?url=https%3A%2F%2Fexample.com%2Fcover.jpg';

  testWidgets('direct cover URL is not decoded or rewritten by the widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 138,
              height: 207,
              child: ComicCover(imageUrl: 'https://example.com/cover.jpg'),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.imageUrl, 'https://example.com/cover.jpg');
    expect(image.memCacheWidth, isNull);
    expect(image.memCacheHeight, isNull);
  });

  testWidgets('proxied cover requests a small server-side variant', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 98,
              height: 200,
              child: ComicCover(imageUrl: proxiedCover),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final query = Uri.parse(image.imageUrl).queryParameters;
    expect(query['width'], '294');
    expect(query['quality'], '80');
    expect(image.memCacheWidth, isNull);
  });

  testWidgets('detail cover requests a larger server-side variant', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 280,
              height: 420,
              child: ComicCover(
                imageUrl: proxiedCover,
                size: ComicCoverSize.large,
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final query = Uri.parse(image.imageUrl).queryParameters;
    expect(query['width'], '840');
    expect(query['quality'], '88');
  });
}
