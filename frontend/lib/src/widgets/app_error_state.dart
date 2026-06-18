import 'package:flutter/material.dart';

import '../utils/app_error.dart';

/// Reusable error-state block: an optional icon, a human-friendly message, and
/// an optional retry button.
///
/// Provide either a raw [error] (resolved via [friendlyErrorMessage] using
/// [fallbackMessage]) or a pre-computed [message]. Renders an intrinsically
/// sized [Column] so callers control the outer layout (Center/Padding/sliver).
/// Pass [icon] `null` to omit the icon entirely, and [messageStyle] to override
/// the message text style.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.error,
    this.message,
    this.fallbackMessage = 'Data belum dapat dimuat. Silakan coba lagi.',
    this.onRetry,
    this.retryLabel = 'Coba lagi',
    this.icon = Icons.cloud_off_rounded,
    this.iconSize = 40,
    this.iconColor,
    this.messageStyle,
  }) : assert(
         error != null || message != null,
         'Provide either an error or a message',
       );

  final Object? error;
  final String? message;
  final String fallbackMessage;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData? icon;
  final double iconSize;
  final Color? iconColor;
  final TextStyle? messageStyle;

  @override
  Widget build(BuildContext context) {
    final text =
        message ?? friendlyErrorMessage(error!, fallbackMessage: fallbackMessage);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: iconColor),
          const SizedBox(height: 12),
        ],
        Text(text, textAlign: TextAlign.center, style: messageStyle),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(retryLabel),
          ),
        ],
      ],
    );
  }
}
