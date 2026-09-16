import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../profile/presentation/widgets/currency_picker.dart';

import '../providers/settings_providers.dart';

/// App preferences: appearance, language, data, danger zone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(persistedThemeModeProvider);
    final String language = ref.watch(languageProvider);
    final bool notifications = ref.watch(notificationsEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: <Widget>[
          const _SectionTitle('Appearance'),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Theme', style: context.text.titleSmall),
                AppSpacing.md.gapH,
                SegmentedButton<ThemeMode>(
                  segments: const <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                    ButtonSegment<ThemeMode>(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                    ButtonSegment<ThemeMode>(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                  ],
                  selected: <ThemeMode>{themeMode},
                  onSelectionChanged: (Set<ThemeMode> selection) => ref.read(persistedThemeModeProvider.notifier).setMode(selection.first),
                ),
              ],
            ),
          ),
          AppSpacing.xl.gapH,

          const _SectionTitle('Preferences'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Language'),
                  subtitle: Text(
                    kSupportedLanguages
                        .firstWhere((({String code, String label}) l) => l.code == language, orElse: () => kSupportedLanguages.first)
                        .label,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => _pickLanguage(context, ref, language),
                ),
                const Divider(height: 1),
                const _CurrencyTile(),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: const Text('Budget alerts and sync updates'),
                  value: notifications,
                  onChanged: (bool value) => ref.read(notificationsEnabledProvider.notifier).setEnabled(enabled: value),
                ),
              ],
            ),
          ),
          AppSpacing.xl.gapH,

          const _SectionTitle('Data'),
          const AppCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(children: <Widget>[_BackupTile(), Divider(height: 1), _RestoreTile()]),
          ),
          AppSpacing.xl.gapH,

          const _SectionTitle('About'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About PocketPilot'),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => context.pushNamed(AppRoutes.about),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                  onTap: () async {
                    final Uri uri = Uri.parse(AppConstants.privacyPolicyUrl);
                    try {
                      final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!launched && context.mounted) {
                        AppFeedback.warning(context, 'Could not open privacy policy URL');
                      }
                    } catch (_) {
                      if (context.mounted) {
                        AppFeedback.warning(context, 'Could not open privacy policy URL');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          AppSpacing.xxl.gapH,

          const _SectionTitle('Danger zone'),
          const _DeleteAccountTile(),
          AppSpacing.xxl.gapH,
        ],
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, String current) async {
    final String? picked = await AppFeedback.sheet<String>(
      context,
      child: AppBottomSheet(
        title: 'Language',
        child: Column(
          children: <Widget>[
            for (final ({String code, String label}) language in kSupportedLanguages)
              ListTile(
                title: Text(language.label),
                trailing: language.code == current ? Icon(Icons.check_circle_rounded, color: context.colors.primary) : null,
                onTap: () => Navigator.of(context).pop(language.code),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      await ref.read(languageProvider.notifier).setLanguage(picked);
      if (context.mounted) {
        AppFeedback.info(context, 'Language updated');
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(text, style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
    );
  }
}

class _CurrencyTile extends ConsumerWidget {
  const _CurrencyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String currency = ref.watch(currencyCodeProvider);
    final ({String code, String name}) current = kSupportedCurrencies.firstWhere(
      (({String code, String name}) c) => c.code == currency,
      orElse: () => (code: currency, name: currency),
    );

    return ListTile(
      leading: const Icon(Icons.payments_outlined),
      title: const Text('Currency'),
      subtitle: Text('${current.code} · ${current.name}'),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () async {
        final String? picked = await AppFeedback.sheet<String>(context, child: CurrencySheet(selected: currency));
        if (picked != null) {
          final user = ref.read(currentUserProvider);
          if (user != null) {
            await ref.read(authProvider.notifier).updateProfile(user.copyWith(currencyCode: picked));
          }
          await ref.read(preferencesServiceProvider).setCurrencyCode(picked);
          ref.invalidate(currencyCodeProvider);
          if (context.mounted) {
            AppFeedback.info(context, 'Currency updated to $picked');
          }
        }
      },
    );
  }
}

class _BackupTile extends ConsumerStatefulWidget {
  const _BackupTile();

  @override
  ConsumerState<_BackupTile> createState() => _BackupTileState();
}

class _BackupTileState extends ConsumerState<_BackupTile> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    final result = await ref.read(backupServiceProvider).export();
    if (!mounted) return;
    setState(() => _busy = false);

    await result.when(
      success: (File file) async {
        await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(file.path)], text: 'PocketPilot backup'));
      },
      failure: (failure) async => AppFeedback.error(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.backup_outlined),
      title: const Text('Back up data'),
      subtitle: const Text('Export everything as a JSON file'),
      trailing: _busy
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: _busy ? null : _backup,
    );
  }
}

class _RestoreTile extends ConsumerStatefulWidget {
  const _RestoreTile();

  @override
  ConsumerState<_RestoreTile> createState() => _RestoreTileState();
}

class _RestoreTileState extends ConsumerState<_RestoreTile> {
  Future<void> _restore() async {
    final TextEditingController controller = TextEditingController();

    final bool? confirmed = await AppFeedback.sheet<bool>(
      context,
      child: AppBottomSheet(
        title: 'Restore from backup',
        actionLabel: 'Restore',
        onAction: () => Navigator.of(context).pop(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Paste the contents of a PocketPilot backup file. Existing '
              'transactions with the same id are overwritten.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            AppSpacing.lg.gapH,
            AppTextField(controller: controller, hint: '{"version": 1, …}', maxLines: 6),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await ref.read(backupServiceProvider).restore(controller.text);
    controller.dispose();

    if (!mounted) return;
    result.when(
      success: (int count) => AppFeedback.success(context, 'Restored $count transactions'),
      failure: (failure) => AppFeedback.error(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.restore_rounded),
      title: const Text('Restore data'),
      subtitle: const Text('Import from a backup file'),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: _restore,
    );
  }
}

class _DeleteAccountTile extends ConsumerWidget {
  const _DeleteAccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: context.colors.error),
        title: Text('Delete account', style: TextStyle(color: context.colors.error)),
        subtitle: const Text('Permanently removes your account and data'),
        onTap: () async {
          final bool confirmed = await AppFeedback.confirm(
            context,
            title: 'Delete your account?',
            message:
                'Every transaction, category and setting will be erased '
                'from this device. This cannot be undone.',
            confirmLabel: 'Delete everything',
            isDestructive: true,
          );
          if (!confirmed) return;

          await ref.read(authProvider.notifier).deleteAccount();
        },
      ),
    );
  }
}
