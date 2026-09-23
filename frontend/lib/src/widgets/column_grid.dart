import 'package:flutter/material.dart';

typedef ColumnGridItemBuilder<T> =
    Widget Function(BuildContext context, T item);

typedef ColumnGridLoadingBuilder =
    Widget Function(BuildContext context, int loadingIndex);

int resolveColumnGridColumnCount({
  required double maxWidth,
  int? columnCount,
  required double minColumnWidth,
  required int maxColumnCount,
  required double horizontalSpacing,
}) {
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
    this.isLoadingMore = false,
    this.loadingBuilder,
    this.loadingRowCount = 1,
  });

  final List<T> items;
  final ColumnGridItemBuilder<T> itemBuilder;
  final int? columnCount;
  final double minColumnWidth;
  final int maxColumnCount;
  final double horizontalSpacing;
  final double verticalSpacing;
  final bool isLoadingMore;
  final ColumnGridLoadingBuilder? loadingBuilder;
  final int loadingRowCount;

  @override
  Widget build(BuildContext context) {
    final showLoading = isLoadingMore && loadingBuilder != null;
    if (items.isEmpty && !showLoading) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeColumnCount = _resolveColumnCount(constraints.maxWidth);

        final int totalLoadingItems;
        if (showLoading) {
          final remainder = items.length % safeColumnCount;
          final slotsToFillRow =
              remainder == 0 ? 0 : safeColumnCount - remainder;
          totalLoadingItems =
              slotsToFillRow + (loadingRowCount * safeColumnCount);
        } else {
          totalLoadingItems = 0;
        }

        final totalItemCount = items.length + totalLoadingItems;
        if (totalItemCount == 0) return const SizedBox.shrink();

        final rowCount = (totalItemCount / safeColumnCount).ceil();

        return Column(
          children: [
            for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) ...[
              _ColumnGridRow<T>(
                rowIndex: rowIndex,
                items: items,
                columnCount: safeColumnCount,
                itemBuilder: itemBuilder,
                horizontalSpacing: horizontalSpacing,
                showLoading: showLoading,
                totalLoadingItems: totalLoadingItems,
                loadingBuilder: loadingBuilder,
              ),
              if (rowIndex != rowCount - 1) SizedBox(height: verticalSpacing),
            ],
          ],
        );
      },
    );
  }

  int _resolveColumnCount(double maxWidth) {
    return resolveColumnGridColumnCount(
      maxWidth: maxWidth,
      columnCount: columnCount,
      minColumnWidth: minColumnWidth,
      maxColumnCount: maxColumnCount,
      horizontalSpacing: horizontalSpacing,
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
    this.isLoadingMore = false,
    this.loadingBuilder,
    this.loadingRowCount = 1,
  });

  final List<T> items;
  final ColumnGridItemBuilder<T> itemBuilder;
  final int? columnCount;
  final double minColumnWidth;
  final int maxColumnCount;
  final double horizontalSpacing;
  final double verticalSpacing;
  final bool isLoadingMore;
  final ColumnGridLoadingBuilder? loadingBuilder;
  final int loadingRowCount;

  @override
  Widget build(BuildContext context) {
    final showLoading = isLoadingMore && loadingBuilder != null;
    if (items.isEmpty && !showLoading) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final safeColumnCount = _resolveColumnCount(
          constraints.crossAxisExtent,
        );

        final int totalLoadingItems;
        if (showLoading) {
          final remainder = items.length % safeColumnCount;
          final slotsToFillRow =
              remainder == 0 ? 0 : safeColumnCount - remainder;
          totalLoadingItems =
              slotsToFillRow + (loadingRowCount * safeColumnCount);
        } else {
          totalLoadingItems = 0;
        }

        final totalItemCount = items.length + totalLoadingItems;
        if (totalItemCount == 0) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final rowCount = (totalItemCount / safeColumnCount).ceil();
        final childCount = rowCount * 2 - 1;

        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index.isOdd) return SizedBox(height: verticalSpacing);

            final rowIndex = index ~/ 2;
            return _ColumnGridRow<T>(
              rowIndex: rowIndex,
              items: items,
              columnCount: safeColumnCount,
              itemBuilder: itemBuilder,
              horizontalSpacing: horizontalSpacing,
              showLoading: showLoading,
              totalLoadingItems: totalLoadingItems,
              loadingBuilder: loadingBuilder,
            );
          }, childCount: childCount),
        );
      },
    );
  }

  int _resolveColumnCount(double maxWidth) {
    return resolveColumnGridColumnCount(
      maxWidth: maxWidth,
      columnCount: columnCount,
      minColumnWidth: minColumnWidth,
      maxColumnCount: maxColumnCount,
      horizontalSpacing: horizontalSpacing,
    );
  }
}

class _ColumnGridRow<T> extends StatelessWidget {
  const _ColumnGridRow({
    required this.rowIndex,
    required this.items,
    required this.columnCount,
    required this.horizontalSpacing,
    required this.itemBuilder,
    required this.showLoading,
    required this.totalLoadingItems,
    required this.loadingBuilder,
  });

  final int rowIndex;
  final List<T> items;
  final int columnCount;
  final double horizontalSpacing;
  final ColumnGridItemBuilder<T> itemBuilder;
  final bool showLoading;
  final int totalLoadingItems;
  final ColumnGridLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) ...[
          if (columnIndex > 0) SizedBox(width: horizontalSpacing),
          Expanded(
            child: _buildCell(context, columnIndex),
          ),
        ],
      ],
    );
  }

  Widget _buildCell(BuildContext context, int columnIndex) {
    final globalIndex = rowIndex * columnCount + columnIndex;
    if (globalIndex < items.length) {
      return itemBuilder(context, items[globalIndex]);
    }
    if (showLoading &&
        loadingBuilder != null &&
        globalIndex < items.length + totalLoadingItems) {
      return loadingBuilder!(context, globalIndex - items.length);
    }
    return const SizedBox.shrink();
  }
}
