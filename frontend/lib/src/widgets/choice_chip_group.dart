import 'package:flutter/material.dart';

class ChoiceChipGroup extends StatelessWidget {
  const ChoiceChipGroup({
    super.key,
    required this.label,
    required this.values,
    required this.selectedValue,
    required this.onChanged,
    this.selectedValues,
    this.multiSelect = false,
    this.scrollable = true,
    this.labelStyle,
  });

  final String label;
  final List<String> values;
  final String selectedValue;
  final ValueChanged<String> onChanged;
  final Set<String>? selectedValues;
  final bool multiSelect;
  final bool scrollable;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          _FilterChoiceChip(
            value: value,
            selected: multiSelect
                ? value.trim().toLowerCase() == 'semua'
                    ? selectedValues?.isEmpty ?? true
                    : selectedValues?.contains(value) ?? false
                : selectedValue == value,
            multiSelect: multiSelect,
            onSelected: () => onChanged(value),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle ?? Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 7),
        if (scrollable)
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips)
        else
          chips,
      ],
    );
  }
}

class _FilterChoiceChip extends StatelessWidget {
  const _FilterChoiceChip({
    required this.value,
    required this.selected,
    required this.multiSelect,
    required this.onSelected,
  });

  final String value;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final chip = multiSelect
        ? FilterChip(
            label: Text(value),
            selected: selected,
            onSelected: (_) => onSelected(),
            showCheckmark: false,
            selectedColor: colorScheme.primaryContainer,
            backgroundColor: colorScheme.surfaceContainerHighest,
            labelStyle: TextStyle(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: selected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
              ),
            ),
          )
        : ChoiceChip(
            label: Text(value),
            selected: selected,
            onSelected: (_) => onSelected(),
            showCheckmark: false,
            selectedColor: colorScheme.primaryContainer,
            backgroundColor: colorScheme.surfaceContainerHighest,
            labelStyle: TextStyle(
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: selected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
              ),
            ),
          );

    return chip;
  }
}
