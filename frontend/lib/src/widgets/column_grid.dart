import 'package:flutter/material.dart';

typedef ColumnGridItemBuilder<T> =
    Widget Function(BuildContext context, T item);

class AppColumnGrid<T> extends StatelessWidget {
  const AppColumnGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.columnCount,
    this.minColumnWidth = 104,
    this.maxColumnCount = 6,
    this.horizontalSpacing = 12,
    this.verticalSpacing = 10,
  });

  final List<T> items;
  final ColumnGridItemBuilder<T> itemBuilder;
  final int? columnCount;
  final double minColumnWidth;
  final int maxColumnCount;
  final double horizontalSpacing;
  final double verticalSpacing;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeColumnCount = _resolveColumnCount(constraints.maxWidth);
        final rowCount = (items.length / safeColumnCount).ceil();

        return Column(
          children: [
            for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) ...[
              _ColumnGridRow<T>(
                items: _rowItems(rowIndex, safeColumnCount),
                columnCount: safeColumnCount,
                itemBuilder: itemBuilder,
                horizontalSpacing: horizontalSpacing,
              ),
              if (rowIndex != rowCount - 1) SizedBox(height: verticalSpacing),
            ],
          ],
        );
      },
    );
  }

  List<T> _rowItems(int rowIndex, int safeColumnCount) {
    final start = rowIndex * safeColumnCount;
    final end = (start + safeColumnCount).clamp(0, items.length);
    return items.sublist(start, end);
  }

  int _resolveColumnCount(double maxWidth) {
    final fixedColumnCount = columnCount;
    if (fixedColumnCount != null) {
      return fixedColumnCount.clamp(1, maxColumnCount);
    }
    if (!maxWidth.isFinite || maxWidth <= 0) return 1;

    final widthWithTrailingGap = maxWidth + horizontalSpacing;
    final columnWidthWithGap = minColumnWidth + horizontalSpacing;
    return (widthWithTrailingGap / columnWidthWithGap).floor().clamp(
      1,
      maxColumnCount,
    );
  }
}

class AppSliverColumnGrid<T> extends StatelessWidget {
  const AppSliverColumnGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.columnCount,
    this.minColumnWidth = 104,
    this.maxColumnCount = 6,
    this.horizontalSpacing = 12,
    this.verticalSpacing = 10,
  });

  final List<T> items;
  final ColumnGridItemBuilder<T> itemBuilder;
  final int? columnCount;
  final double minColumnWidth;
  final int maxColumnCount;
  final double horizontalSpacing;
  final double verticalSpacing;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final safeColumnCount = _resolveColumnCount(
          constraints.crossAxisExtent,
        );
        final rowCount = (items.length / safeColumnCount).ceil();
        final childCount = rowCount * 2 - 1;

        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index.isOdd) return SizedBox(height: verticalSpacing);

            final rowIndex = index ~/ 2;
            return _ColumnGridRow<T>(
              items: _rowItems(rowIndex, safeColumnCount),
              columnCount: safeColumnCount,
              itemBuilder: itemBuilder,
              horizontalSpacing: horizontalSpacing,
            );
          }, childCount: childCount),
        );
      },
    );
  }

  List<T> _rowItems(int rowIndex, int safeColumnCount) {
    final start = rowIndex * safeColumnCount;
    final end = (start + safeColumnCount).clamp(0, items.length);
    return items.sublist(start, end);
  }

  int _resolveColumnCount(double maxWidth) {
    final fixedColumnCount = columnCount;
    if (fixedColumnCount != null) {
      return fixedColumnCount.clamp(1, maxColumnCount);
    }
    if (!maxWidth.isFinite || maxWidth <= 0) return 1;

    final widthWithTrailingGap = maxWidth + horizontalSpacing;
    final columnWidthWithGap = minColumnWidth + horizontalSpacing;
    return (widthWithTrailingGap / columnWidthWithGap).floor().clamp(
      1,
      maxColumnCount,
    );
  }
}

class _ColumnGridRow<T> extends StatelessWidget {
  const _ColumnGridRow({
    required this.itemBuilder,
    required this.items,
    required this.columnCount,
    required this.horizontalSpacing,
  });

  final List<T> items;
  final int columnCount;
  final ColumnGridItemBuilder<T> itemBuilder;
  final double horizontalSpacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) ...[
          if (columnIndex > 0) SizedBox(width: horizontalSpacing),
          Expanded(
            child: columnIndex < items.length
                ? itemBuilder(context, items[columnIndex])
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}
