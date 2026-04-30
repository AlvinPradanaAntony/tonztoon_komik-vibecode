import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AppAsyncView<ReaderPreferences>(
        value: prefs,
        onRetry: () => ref.invalidate(readerPreferencesProvider),
        builder: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Reader', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'vertical',
                  icon: Icon(Icons.view_agenda_outlined),
                  label: Text('Vertical'),
                ),
                ButtonSegment(
                  value: 'paged',
                  icon: Icon(Icons.auto_stories_outlined),
                  label: Text('Paged'),
                ),
              ],
              selected: {value.defaultReadingMode},
              onSelectionChanged: (selected) => _save(
                ref,
                value.copyWith(defaultReadingMode: selected.first),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ltr', label: Text('LTR')),
                ButtonSegment(value: 'rtl', label: Text('RTL')),
              ],
              selected: {value.readingDirection},
              onSelectionChanged: (selected) =>
                  _save(ref, value.copyWith(readingDirection: selected.first)),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: value.autoNext,
              title: const Text('Auto-next chapter'),
              onChanged: (enabled) =>
                  _save(ref, value.copyWith(autoNext: enabled)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: value.markReadOnComplete,
              title: const Text('Mark read on complete'),
              onChanged: (enabled) =>
                  _save(ref, value.copyWith(markReadOnComplete: enabled)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: value.defaultBingeMode,
              title: const Text('Binge mode default'),
              onChanged: (enabled) =>
                  _save(ref, value.copyWith(defaultBingeMode: enabled)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await ref.read(localStoreProvider).cache.clear();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared.')),
                  );
                }
              },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear catalog cache'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(WidgetRef ref, ReaderPreferences prefs) async {
    await ref.read(libraryRepositoryProvider).saveReaderPreferences(prefs);
    ref.invalidate(readerPreferencesProvider);
  }
}
