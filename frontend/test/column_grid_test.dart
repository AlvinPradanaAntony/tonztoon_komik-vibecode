import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/widgets/column_grid.dart';

void main() {
  group('AppSliverColumnGrid dynamic loading shimmer', () {
    testWidgets('fills remaining row slots and adds subsequent shimmer row without dead space', (
      tester,
    ) async {
      final items = ['Item 1', 'Item 2', 'Item 3', 'Item 4', 'Item 5'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                AppSliverColumnGrid<String>(
                  items: items,
                  columnCount: 3,
                  isLoadingMore: true,
                  loadingRowCount: 1,
                  loadingBuilder: (context, loadingIndex) {
                    return Container(
                      key: ValueKey('shimmer-$loadingIndex'),
                      height: 100,
                      color: Colors.grey,
                      child: Text('Shimmer $loadingIndex'),
                    );
                  },
                  itemBuilder: (context, item) {
                    return SizedBox(
                      key: ValueKey(item),
                      height: 100,
                      child: Text(item),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All 5 real items are present
      for (final item in items) {
        expect(find.byKey(ValueKey(item)), findsOneWidget);
      }

      // Shimmer index 0 fills the 3rd slot of the 2nd row (remainder 5 % 3 = 2, so 1 slot needed)
      expect(find.byKey(const ValueKey('shimmer-0')), findsOneWidget);
      // Shimmer index 1, 2, 3 fill the 3rd row (1 full row of 3 columns)
      expect(find.byKey(const ValueKey('shimmer-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('shimmer-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('shimmer-3')), findsOneWidget);

      // Verify layout positions:
      // Item 4 and Item 5 are in Row 1. Shimmer 0 should have the same Y position as Item 4 and Item 5!
      final item4Pos = tester.getTopLeft(find.byKey(const ValueKey('Item 4')));
      final item5Pos = tester.getTopLeft(find.byKey(const ValueKey('Item 5')));
      final shimmer0Pos = tester.getTopLeft(find.byKey(const ValueKey('shimmer-0')));

      expect(item4Pos.dy, equals(item5Pos.dy));
      expect(shimmer0Pos.dy, equals(item4Pos.dy)); // Same row! No dead space!
      expect(shimmer0Pos.dx, greaterThan(item5Pos.dx)); // Right of Item 5

      // Shimmer 1 should be on the next row below Item 4
      final shimmer1Pos = tester.getTopLeft(find.byKey(const ValueKey('shimmer-1')));
      expect(shimmer1Pos.dy, greaterThan(item4Pos.dy));
    });

    testWidgets('does not render shimmer items when isLoadingMore is false', (
      tester,
    ) async {
      final items = ['Item 1', 'Item 2', 'Item 3', 'Item 4', 'Item 5'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                AppSliverColumnGrid<String>(
                  items: items,
                  columnCount: 3,
                  isLoadingMore: false,
                  loadingBuilder: (context, loadingIndex) {
                    return Text('Shimmer $loadingIndex');
                  },
                  itemBuilder: (context, item) {
                    return Text(item);
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final item in items) {
        expect(find.text(item), findsOneWidget);
      }
      expect(find.textContaining('Shimmer'), findsNothing);
    });
  });

  group('AppColumnGrid dynamic loading shimmer', () {
    testWidgets('fills remaining row slots and subsequent shimmer row in non-sliver grid', (
      tester,
    ) async {
      final items = ['A', 'B', 'C', 'D'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppColumnGrid<String>(
                items: items,
                columnCount: 3,
                isLoadingMore: true,
                loadingRowCount: 1,
                loadingBuilder: (context, loadingIndex) {
                  return SizedBox(
                    key: ValueKey('box-shimmer-$loadingIndex'),
                    height: 80,
                    child: Text('Shimmer $loadingIndex'),
                  );
                },
                itemBuilder: (context, item) {
                  return SizedBox(
                    key: ValueKey('item-$item'),
                    height: 80,
                    child: Text(item),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 4 items with 3 columns:
      // Row 0: A, B, C (3 items)
      // Row 1: D, Shimmer 0, Shimmer 1 (2 slots needed to fill row!)
      // Row 2: Shimmer 2, Shimmer 3, Shimmer 4 (3 slots for additional row)
      expect(find.byKey(const ValueKey('box-shimmer-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('box-shimmer-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('box-shimmer-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('box-shimmer-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('box-shimmer-4')), findsOneWidget);

      final dPos = tester.getTopLeft(find.byKey(const ValueKey('item-D')));
      final shimmer0Pos = tester.getTopLeft(find.byKey(const ValueKey('box-shimmer-0')));
      final shimmer1Pos = tester.getTopLeft(find.byKey(const ValueKey('box-shimmer-1')));

      expect(shimmer0Pos.dy, equals(dPos.dy)); // In the same row as D!
      expect(shimmer1Pos.dy, equals(dPos.dy)); // In the same row as D!
    });
  });
}
