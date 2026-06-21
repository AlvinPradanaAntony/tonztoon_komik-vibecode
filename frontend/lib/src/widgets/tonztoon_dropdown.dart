import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';

class TonztoonDropdownItem<T> {
  const TonztoonDropdownItem({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class TonztoonDropdownButton<T> extends StatelessWidget {
  const TonztoonDropdownButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText = 'Pilih opsi',
    this.icon = TonztoonIcons.travelExplore,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.iconSize = 18,
    this.maxLabelWidth,
    this.isError = false,
    this.mainAxisSize = MainAxisSize.max,
  });

  final T? value;
  final List<TonztoonDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String hintText;
  final IconData icon;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final double? maxLabelWidth;
  final bool isError;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final displayLabel = value == null
        ? hintText
        : items
            .firstWhere(
              (item) => item.value == value,
              orElse: () => TonztoonDropdownItem(
                value: value as T,
                label: hintText,
              ),
            )
            .label;

    return PopupMenuButton<T>(
      enabled: enabled,
      initialValue: value,
      tooltip: hintText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      position: PopupMenuPosition.under,
      onSelected: (newValue) {
        if (enabled && onChanged != null) {
          onChanged!(newValue);
        }
      },
      itemBuilder: (context) => items.map((item) {
        return PopupMenuItem<T>(
          value: item.value,
          child: Row(
            children: [
              Icon(
                value == item.value ? TonztoonIcons.check : null,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: value == item.value
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.82),
          border: Border.all(
            color: isError
                ? colorScheme.error
                : colorScheme.primary.withValues(alpha: 0.25),
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(
                alpha: isDark ? 0.12 : 0.08,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: mainAxisSize,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: isError ? colorScheme.error : colorScheme.primary,
              ),
              const SizedBox(width: 6),
              if (maxLabelWidth != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth!),
                  child: Text(
                    displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: isError ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: value == null
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(width: 3),
              Icon(
                TonztoonIcons.keyboardArrowDown,
                size: iconSize - 1,
                color: isError ? colorScheme.error : colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TonztoonDropdown<T> extends StatelessWidget {
  const TonztoonDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelText,
    this.hintText = 'Pilih opsi',
    this.icon = TonztoonIcons.travelExplore,
    this.validator,
    this.enabled = true,
  });

  final T? value;
  final List<TonztoonDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String labelText;
  final String hintText;
  final IconData icon;
  final FormFieldValidator<T>? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (FormFieldState<T> state) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final hasError = state.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labelText,
              style: theme.textTheme.labelLarge?.copyWith(
                color: hasError
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TonztoonDropdownButton<T>(
              value: state.value,
              items: items,
              onChanged: (newValue) {
                state.didChange(newValue);
                if (enabled && onChanged != null) {
                  onChanged!(newValue);
                }
              },
              hintText: hintText,
              icon: icon,
              enabled: enabled,
              isError: hasError,
            ),
            if (hasError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  state.errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
