import 'package:flutter/material.dart';

import '../core/app_icons.dart';
import '../models/helpdesk.dart';
import 'tonztoon_modal_dialog.dart';

Future<HelpdeskSubmissionReceipt?> showHelpdeskDialog(
  BuildContext context, {
  required Future<HelpdeskSubmissionReceipt> Function(
    HelpdeskSubmissionDraft draft,
  )
  onSubmit,
}) {
  return showTonztoonModal<HelpdeskSubmissionReceipt>(
    context: context,
    builder: (context) => HelpdeskDialog(onSubmit: onSubmit),
  );
}

class HelpdeskDialog extends StatefulWidget {
  const HelpdeskDialog({super.key, required this.onSubmit});

  final Future<HelpdeskSubmissionReceipt> Function(
    HelpdeskSubmissionDraft draft,
  )
  onSubmit;

  @override
  State<HelpdeskDialog> createState() => _HelpdeskDialogState();
}

class _HelpdeskDialogState extends State<HelpdeskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  HelpdeskCategory? _category;
  int _rating = 5;
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;

    return PopScope(
      canPop: !_submitting,
      child: TonztoonModalDialog(
        eyebrow: 'HELPDESK',
        title: 'Ada yang ingin disampaikan?',
        message:
            'Bagikan pengalamanmu atau laporkan masalah agar TonzToon terus membaik.',
        art: TonztoonModalArt.sendToEmail,
        showCloseButton: !_submitting,
        content: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _CategoryCard(
                      key: const ValueKey('helpdesk-review-card'),
                      title: 'Review',
                      subtitle: 'Beri nilai dan masukan',
                      icon: TonztoonIcons.star,
                      selected: category == HelpdeskCategory.review,
                      enabled: !_submitting,
                      onTap: () => _selectCategory(HelpdeskCategory.review),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CategoryCard(
                      key: const ValueKey('helpdesk-report-card'),
                      title: 'Report',
                      subtitle: 'Laporkan kendala aplikasi',
                      icon: TonztoonIcons.bug,
                      selected: category == HelpdeskCategory.report,
                      enabled: !_submitting,
                      onTap: () => _selectCategory(HelpdeskCategory.report),
                    ),
                  ),
                ],
              ),
              if (category != null) ...[
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: category == HelpdeskCategory.review
                      ? _ReviewForm(
                          key: const ValueKey('helpdesk-review-form'),
                          rating: _rating,
                          enabled: !_submitting,
                          messageController: _messageController,
                          onRatingChanged: (rating) {
                            setState(() => _rating = rating);
                          },
                        )
                      : _ReportForm(
                          key: const ValueKey('helpdesk-report-form'),
                          enabled: !_submitting,
                          titleController: _titleController,
                          messageController: _messageController,
                        ),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: _submitError!),
              ],
            ],
          ),
        ),
        secondaryLabel: 'Batal',
        onSecondaryPressed: _submitting
            ? null
            : () => Navigator.of(context).pop(),
        primaryLabel: category == null ? 'Pilih' : 'Kirim',
        primaryLoading: _submitting,
        onPrimaryPressed: category == null || _submitting ? null : _submit,
      ),
    );
  }

  void _selectCategory(HelpdeskCategory category) {
    if (_submitting || category == _category) return;
    setState(() {
      _category = category;
      _submitError = null;
      _titleController.clear();
      _messageController.clear();
      _rating = 5;
    });
  }

  Future<void> _submit() async {
    final category = _category;
    if (_submitting || category == null) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final receipt = await widget.onSubmit(
        HelpdeskSubmissionDraft(
          category: category,
          rating: category == HelpdeskCategory.review ? _rating : null,
          title: category == HelpdeskCategory.report
              ? _titleController.text.trim()
              : null,
          message: _messageController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(receipt);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error.toString();
      });
    }
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = selected ? colors.primary : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$title, $subtitle',
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.11)
            : colors.surfaceContainerHighest.withValues(alpha: 0.58),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.7),
            width: selected ? 1.8 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(height: 9),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.55),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewForm extends StatelessWidget {
  const _ReviewForm({
    super.key,
    required this.rating,
    required this.enabled,
    required this.messageController,
    required this.onRatingChanged,
  });

  final int rating;
  final bool enabled;
  final TextEditingController messageController;
  final ValueChanged<int> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Seberapa puas kamu?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Semantics(
          label: 'Rating $rating dari 5',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 1; index <= 5; index++)
                IconButton(
                  key: ValueKey('helpdesk-rating-$index'),
                  tooltip: '$index bintang',
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? () => onRatingChanged(index) : null,
                  icon: Icon(
                    index <= rating
                        ? TonztoonIcons.starFilled
                        : TonztoonIcons.star,
                    color: index <= rating
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('helpdesk-review-message'),
          controller: messageController,
          enabled: enabled,
          minLines: 3,
          maxLines: 5,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Tulis review',
            hintText: 'Ceritakan hal yang kamu suka atau perlu ditingkatkan.',
            alignLabelWithHint: true,
          ),
          validator: _validateMessage,
        ),
      ],
    );
  }
}

class _ReportForm extends StatelessWidget {
  const _ReportForm({
    super.key,
    required this.enabled,
    required this.titleController,
    required this.messageController,
  });

  final bool enabled;
  final TextEditingController titleController;
  final TextEditingController messageController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          key: const ValueKey('helpdesk-report-title'),
          controller: titleController,
          enabled: enabled,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Judul masalah',
            hintText: 'Contoh: Chapter tidak dapat dibuka',
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'Judul masalah wajib diisi.';
            if (text.length < 5) return 'Judul masalah terlalu singkat.';
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('helpdesk-report-message'),
          controller: messageController,
          enabled: enabled,
          minLines: 4,
          maxLines: 7,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Detail masalah',
            hintText:
                'Jelaskan apa yang terjadi dan langkah sebelum masalah muncul.',
            alignLabelWithHint: true,
          ),
          validator: _validateMessage,
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(TonztoonIcons.warning, color: colors.error, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _validateMessage(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Pesan wajib diisi.';
  if (text.length < 10) return 'Ceritakan sedikit lebih detail.';
  return null;
}
