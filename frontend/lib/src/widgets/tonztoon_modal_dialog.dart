import 'package:flutter/material.dart';

import '../utils/app_assets.dart';
import '../helpers/app_icons.dart';

enum TonztoonModalVariant { primary, danger, success }

enum TonztoonModalArt {
  accountSetup,
  authError,
  closeApp,
  cloudSync,
  editHeaderProfile,
  folder,
  logoutAccount,
  logoutDeviceSession,
  passwordSetup,
  sendToEmail,
  trash,
}

extension TonztoonModalArtAsset on TonztoonModalArt {
  String get assetPath {
    return switch (this) {
      TonztoonModalArt.accountSetup => AppAssets.dialogAccountSetup,
      TonztoonModalArt.authError => AppAssets.dialogAuthError,
      TonztoonModalArt.closeApp => AppAssets.dialogCloseApp,
      TonztoonModalArt.cloudSync => AppAssets.dialogCloudSync,
      TonztoonModalArt.editHeaderProfile => AppAssets.dialogEditHeaderProfile,
      TonztoonModalArt.folder => AppAssets.dialogFolder,
      TonztoonModalArt.logoutAccount => AppAssets.dialogLogoutAccount,
      TonztoonModalArt.logoutDeviceSession =>
        AppAssets.dialogLogoutDeviceSession,
      TonztoonModalArt.passwordSetup => AppAssets.dialogPasswordSetup,
      TonztoonModalArt.sendToEmail => AppAssets.dialogSendToEmail,
      TonztoonModalArt.trash => AppAssets.dialogTrash,
    };
  }
}

class TonztoonModalSupportAction {
  const TonztoonModalSupportAction({
    required this.label,
    required this.icon,
    this.fullWidth = false,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool fullWidth;
  final VoidCallback? onPressed;
}

Future<T?> showTonztoonModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final resolvedBarrierLabel =
      barrierLabel ??
      MaterialLocalizations.of(context).modalBarrierDismissLabel;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: resolvedBarrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: const Duration(milliseconds: 260),
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scaleAnimation = Tween<double>(
        begin: 0.92,
        end: 1,
      ).animate(curvedAnimation);

      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(scale: scaleAnimation, child: child),
      );
    },
  );
}

Future<bool?> showTonztoonConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? eyebrow,
  String? helperText,
  IconData helperIcon = TonztoonIcons.shieldCheck,
  String cancelLabel = 'Batal',
  String confirmLabel = 'Ya',
  TonztoonModalVariant variant = TonztoonModalVariant.primary,
  TonztoonModalArt art = TonztoonModalArt.logoutAccount,
  bool barrierDismissible = true,
}) {
  return showTonztoonModal<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => TonztoonModalDialog(
      title: title,
      message: message,
      eyebrow: eyebrow,
      helperText: helperText,
      helperIcon: helperIcon,
      variant: variant,
      art: art,
      secondaryLabel: cancelLabel,
      onSecondaryPressed: () => Navigator.of(context).pop(false),
      primaryLabel: confirmLabel,
      onPrimaryPressed: () => Navigator.of(context).pop(true),
    ),
  );
}

Future<bool?> showTonztoonAsyncConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() onConfirm,
  void Function(Object error, StackTrace stackTrace)? onError,
  String? eyebrow,
  String? helperText,
  IconData helperIcon = TonztoonIcons.shieldCheck,
  String cancelLabel = 'Batal',
  String confirmLabel = 'Ya',
  TonztoonModalVariant variant = TonztoonModalVariant.primary,
  TonztoonModalArt art = TonztoonModalArt.logoutAccount,
}) {
  return showTonztoonModal<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TonztoonAsyncConfirmDialog(
      title: title,
      message: message,
      onConfirm: onConfirm,
      onError: onError,
      eyebrow: eyebrow,
      helperText: helperText,
      helperIcon: helperIcon,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      variant: variant,
      art: art,
    ),
  );
}

Future<void> showTonztoonNoticeDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? eyebrow,
  String? emphasis,
  String? helperText,
  IconData helperIcon = TonztoonIcons.warning,
  String primaryLabel = 'OK',
  TonztoonModalVariant variant = TonztoonModalVariant.danger,
  TonztoonModalArt art = TonztoonModalArt.authError,
  List<TonztoonModalSupportAction> supportActions = const [],
  VoidCallback? onPrimaryPressed,
}) {
  return showTonztoonModal<void>(
    context: context,
    builder: (context) => TonztoonModalDialog(
      title: title,
      message: message,
      eyebrow: eyebrow,
      emphasis: emphasis,
      helperText: helperText,
      helperIcon: helperIcon,
      variant: variant,
      art: art,
      supportActions: supportActions,
      primaryLabel: primaryLabel,
      onPrimaryPressed: () {
        Navigator.of(context).pop();
        onPrimaryPressed?.call();
      },
    ),
  );
}

class _TonztoonAsyncConfirmDialog extends StatefulWidget {
  const _TonztoonAsyncConfirmDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.variant,
    required this.art,
    this.onError,
    this.eyebrow,
    this.helperText,
    this.helperIcon = TonztoonIcons.shieldCheck,
  });

  final String title;
  final String message;
  final Future<void> Function() onConfirm;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final String? eyebrow;
  final String? helperText;
  final IconData helperIcon;
  final String cancelLabel;
  final String confirmLabel;
  final TonztoonModalVariant variant;
  final TonztoonModalArt art;

  @override
  State<_TonztoonAsyncConfirmDialog> createState() =>
      _TonztoonAsyncConfirmDialogState();
}

class _TonztoonAsyncConfirmDialogState
    extends State<_TonztoonAsyncConfirmDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading,
      child: TonztoonModalDialog(
        title: widget.title,
        message: widget.message,
        eyebrow: widget.eyebrow,
        helperText: widget.helperText,
        helperIcon: widget.helperIcon,
        variant: widget.variant,
        art: widget.art,
        showCloseButton: !_loading,
        secondaryLabel: widget.cancelLabel,
        onSecondaryPressed: _loading
            ? null
            : () => Navigator.of(context).pop(false),
        primaryLabel: widget.confirmLabel,
        primaryLoading: _loading,
        onPrimaryPressed: _loading ? null : _submit,
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onError?.call(error, stackTrace);
    }
  }
}

class TonztoonModalDialog extends StatelessWidget {
  const TonztoonModalDialog({
    super.key,
    this.title,
    this.titleWidget,
    this.message,
    this.primaryLabel,
    this.onPrimaryPressed,
    this.eyebrow,
    this.emphasis,
    this.emphasisStyle,
    this.helperText,
    this.helperIcon = TonztoonIcons.shieldCheck,
    this.content,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.primaryLoading = false,
    this.variant = TonztoonModalVariant.primary,
    this.art = TonztoonModalArt.logoutAccount,
    this.supportActions = const [],
    this.showActions = true,
    this.showCloseButton = true,
    this.contentTopPadding = 92,
  });

  final String? title;
  final Widget? titleWidget;
  final String? message;
  final String? eyebrow;
  final String? emphasis;
  final TextStyle? emphasisStyle;
  final String? helperText;
  final IconData helperIcon;
  final Widget? content;
  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final bool primaryLoading;
  final TonztoonModalVariant variant;
  final TonztoonModalArt art;
  final List<TonztoonModalSupportAction> supportActions;
  final bool showActions;
  final bool showCloseButton;
  final double contentTopPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDanger = variant == TonztoonModalVariant.danger;
    final isSuccess = variant == TonztoonModalVariant.success;
    final accent = isDanger
        ? theme.colorScheme.error
        : isSuccess
        ? const Color(0xFF22C55E)
        : theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final surface = theme.colorScheme.surface;
    final topTint = Color.lerp(surface, accent, isDanger ? 0.10 : 0.18)!;
    final topTintSoft = Color.lerp(surface, accent, isDanger ? 0.05 : 0.09)!;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 374,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 46),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 36,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [topTint, topTintSoft, surface, surface],
                              stops: const [0, 0.22, 0.43, 1],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 28,
                        left: 60,
                        right: 60,
                        child: _ModalTopOrnaments(color: accent),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(24, contentTopPadding, 24, 26),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (eyebrow != null) ...[
                                _Eyebrow(text: eyebrow!, color: accent),
                                const SizedBox(height: 12),
                              ],
                              if (titleWidget != null) ...[
                                titleWidget!,
                              ] else if (title != null && title!.isNotEmpty) ...[
                                Text(
                                  title!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    color: onSurface,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                              if (emphasis != null) ...[
                                const SizedBox(height: 7),
                                Text(
                                  emphasis!,
                                  textAlign: TextAlign.center,
                                  style: emphasisStyle ??
                                      theme.textTheme.titleSmall?.copyWith(
                                        color: accent,
                                        fontWeight: FontWeight.w900,
                                        height: 1.24,
                                      ),
                                ),
                              ],
                              if (message != null &&
                                  message!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  message!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: onSurface.withValues(alpha: 0.54),
                                    height: 1.48,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (helperText != null) ...[
                                const SizedBox(height: 16),
                                _HelperBand(
                                  text: helperText!,
                                  icon: helperIcon,
                                  color: accent,
                                  danger: isDanger,
                                ),
                              ],
                              if (content != null) ...[
                                const SizedBox(height: 16),
                                content!,
                              ],
                              if (supportActions.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _SupportActions(
                                  actions: supportActions,
                                  color: isDanger
                                      ? const Color(0xFF3955A6)
                                      : accent,
                                ),
                              ],
                              if (showActions && primaryLabel != null) ...[
                                const SizedBox(height: 20),
                                _DialogActions(
                                  primaryLabel: primaryLabel!,
                                  secondaryLabel: secondaryLabel,
                                  onPrimaryPressed: onPrimaryPressed,
                                  onSecondaryPressed: onSecondaryPressed,
                                  primaryLoading: primaryLoading,
                                  color: accent,
                                  variant: variant,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (showCloseButton)
                        Positioned(
                          top: 14,
                          right: 14,
                          child: _CloseButton(
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: _ModalHeroIcon(art: art, variant: variant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalHeroIcon extends StatelessWidget {
  const _ModalHeroIcon({required this.art, required this.variant});

  final TonztoonModalArt art;
  final TonztoonModalVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = variant == TonztoonModalVariant.danger;
    final success = variant == TonztoonModalVariant.success;
    final accent = danger
        ? theme.colorScheme.error
        : success
        ? const Color(0xFF22C55E)
        : theme.colorScheme.primary;

    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _HeroHalo(color: accent, variant: variant),
          Image.asset(
            art.assetPath,
            width: 82,
            height: 82,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ],
      ),
    );
  }
}

class _HeroHalo extends StatelessWidget {
  const _HeroHalo({required this.color, required this.variant});

  final Color color;
  final TonztoonModalVariant variant;

  @override
  Widget build(BuildContext context) {
    final success = variant == TonztoonModalVariant.success;
    final solidOuter = success
        ? const Color(0xFFE7FFF1)
        : Color.lerp(Colors.white, color, 0.08)!;
    final solidInner = success
        ? const Color(0xFFBBF7D0)
        : Color.lerp(Colors.white, color, 0.22)!;
    final solidMid = success
        ? const Color(0xFF86EFAC)
        : Color.lerp(Colors.white, color, 0.36)!;
    final solidShade = success
        ? const Color(0xFF16A34A)
        : Color.lerp(Colors.black, color, 0.64)!;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: solidOuter,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.22, -0.34),
              radius: 0.84,
              colors: [Colors.white, solidOuter, solidMid, solidShade],
              stops: const [0, 0.46, 0.72, 1],
            ),
          ),
        ),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                solidInner,
                success
                    ? const Color(0xFF4ADE80)
                    : Color.lerp(solidInner, Colors.black, 0.12)!,
              ],
              stops: const [0, 0.52, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModalTopOrnaments extends StatelessWidget {
  const _ModalTopOrnaments({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 24,
            top: 8,
            child: Transform.rotate(
              angle: -0.28,
              child: Icon(
                Icons.bolt_rounded,
                color: color.withValues(alpha: 0.42),
                size: 26,
              ),
            ),
          ),
          Positioned(
            right: 25,
            top: 8,
            child: Transform.rotate(
              angle: 0.26,
              child: Icon(
                Icons.bolt_rounded,
                color: color.withValues(alpha: 0.42),
                size: 26,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 24,
            child: Icon(
              TonztoonIcons.autoAwesome,
              color: color.withValues(alpha: 0.34),
              size: 12,
            ),
          ),
          Positioned(
            right: 12,
            top: 24,
            child: Icon(
              TonztoonIcons.autoAwesome,
              color: color.withValues(alpha: 0.34),
              size: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HelperBand extends StatelessWidget {
  const _HelperBand({
    required this.text,
    required this.icon,
    required this.color,
    required this.danger,
  });

  final String text;
  final IconData icon;
  final Color color;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconBackground = isDark
        ? Color.alphaBlend(
            color.withValues(alpha: danger ? 0.18 : 0.14),
            colorScheme.surfaceContainerHighest,
          )
        : Colors.white.withValues(alpha: 0.68);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: danger ? 0.14 : 0.10),
            color.withValues(alpha: danger ? 0.08 : 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              key: const ValueKey('tonztoon-modal-helper-icon-background'),
              width: 40,
              height: 38,
              decoration: BoxDecoration(
                color: iconBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportActions extends StatelessWidget {
  const _SupportActions({required this.actions, required this.color});

  final List<TonztoonModalSupportAction> actions;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasFullWidth = actions.any((action) => action.fullWidth);
    if (hasFullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in actions) ...[
            _SupportActionButton(action: action, color: color),
            if (action != actions.last) const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final action in actions)
          _SupportActionButton(action: action, color: color),
      ],
    );
  }
}

class _SupportActionButton extends StatelessWidget {
  const _SupportActionButton({required this.action, required this.color});

  final TonztoonModalSupportAction action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: action.onPressed,
      icon: Icon(action.icon, size: 17),
      label: Text(action.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: Size(action.fullWidth ? double.infinity : 142, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.primaryLabel,
    required this.onPrimaryPressed,
    required this.color,
    required this.variant,
    this.primaryLoading = false,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final bool primaryLoading;
  final Color color;
  final TonztoonModalVariant variant;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (secondaryLabel != null)
        Expanded(
          child: OutlinedButton(
            onPressed: onSecondaryPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.7),
                width: 1.5,
              ),
              minimumSize: const Size(0, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
            child: Text(secondaryLabel!),
          ),
        ),
      Expanded(
        child: _GradientActionButton(
          label: primaryLabel,
          color: color,
          variant: variant,
          loading: primaryLoading,
          onPressed: onPrimaryPressed,
        ),
      ),
    ];

    if (buttons.length == 1) {
      return Row(children: buttons);
    }

    return Row(
      children: [buttons.first, const SizedBox(width: 16), buttons.last],
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.label,
    required this.color,
    required this.variant,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final TonztoonModalVariant variant;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = switch (variant) {
      TonztoonModalVariant.danger => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF8190), Color(0xFFE51F3F), Color(0xFFB90F2E)],
      ),
      TonztoonModalVariant.success => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF86EFAC), Color(0xFF22C55E), Color(0xFF16A34A)],
      ),
      TonztoonModalVariant.primary => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFB640), Color(0xFFFF850F), Color(0xFFFF5F00)],
      ),
    };

    final enabled = onPressed != null && !loading;

    return Opacity(
      opacity: enabled || loading ? 1 : 0.68,
      child: DecoratedBox(
        key: const ValueKey('tonztoon-modal-primary-action-decoration'),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isDark ? 0.24 : 0.16),
              blurRadius: isDark ? 14 : 11,
              spreadRadius: isDark ? 0.5 : 0,
              offset: Offset(0, isDark ? 6 : 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
              blurRadius: isDark ? 8 : 6,
              offset: Offset(0, isDark ? 3 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 52,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading) ...[
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const closeColor = Color(0xFFEF4444);

    return SizedBox.square(
      dimension: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: closeColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: closeColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            tooltip: 'Tutup',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 42, height: 42),
            onPressed: onPressed,
            icon: const SizedBox.square(
              dimension: 18,
              child: CustomPaint(painter: _CloseIconPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseIconPainter extends CustomPainter {
  const _CloseIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    const inset = 3.0;

    canvas
      ..drawLine(
        const Offset(inset, inset),
        Offset(size.width - inset, size.height - inset),
        paint,
      )
      ..drawLine(
        Offset(size.width - inset, inset),
        Offset(inset, size.height - inset),
        paint,
      );
  }

  @override
  bool shouldRepaint(_CloseIconPainter oldDelegate) => false;
}
