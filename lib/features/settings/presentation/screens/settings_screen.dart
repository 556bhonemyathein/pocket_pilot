import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
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

/// App preferences: appearance, currency, data, danger zone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(persistedThemeModeProvider);
    final bool notifications = ref.watch(notificationsEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: <Widget>[
          _SectionTitle('appearance'.tr()),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('theme'.tr(), style: context.text.titleSmall),
                AppSpacing.md.gapH,
                SegmentedButton<ThemeMode>(
                  segments: <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text('light'.tr())),
                    ButtonSegment<ThemeMode>(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_outlined), label: Text('system'.tr())),
                    ButtonSegment<ThemeMode>(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text('dark'.tr())),
                  ],
                  selected: <ThemeMode>{themeMode},
                  onSelectionChanged: (Set<ThemeMode> selection) => ref.read(persistedThemeModeProvider.notifier).setMode(selection.first),
                ),
              ],
            ),
          ),
          AppSpacing.xl.gapH,

          _SectionTitle('preferences'.tr()),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: <Widget>[
                const _CurrencyTile(),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: Text('notifications'.tr()),
                  subtitle: Text('budget_alerts_and_sync_updates'.tr()),
                  value: notifications,
                  onChanged: (bool value) => ref.read(notificationsEnabledProvider.notifier).setEnabled(enabled: value),
                ),
              ],
            ),
          ),
          AppSpacing.xl.gapH,

          _SectionTitle('data'.tr()),
          const AppCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(children: <Widget>[_BackupTile(), Divider(height: 1), _RestoreTile()]),
          ),
          AppSpacing.xl.gapH,

          _SectionTitle('about'.tr()),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text('about_pocketpilot'.tr()),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => context.pushNamed(AppRoutes.about),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text('privacy_policy_2'.tr()),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                  onTap: () async {
                    final Uri uri = Uri.parse(AppConstants.privacyPolicyUrl);
                    try {
                      final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!launched && context.mounted) {
                        AppFeedback.warning(context, 'could_not_open_privacy_policy_url'.tr());
                      }
                    } catch (_) {
                      if (context.mounted) {
                        AppFeedback.warning(context, 'could_not_open_privacy_policy_url'.tr());
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          AppSpacing.xxl.gapH,

          _SectionTitle('danger_zone'.tr()),
          const _DeleteAccountTile(),
          AppSpacing.xxl.gapH,
        ],
      ),
    );
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
      title: Text('currency'.tr()),
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
            AppFeedback.info(context, 'currency_updated_to_picked'.tr(namedArgs: <String, String>{'picked': picked}));
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
      title: Text('back_up_data'.tr()),
      subtitle: Text('export_everything_as_a_json_file'.tr()),
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
        title: 'restore_from_backup'.tr(),
        actionLabel: 'restore'.tr(),
        onAction: () => Navigator.of(context).pop(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'paste_the_contents_of_a_pocketpilot_backup_file'.tr(),
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
      success: (int count) => AppFeedback.success(context, 'restored_count_transactions'.tr(namedArgs: <String, String>{'count': '$count'})),
      failure: (failure) => AppFeedback.error(context, failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.restore_rounded),
      title: Text('restore_data'.tr()),
      subtitle: Text('import_from_a_backup_file'.tr()),
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
        title: Text('delete_account'.tr(), style: TextStyle(color: context.colors.error)),
        subtitle: Text('permanently_removes_your_account_and_data'.tr()),
        onTap: () async {
          final bool confirmed = await AppFeedback.confirm(
            context,
            title: 'delete_your_account'.tr(),
            message:
                'every_transaction_category_and_setting_will_be_e'.tr(),
            confirmLabel: 'delete_everything'.tr(),
            isDestructive: true,
          );
          if (!confirmed) return;

          await ref.read(authProvider.notifier).deleteAccount();
        },
      ),
    );
  }
}
